import 'dart:convert';

import '../core/numbers.dart';
import 'models.dart';

String reconcileReason(String value) {
  final reason = value.trim();
  if (reason.runes.length < 3 || reason.runes.length > 1000) {
    throw const FormatException(
      'Lý do cần từ 3 đến 1000 ký tự sau khi bỏ khoảng trắng đầu cuối.',
    );
  }
  return reason;
}

class ReconcileLine {
  ReconcileLine(String lot, String supplemental, String returned, String lost)
    : lotId = jsonId(lot),
      supplemental = _amount(supplemental),
      returned = _amount(returned),
      lost = _amount(lost);

  static FixedDecimal _amount(String value) {
    final amount = FixedDecimal.parse(value, scale: 3, wholeDigits: 15);
    if (amount.atoms < BigInt.zero) {
      throw const FormatException('Số đối soát không được âm.');
    }
    return amount;
  }

  final String lotId;
  final FixedDecimal supplemental, returned, lost;
  FixedDecimal get total => supplemental + returned + lost;
  TransferJson toJson() => {
    'lot_id': lotId,
    'supplemental_received_quantity': supplemental.toString(),
    'returned_quantity': returned.toString(),
    'lost_quantity': lost.toString(),
  };
  bool same(ReconcileLine other) =>
      lotId == other.lotId &&
      supplemental.compareTo(other.supplemental) == 0 &&
      returned.compareTo(other.returned) == 0 &&
      lost.compareTo(other.lost) == 0;
}

List<ReconcileLine> reconcileLines(Object? value) {
  final lines = (value as List).map((row) {
    final data = row as TransferJson;
    if (data.length != 4) throw const FormatException('Sai dòng đối soát.');
    return ReconcileLine(
      jsonId(data['lot_id']),
      data['supplemental_received_quantity'] as String,
      data['returned_quantity'] as String,
      data['lost_quantity'] as String,
    );
  }).toList();
  if (lines.isEmpty ||
      lines.length > 50 ||
      lines.map((e) => e.lotId).toSet().length != lines.length) {
    throw const FormatException('Cần 1–50 lô riêng, mỗi lô đúng một lần.');
  }
  return List.unmodifiable(lines);
}

void validateReconciliation(TransferJson snapshot, List<ReconcileLine> lines) {
  final items = snapshot['items'] as List;
  if (items.length != lines.length ||
      items.map((e) => (e as Map)['lot_id']).toSet().length != items.length) {
    throw const FormatException('Phải đối soát đúng tập lô của phiếu.');
  }
  for (final line in lines) {
    final item = items.where((e) => e['lot_id'] == line.lotId).single;
    final dispatched = FixedDecimal.parse(
      item['dispatched_quantity'] as String,
      scale: 3,
      wholeDigits: 15,
    );
    final received = FixedDecimal.parse(
      item['received_quantity'] as String,
      scale: 3,
      wholeDigits: 15,
    );
    if (dispatched.atoms <= BigInt.zero ||
        received.atoms < BigInt.zero ||
        received.compareTo(dispatched) > 0 ||
        line.total.compareTo(dispatched - received) != 0) {
      throw const FormatException(
        'Nhận bổ sung + hoàn nguồn + hao hụt phải bằng phần thiếu của từng lô.',
      );
    }
  }
}

class ReconcileDetail {
  ReconcileDetail.fromJson(TransferJson json)
    : detail = TransferDetail.fromJson(json),
      requestedBy = jsonId((json['data'] as TransferJson)['requested_by']),
      chainId = jsonId((json['data'] as TransferJson)['chain_id']),
      dispatchedBy = jsonId((json['data'] as TransferJson)['dispatched_by']),
      receivedBy = jsonId((json['data'] as TransferJson)['received_by']),
      canReconcile = (json['data'] as TransferJson)['can_reconcile'] as bool,
      reconciledBy = (json['data'] as TransferJson)['reconciled_by'] == null
          ? null
          : jsonId((json['data'] as TransferJson)['reconciled_by']) {
    if (detail.times['dispatched_at'] == null ||
        detail.times['received_at'] == null ||
        detail.items.isEmpty ||
        detail.items.length > 50 ||
        detail.transfer.fromWarehouseId == detail.transfer.toWarehouseId ||
        detail.items.any(
          (e) =>
              e.dispatched.atoms <= BigInt.zero ||
              e.dispatched.compareTo(e.requested) > 0 ||
              e.received.compareTo(e.dispatched) > 0,
        )) {
      throw const FormatException('Phiếu không có snapshot xuất/nhận hợp lệ.');
    }
  }

  final TransferDetail detail;
  final String requestedBy, chainId, dispatchedBy, receivedBy;
  final String? reconciledBy;
  final bool canReconcile;
  List<TransferLine> get sorted =>
      [...detail.items]..sort((a, b) => a.lotId.compareTo(b.lotId));
  String get fingerprint => jsonEncode({
    'id': detail.transfer.id,
    'number': detail.transfer.number,
    'requested_by': requestedBy,
    'chain_id': chainId,
    'requested_at': detail.transfer.requestedAt.toIso8601String(),
    'dispatched_by': dispatchedBy,
    'dispatched_at': detail.times['dispatched_at']!.toIso8601String(),
    'received_by': receivedBy,
    'received_at': detail.times['received_at']!.toIso8601String(),
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
          'received_quantity': item.received.toString(),
        },
    ],
  });
  bool allowed(String branch) =>
      detail.transfer.belongsTo(branch) &&
      detail.transfer.status == 'discrepancy' &&
      canReconcile &&
      detail.items.any((e) => e.received.compareTo(e.dispatched) < 0);
  void validate(List<ReconcileLine> lines) => validateReconciliation(
    jsonDecode(fingerprint) as TransferJson,
    reconcileLines([for (final line in lines) line.toJson()]),
  );
  TransferJson get observation => {
    'transfer_id': detail.transfer.id,
    'status': detail.transfer.status,
    'reconciled_by': reconciledBy,
    'reconciled_at': detail.times['reconciled_at']?.toIso8601String(),
    'reconciliation_reason': detail.reconciliationReason,
    'items': [
      for (final item in sorted)
        ReconcileLine(
          item.lotId,
          item.supplemental.toString(),
          item.returned.toString(),
          item.lost.toString(),
        ).toJson(),
    ],
  };
  String? evidence(ReconcileAttempt attempt, String user) {
    if (fingerprint != attempt.fingerprint ||
        detail.transfer.status != 'reconciled' ||
        reconciledBy == null ||
        detail.times['reconciled_at'] == null) {
      return null;
    }
    try {
      final reason = reconcileReason(detail.reconciliationReason!);
      if (reason != detail.reconciliationReason) return null;
      final actual = reconcileLines(observation['items']);
      validate(actual);
      final matches = actual.every((line) => attempt.lines.any(line.same));
      return reconciledBy == user && reason == attempt.reason && matches
          ? 'verified'
          : 'handled_elsewhere';
    } catch (_) {
      return null;
    }
  }
}

class ReconcileAttempt {
  ReconcileAttempt({
    required this.attemptId,
    required this.id,
    required this.branchId,
    required List<ReconcileLine> lines,
    required this.reason,
    required this.fingerprint,
    required this.createdAt,
    required this.phase,
  }) : lines = List.unmodifiable(lines);
  factory ReconcileAttempt.fromJson(TransferJson json) {
    final id = jsonId(json['transfer_id']), branch = jsonId(json['branch_id']);
    final attempt = json['attempt_id'] as String,
        created = json['created_at'] as String;
    final phase = json['phase'] as String,
        fingerprint = json['fingerprint'] as String;
    final snapshot = jsonDecode(fingerprint) as TransferJson;
    final lines = reconcileLines(json['items']);
    final reason = reconcileReason(json['reason'] as String);
    if (!RegExp(r'^[a-f0-9]{32}$').hasMatch(attempt) ||
        !DateTime.parse(created).isUtc ||
        !{
          'pending',
          'unknown',
          'verified',
          'handled_elsewhere',
          'denied',
        }.contains(phase) ||
        snapshot['id'] != id ||
        !{snapshot['from_branch'], snapshot['to_branch']}.contains(branch) ||
        reason != json['reason']) {
      throw const FormatException('Marker đối soát không hợp lệ.');
    }
    validateReconciliation(snapshot, lines);
    return ReconcileAttempt(
      attemptId: attempt,
      id: id,
      branchId: branch,
      lines: lines,
      reason: reason,
      fingerprint: fingerprint,
      createdAt: created,
      phase: phase,
    );
  }
  final String attemptId, id, branchId, reason, fingerprint, createdAt, phase;
  final List<ReconcileLine> lines;
  ReconcileAttempt withPhase(String phase) => ReconcileAttempt(
    attemptId: attemptId,
    id: id,
    branchId: branchId,
    lines: lines,
    reason: reason,
    fingerprint: fingerprint,
    createdAt: createdAt,
    phase: phase,
  );
  TransferJson toJson() => {
    'attempt_id': attemptId,
    'transfer_id': id,
    'branch_id': branchId,
    'reason': reason,
    'fingerprint': fingerprint,
    'created_at': createdAt,
    'phase': phase,
    'items': [for (final line in lines) line.toJson()],
  };
}
