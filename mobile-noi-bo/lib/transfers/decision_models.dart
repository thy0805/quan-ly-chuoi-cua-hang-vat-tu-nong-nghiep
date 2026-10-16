import 'dart:convert';

import '../core/numbers.dart';
import 'models.dart';

enum TransferAction { approve, reject }

class DecisionDetail {
  DecisionDetail.fromJson(TransferJson json)
    : detail = TransferDetail.fromJson(json),
      requestedBy = jsonId((json['data'] as TransferJson)['requested_by']),
      canApprove = (json['data'] as TransferJson)['can_approve'] as bool,
      canReject = (json['data'] as TransferJson)['can_reject'] as bool,
      approvedBy = _id((json['data'] as TransferJson)['approved_by']),
      rejectedBy = _id((json['data'] as TransferJson)['rejected_by']);

  final TransferDetail detail;
  final String requestedBy;
  final String? approvedBy, rejectedBy;
  final bool canApprove, canReject;
  static String? _id(Object? value) => value == null ? null : jsonId(value);

  TransferJson get observation => {
    'transfer_id': detail.transfer.id,
    'status': detail.transfer.status,
    'approved_by': approvedBy,
    'approved_at': detail.times['approved_at']?.toIso8601String(),
    'rejected_by': rejectedBy,
    'rejected_at': detail.times['rejected_at']?.toIso8601String(),
    'rejection_reason': detail.rejectionReason,
  };

  String get fingerprint => jsonEncode({
    'id': detail.transfer.id,
    'number': detail.transfer.number,
    'requested_by': requestedBy,
    'requested_at': detail.transfer.requestedAt.toIso8601String(),
    'from': detail.transfer.fromWarehouseId,
    'to': detail.transfer.toWarehouseId,
    'from_branch': detail.transfer.fromBranchId,
    'to_branch': detail.transfer.toBranchId,
    'items': [
      for (final row in detail.items)
        {
          'id': row.id,
          'lot_id': row.lotId,
          'quantity': row.requested.toString(),
        },
    ],
  });

  bool allowed(TransferAction action, String user, String branch) =>
      detail.transfer.belongsTo(branch) &&
      detail.transfer.status == 'requested' &&
      requestedBy != user &&
      (action == TransferAction.approve ? canApprove : canReject);

  String? evidence(DecisionAttempt attempt, String user) {
    if (fingerprint != attempt.fingerprint) return null;
    final row = detail.transfer;
    if (attempt.action == TransferAction.approve &&
        {
          'approved',
          'dispatched',
          'received',
          'discrepancy',
          'reconciled',
        }.contains(row.status) &&
        approvedBy != null &&
        detail.times['approved_at'] != null) {
      return approvedBy == user ? 'verified' : 'handled_elsewhere';
    }
    if (row.status == 'rejected' &&
        rejectedBy != null &&
        detail.times['rejected_at'] != null) {
      if (attempt.action == TransferAction.reject &&
          rejectedBy == user &&
          detail.rejectionReason == attempt.reason) {
        return 'verified';
      }
      return 'handled_elsewhere';
    }
    if (attempt.action == TransferAction.reject &&
        {
          'approved',
          'dispatched',
          'received',
          'discrepancy',
          'reconciled',
        }.contains(row.status) &&
        approvedBy != null &&
        detail.times['approved_at'] != null) {
      return 'handled_elsewhere';
    }
    return null;
  }
}

class DecisionAttempt {
  DecisionAttempt({
    required this.attemptId,
    required this.id,
    required this.branchId,
    required this.action,
    required this.fingerprint,
    required this.createdAt,
    required this.phase,
    this.reason,
  });

  factory DecisionAttempt.fromJson(TransferJson json) {
    final action = TransferAction.values.byName(json['action'] as String);
    final reason = json['reason'] as String?;
    final id = jsonId(json['transfer_id']);
    final branch = jsonId(json['branch_id']);
    final attempt = json['attempt_id'] as String;
    final created = json['created_at'] as String;
    final phase = json['phase'] as String;
    final fingerprint = json['fingerprint'] as String;
    final original = jsonDecode(fingerprint) as TransferJson;
    if (!RegExp(r'^[a-f0-9]{32}$').hasMatch(attempt) ||
        !DateTime.parse(created).isUtc ||
        !{
          'pending',
          'unknown',
          'verified',
          'handled_elsewhere',
          'denied',
        }.contains(phase) ||
        reason != null && (reason.isEmpty || reason.runes.length > 1000) ||
        action == TransferAction.approve && reason != null ||
        original['id'] != id ||
        (original['from_branch'] != branch &&
            original['to_branch'] != branch)) {
      throw const FormatException('Marker xử lý phiếu không hợp lệ.');
    }
    return DecisionAttempt(
      attemptId: attempt,
      id: id,
      branchId: branch,
      action: action,
      reason: reason,
      fingerprint: fingerprint,
      createdAt: created,
      phase: phase,
    );
  }

  final String attemptId, id, branchId, fingerprint, createdAt, phase;
  final TransferAction action;
  final String? reason;
  DecisionAttempt withPhase(String phase) => DecisionAttempt(
    attemptId: attemptId,
    id: id,
    branchId: branchId,
    action: action,
    reason: reason,
    fingerprint: fingerprint,
    createdAt: createdAt,
    phase: phase,
  );
  TransferJson toJson() => {
    'attempt_id': attemptId,
    'transfer_id': id,
    'branch_id': branchId,
    'action': action.name,
    'reason': reason,
    'fingerprint': fingerprint,
    'created_at': createdAt,
    'phase': phase,
  };
}
