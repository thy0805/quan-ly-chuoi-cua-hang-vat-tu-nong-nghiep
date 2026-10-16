import 'dart:convert';

import '../core/numbers.dart';
import 'models.dart';
import 'request_models.dart';

class DispatchLine {
  DispatchLine(String lot, String amount)
    : lotId = jsonId(lot),
      quantity = FixedDecimal.parse(amount, scale: 3, wholeDigits: 15) {
    if (quantity.atoms <= BigInt.zero) {
      throw const FormatException('Số xuất phải lớn hơn 0.');
    }
  }
  final String lotId;
  final FixedDecimal quantity;
  TransferJson toJson() => {
    'lot_id': lotId,
    'dispatched_quantity': quantity.toString(),
  };
}

List<DispatchLine> dispatchLines(Object? value) {
  final lines = (value as List).map((row) {
    final data = row as TransferJson;
    if (data.length != 2) throw const FormatException('Sai dòng xuất.');
    return DispatchLine(
      jsonId(data['lot_id']),
      data['dispatched_quantity'] as String,
    );
  }).toList();
  if (lines.isEmpty ||
      lines.length > 50 ||
      lines.map((e) => e.lotId).toSet().length != lines.length) {
    throw const FormatException('Cần 1–50 lô riêng, mỗi lô đúng một lần.');
  }
  return List.unmodifiable(lines);
}

class DispatchDetail {
  DispatchDetail.fromJson(TransferJson json)
    : detail = TransferDetail.fromJson(json),
      requestedBy = jsonId((json['data'] as TransferJson)['requested_by']),
      chainId = jsonId((json['data'] as TransferJson)['chain_id']),
      canDispatch = (json['data'] as TransferJson)['can_dispatch'] as bool,
      dispatchedBy = (json['data'] as TransferJson)['dispatched_by'] == null
          ? null
          : jsonId((json['data'] as TransferJson)['dispatched_by']) {
    if (detail.items.isEmpty ||
        detail.items.length > 50 ||
        detail.transfer.fromWarehouseId == detail.transfer.toWarehouseId ||
        detail.items.any((e) => e.requested.atoms <= BigInt.zero)) {
      throw const FormatException('Phiếu không có tập lô hợp lệ.');
    }
  }
  final TransferDetail detail;
  final String requestedBy, chainId;
  final String? dispatchedBy;
  final bool canDispatch;

  List<TransferLine> get sorted =>
      [...detail.items]..sort((a, b) => a.lotId.compareTo(b.lotId));

  String get fingerprint => jsonEncode({
    'id': detail.transfer.id,
    'number': detail.transfer.number,
    'requested_by': requestedBy,
    'chain_id': chainId,
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
        },
    ],
  });

  bool allowed(String branch) =>
      detail.transfer.fromBranchId == branch &&
      detail.transfer.status == 'approved' &&
      canDispatch;

  void validateOptionsScope(TransferOptions? options) {
    final source = options?.sources
        .where((e) => e.id == detail.transfer.fromWarehouseId)
        .firstOrNull;
    if (source != null &&
        (source.branchId != detail.transfer.fromBranchId ||
            source.chainId != chainId)) {
      throw const FormatException('Snapshot tồn nguồn sai phạm vi.');
    }
  }

  void validate(List<DispatchLine> lines, {TransferOptions? options}) {
    validateOptionsScope(options);
    final source = options?.sources
        .where((e) => e.id == detail.transfer.fromWarehouseId)
        .firstOrNull;
    final parsed = dispatchLines([for (final line in lines) line.toJson()]);
    if (parsed.length != detail.items.length ||
        parsed.any((e) => !detail.items.any((i) => i.lotId == e.lotId))) {
      throw const FormatException('Số xuất phải chứa đúng tập lô của phiếu.');
    }
    for (final line in parsed) {
      final item = detail.items.singleWhere((i) => i.lotId == line.lotId);
      if (line.quantity.compareTo(item.requested) > 0) {
        throw const FormatException('Số xuất không được vượt số yêu cầu.');
      }
      final stock = source == null
          ? null
          : options
                ?.lotsFor(detail.transfer.fromWarehouseId)
                .where((e) => e.lotId == line.lotId)
                .firstOrNull;
      if (stock != null && line.quantity.compareTo(stock.quantity) > 0) {
        throw const FormatException('Số xuất vượt tồn nguồn vừa tải.');
      }
    }
  }

  TransferJson get observation => {
    'transfer_id': detail.transfer.id,
    'status': detail.transfer.status,
    'dispatched_by': dispatchedBy,
    'dispatched_at': detail.times['dispatched_at']?.toIso8601String(),
    'items': [
      for (final row in sorted)
        {'lot_id': row.lotId, 'dispatched_quantity': row.dispatched.toString()},
    ],
  };

  String? evidence(DispatchAttempt attempt, String user) {
    if (fingerprint != attempt.fingerprint ||
        !{
          'dispatched',
          'received',
          'discrepancy',
          'reconciled',
        }.contains(detail.transfer.status) ||
        dispatchedBy == null ||
        detail.times['dispatched_at'] == null) {
      return null;
    }
    final matches = attempt.lines.every(
      (line) => sorted.any(
        (item) =>
            item.lotId == line.lotId &&
            item.dispatched.compareTo(line.quantity) == 0,
      ),
    );
    return dispatchedBy == user && matches ? 'verified' : 'handled_elsewhere';
  }
}

class DispatchAttempt {
  DispatchAttempt({
    required this.attemptId,
    required this.id,
    required this.branchId,
    required List<DispatchLine> lines,
    required this.fingerprint,
    required this.createdAt,
    required this.phase,
  }) : lines = List.unmodifiable(lines);

  factory DispatchAttempt.fromJson(TransferJson json) {
    final id = jsonId(json['transfer_id']);
    final branch = jsonId(json['branch_id']);
    final attempt = json['attempt_id'] as String;
    final created = json['created_at'] as String;
    final phase = json['phase'] as String;
    final fingerprint = json['fingerprint'] as String;
    final original = jsonDecode(fingerprint) as TransferJson;
    final lines = dispatchLines(json['items']);
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
        original['from_branch'] != branch ||
        items.length != lines.length ||
        items.map((e) => (e as Map)['lot_id']).toSet().length != items.length) {
      throw const FormatException('Marker xuất kho không hợp lệ.');
    }
    for (final line in lines) {
      final item = items.where((e) => e['lot_id'] == line.lotId).single;
      final requested = FixedDecimal.parse(
        item['requested_quantity'] as String,
        scale: 3,
        wholeDigits: 15,
      );
      if (line.quantity.compareTo(requested) > 0) {
        throw const FormatException('Marker xuất vượt lượng yêu cầu.');
      }
    }
    return DispatchAttempt(
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
  final List<DispatchLine> lines;
  DispatchAttempt withPhase(String phase) => DispatchAttempt(
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
