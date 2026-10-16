import 'dart:convert';

import '../core/numbers.dart';
import 'models.dart';

class ReceiveLine {
  ReceiveLine(String lot, String amount)
    : lotId = jsonId(lot),
      quantity = FixedDecimal.parse(amount, scale: 3, wholeDigits: 15) {
    if (quantity.atoms < BigInt.zero) {
      throw const FormatException('Số nhận không được âm.');
    }
  }
  final String lotId;
  final FixedDecimal quantity;
  TransferJson toJson() => {
    'lot_id': lotId,
    'received_quantity': quantity.toString(),
  };
}

List<ReceiveLine> receiveLines(Object? value) {
  final lines = (value as List).map((row) {
    final data = row as TransferJson;
    if (data.length != 2) throw const FormatException('Sai dòng nhận.');
    return ReceiveLine(
      jsonId(data['lot_id']),
      data['received_quantity'] as String,
    );
  }).toList();
  if (lines.isEmpty ||
      lines.length > 50 ||
      lines.map((e) => e.lotId).toSet().length != lines.length) {
    throw const FormatException('Cần 1–50 lô riêng, mỗi lô đúng một lần.');
  }
  return List.unmodifiable(lines);
}

class ReceiveDetail {
  ReceiveDetail.fromJson(TransferJson json)
    : detail = TransferDetail.fromJson(json),
      requestedBy = jsonId((json['data'] as TransferJson)['requested_by']),
      chainId = jsonId((json['data'] as TransferJson)['chain_id']),
      dispatchedBy = jsonId((json['data'] as TransferJson)['dispatched_by']),
      canReceive = (json['data'] as TransferJson)['can_receive'] as bool,
      receivedBy = (json['data'] as TransferJson)['received_by'] == null
          ? null
          : jsonId((json['data'] as TransferJson)['received_by']) {
    if (detail.times['dispatched_at'] == null ||
        detail.items.isEmpty ||
        detail.items.length > 50 ||
        detail.transfer.fromWarehouseId == detail.transfer.toWarehouseId ||
        detail.items.any(
          (e) =>
              e.dispatched.atoms <= BigInt.zero ||
              e.dispatched.compareTo(e.requested) > 0 ||
              e.received.atoms < BigInt.zero ||
              e.received.compareTo(e.dispatched) > 0,
        )) {
      throw const FormatException('Phiếu không có tập lô hợp lệ.');
    }
  }
  final TransferDetail detail;
  final String requestedBy, chainId, dispatchedBy;
  final String? receivedBy;
  final bool canReceive;

  List<TransferLine> get sorted =>
      [...detail.items]..sort((a, b) => a.lotId.compareTo(b.lotId));

  String get fingerprint => jsonEncode({
    'id': detail.transfer.id,
    'number': detail.transfer.number,
    'requested_by': requestedBy,
    'chain_id': chainId,
    'dispatched_by': dispatchedBy,
    'dispatched_at': detail.times['dispatched_at']!.toIso8601String(),
    'requested_at': detail.transfer.requestedAt.toIso8601String(),
    'from': detail.transfer.fromWarehouseId,
    'to': detail.transfer.toWarehouseId,
    'from_branch': detail.transfer.fromBranchId,
    'to_branch': detail.transfer.toBranchId,
    'items': [
      for (final item in sorted)
        {
          'id': item.id,
          'lot_id': item.lotId,
          'requested_quantity': item.requested.toString(),
          'dispatched_quantity': item.dispatched.toString(),
        },
    ],
  });

  bool allowed(String branch) =>
      detail.transfer.toBranchId == branch &&
      detail.transfer.status == 'dispatched' &&
      canReceive;

  void validate(List<ReceiveLine> lines) {
    final parsed = receiveLines([for (final line in lines) line.toJson()]);
    if (parsed.length != detail.items.length ||
        parsed.any((e) => !detail.items.any((i) => i.lotId == e.lotId))) {
      throw const FormatException('Số nhận phải chứa đúng tập lô của phiếu.');
    }
    for (final line in parsed) {
      final item = detail.items.singleWhere((i) => i.lotId == line.lotId);
      if (line.quantity.compareTo(item.dispatched) > 0) {
        throw const FormatException('Số nhận không được vượt số đã xuất.');
      }
    }
  }

  String expectedStatus(List<ReceiveLine> lines) {
    validate(lines);
    return lines.any(
          (line) =>
              line.quantity.compareTo(
                detail.items
                    .singleWhere((i) => i.lotId == line.lotId)
                    .dispatched,
              ) <
              0,
        )
        ? 'discrepancy'
        : 'received';
  }

  TransferJson get observation => {
    'transfer_id': detail.transfer.id,
    'status': detail.transfer.status,
    'received_by': receivedBy,
    'received_at': detail.times['received_at']?.toIso8601String(),
    'items': [
      for (final row in sorted)
        {'lot_id': row.lotId, 'received_quantity': row.received.toString()},
    ],
  };

  String? evidence(ReceiveAttempt attempt, String user) {
    if (fingerprint != attempt.fingerprint ||
        !{'received', 'discrepancy'}.contains(detail.transfer.status) ||
        receivedBy == null ||
        detail.times['received_at'] == null) {
      return null;
    }
    final actual = [
      for (final item in sorted)
        ReceiveLine(item.lotId, item.received.toString()),
    ];
    if (expectedStatus(actual) != detail.transfer.status) return null;
    final matches =
        detail.transfer.status == expectedStatus(attempt.lines) &&
        attempt.lines.every(
          (line) => sorted.any(
            (item) =>
                item.lotId == line.lotId &&
                item.received.compareTo(line.quantity) == 0,
          ),
        );
    return receivedBy == user && matches ? 'verified' : 'handled_elsewhere';
  }
}

class ReceiveAttempt {
  ReceiveAttempt({
    required this.attemptId,
    required this.id,
    required this.branchId,
    required List<ReceiveLine> lines,
    required this.fingerprint,
    required this.createdAt,
    required this.phase,
  }) : lines = List.unmodifiable(lines);

  factory ReceiveAttempt.fromJson(TransferJson json) {
    final id = jsonId(json['transfer_id']);
    final branch = jsonId(json['branch_id']);
    final attempt = json['attempt_id'] as String;
    final created = json['created_at'] as String;
    final phase = json['phase'] as String;
    final fingerprint = json['fingerprint'] as String;
    final original = jsonDecode(fingerprint) as TransferJson;
    final lines = receiveLines(json['items']);
    final items = original['items'] as List;
    if (!RegExp(r'^[a-f0-9]{32}$').hasMatch(attempt) ||
        !DateTime.parse(created).isUtc ||
        !{
          'pending',
          'unknown',
          'verified',
          'handled_elsewhere',
          'denied',
        }.contains(phase) ||
        original['id'] != id ||
        original['to_branch'] != branch ||
        items.length != lines.length ||
        items.map((e) => (e as Map)['lot_id']).toSet().length != items.length) {
      throw const FormatException('Marker nhận hàng không hợp lệ.');
    }
    for (final line in lines) {
      final item = items.where((e) => e['lot_id'] == line.lotId).single;
      final dispatched = FixedDecimal.parse(
        item['dispatched_quantity'] as String,
        scale: 3,
        wholeDigits: 15,
      );
      if (line.quantity.compareTo(dispatched) > 0) {
        throw const FormatException('Marker nhận vượt lượng đã xuất.');
      }
    }
    return ReceiveAttempt(
      attemptId: attempt,
      id: id,
      branchId: branch,
      lines: lines,
      fingerprint: fingerprint,
      createdAt: created,
      phase: phase,
    );
  }

  final String attemptId, id, branchId, fingerprint, createdAt, phase;
  final List<ReceiveLine> lines;
  ReceiveAttempt withPhase(String phase) => ReceiveAttempt(
    attemptId: attemptId,
    id: id,
    branchId: branchId,
    lines: lines,
    fingerprint: fingerprint,
    createdAt: createdAt,
    phase: phase,
  );
  TransferJson toJson() => {
    'attempt_id': attemptId,
    'transfer_id': id,
    'branch_id': branchId,
    'items': [for (final line in lines) line.toJson()],
    'fingerprint': fingerprint,
    'created_at': createdAt,
    'phase': phase,
  };
}
