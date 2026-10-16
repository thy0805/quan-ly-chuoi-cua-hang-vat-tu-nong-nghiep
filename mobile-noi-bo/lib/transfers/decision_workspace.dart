import 'package:flutter/material.dart';

import '../auth/auth_controller.dart';
import 'decision_models.dart';
import 'decision_submission.dart';
import 'models.dart';

class TransferDecisionWorkspace extends StatefulWidget {
  const TransferDecisionWorkspace({
    super.key,
    required this.controller,
    this.id,
  });
  final AuthController controller;
  final String? id;
  @override
  State<TransferDecisionWorkspace> createState() =>
      _TransferDecisionWorkspaceState();
}

class _TransferDecisionWorkspaceState extends State<TransferDecisionWorkspace> {
  final _reason = TextEditingController();
  final _scroll = ScrollController();
  String? _reasonError;
  TransferDecisions get decisions => widget.controller.transferDecisions;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) decisions.open(id: widget.id);
    });
  }

  @override
  void dispose() {
    _reason.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _confirm(TransferAction action) async {
    final row = decisions.detail?.detail.transfer;
    if (row == null || !decisions.canDecide(action)) return;
    final reason = _reason.text.trim();
    if (reason.runes.length > 1000) {
      setState(() => _reasonError = 'Lý do tối đa 1.000 ký tự Unicode.');
      return;
    }
    FocusScope.of(context).unfocus();
    final agreed = await showDialog<bool>(
      context: context,
      builder: (context) => AnimatedBuilder(
        animation: decisions,
        builder: (context, _) {
          if (!decisions.canDecide(action)) {
            return AlertDialog(
              scrollable: true,
              title: const Text('Phiên hoặc quyền đã đổi'),
              content: const Text(
                'Đóng hộp thoại và kiểm tra lại phạm vi làm việc.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Đóng'),
                ),
              ],
            );
          }
          return AlertDialog(
            scrollable: true,
            title: Text(
              action == TransferAction.approve
                  ? 'Duyệt yêu cầu này?'
                  : 'Từ chối yêu cầu này?',
            ),
            content: SingleChildScrollView(
              child: Text(
                '${row.number}\n\n'
                '${action == TransferAction.approve
                    ? 'Cho phép thực hiện điều chuyển. Chưa xuất hàng và chưa thay đổi tồn kho.'
                    : reason.isEmpty
                    ? 'Không ghi lý do từ chối.'
                    : 'Lý do: $reason'}\n\nQuyền và dữ liệu sẽ được kiểm tra lại trước khi gửi.',
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Quay lại'),
              ),
              FilledButton(
                key: const Key('confirm-transfer-decision'),
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Xác nhận'),
              ),
            ],
          );
        },
      ),
    );
    if (!mounted || agreed != true || !decisions.canDecide(action)) return;
    await decisions.submit(
      action,
      reason: action == TransferAction.reject ? reason : null,
    );
    if (mounted && _scroll.hasClients) _scroll.jumpTo(0);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text(
        'Xử lý yêu cầu điều chuyển',
        style: TextStyle(fontSize: 18),
      ),
    ),
    body: SafeArea(
      child: AnimatedBuilder(
        animation: decisions,
        builder: (context, _) => Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 540),
            child: ListView(
              controller: _scroll,
              padding: const EdgeInsets.all(20),
              children: [
                if (!decisions.visible)
                  const Text(
                    'Phiên hoặc chi nhánh đã đổi. Quay lại để chọn phạm vi làm việc.',
                  )
                else ...[
                  _status(),
                  if (decisions.busy)
                    const Padding(
                      padding: EdgeInsets.all(20),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                  if (decisions.error != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      decisions.error!.message,
                      key: const Key('transfer-decision-error'),
                      style: const TextStyle(color: Color(0xFF9B321C)),
                    ),
                    for (final errors in decisions.error!.fieldErrors.values)
                      for (final message in errors) Text(message),
                  ],
                  if (decisions.attempt != null) ...[
                    const SizedBox(height: 16),
                    Text('Mã phiếu: ${decisions.attempt!.id}'),
                    Text(
                      'Thao tác: ${decisions.attempt!.action == TransferAction.approve ? 'Duyệt' : 'Từ chối'}',
                    ),
                    if (decisions.attempt!.reason != null)
                      Text('Lý do đã gửi: ${decisions.attempt!.reason}'),
                    if (decisions.detail == null &&
                        decisions.attempt!.branchId !=
                            widget.controller.branch?.id)
                      const Text(
                        'Chọn lại chi nhánh của thao tác đang lưu để kiểm tra kết quả.',
                      ),
                  ],
                  if (decisions.detail != null) ..._detail(decisions.detail!),
                  const SizedBox(height: 20),
                  if (decisions.canDecide(TransferAction.approve))
                    FilledButton.icon(
                      key: const Key('approve-transfer'),
                      onPressed: () => _confirm(TransferAction.approve),
                      icon: const Icon(Icons.check),
                      label: const Text('Duyệt yêu cầu'),
                    ),
                  if (decisions.canDecide(TransferAction.reject)) ...[
                    const SizedBox(height: 18),
                    TextField(
                      key: const Key('transfer-rejection-reason'),
                      controller: _reason,
                      maxLines: 3,
                      maxLength: 1000,
                      onChanged: (_) {
                        if (_reasonError != null) {
                          setState(() => _reasonError = null);
                        }
                      },
                      decoration: InputDecoration(
                        errorText: _reasonError,
                        labelText: 'Lý do từ chối (không bắt buộc)',
                        alignLabelWithHint: true,
                      ),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      key: const Key('reject-transfer'),
                      onPressed: () => _confirm(TransferAction.reject),
                      icon: const Icon(Icons.close),
                      label: const Text('Từ chối yêu cầu'),
                    ),
                  ],
                  if (decisions.canComplete)
                    FilledButton(
                      key: const Key('complete-transfer-decision'),
                      onPressed: () async {
                        await decisions.complete();
                        if (mounted && _scroll.hasClients) _scroll.jumpTo(0);
                      },
                      child: const Text('Lưu dấu vết và hoàn tất'),
                    ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    key: const Key('reload-transfer-decision'),
                    onPressed: decisions.busy
                        ? null
                        : () => decisions.state == DecisionState.storageBlocked
                              ? decisions.open(id: widget.id)
                              : decisions.reload(),
                    icon: const Icon(Icons.refresh),
                    label: Text(
                      decisions.state == DecisionState.storageBlocked
                          ? 'Đọc lại bộ nhớ'
                          : 'Tải lại phiếu',
                    ),
                  ),
                  if (decisions.journal.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    Text(
                      'Dấu vết đã lưu (${decisions.journal.length})',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    for (final entry in decisions.journal.reversed) ...[
                      const Divider(),
                      Text(
                        'Phiếu ${(entry['attempt'] as Map)['transfer_id']} · ${(entry['attempt'] as Map)['action'] == 'approve' ? 'Duyệt' : 'Từ chối'}',
                      ),
                      Text(switch ((entry['attempt'] as Map)['phase']) {
                        'verified' =>
                          'Đã xác minh trạng thái và người thực hiện',
                        'handled_elsewhere' =>
                          'Phiếu đã được xử lý theo kết quả khác',
                        _ => 'Yêu cầu bị từ chối trước khi áp dụng',
                      }),
                    ],
                  ],
                  const SizedBox(height: 24),
                  const Text(
                    'Duyệt hoặc từ chối không xuất hàng, không nhận hàng và không thay đổi tồn kho.',
                    style: TextStyle(color: Colors.black54, height: 1.5),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    ),
  );

  Widget _status() => Card(
    elevation: 0,
    color: const Color(0xFFF0F4EE),
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Text(
        switch (decisions.state) {
          DecisionState.loading => 'Đang đọc dấu vết…',
          DecisionState.ready =>
            decisions.detail == null
                ? 'Chưa có thao tác đang chờ. Mở một phiếu trong mục Điều chuyển kho để kiểm tra quyền xử lý.'
                : 'Kiểm tra phiếu trước khi xử lý',
          DecisionState.sending => 'Đang gửi một lần. Vui lòng chờ.',
          DecisionState.unknown =>
            'Chưa xác định kết quả. Chỉ tải lại đúng phiếu; không gửi lại thao tác.',
          DecisionState.verified =>
            'Đã xác minh trạng thái và người thực hiện từ phiếu.',
          DecisionState.handledElsewhere =>
            'Phiếu đã được xử lý theo kết quả khác. Thao tác này không được ghi nhận là thành công.',
          DecisionState.denied =>
            'API từ chối yêu cầu trước khi áp dụng. Kiểm tra lại phiếu rồi lưu dấu vết.',
          DecisionState.storageBlocked =>
            'Bộ nhớ chưa được xác minh. Đã khóa gửi.',
        },
        key: const Key('transfer-decision-status'),
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          height: 1.5,
        ),
      ),
    ),
  );

  List<Widget> _detail(DecisionDetail data) {
    final row = data.detail.transfer;
    return [
      const SizedBox(height: 20),
      Text(
        row.number,
        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
      ),
      const SizedBox(height: 10),
      Text(row.statusLabel),
      const Divider(height: 28),
      Text('Kho nguồn: ${row.fromBranchName} · ${row.fromWarehouseName}'),
      const SizedBox(height: 10),
      Text('Kho đích: ${row.toBranchName} · ${row.toWarehouseName}'),
      const SizedBox(height: 10),
      Text('Người lập: ${row.requesterName}'),
      if (data.detail.times['approved_at'] != null)
        Text('Duyệt lúc: ${transferDate(data.detail.times['approved_at']!)}'),
      if (data.detail.times['rejected_at'] != null)
        Text('Từ chối lúc: ${transferDate(data.detail.times['rejected_at']!)}'),
      if (data.detail.rejectionReason != null)
        Text('Lý do: ${data.detail.rejectionReason}'),
      const SizedBox(height: 16),
      for (final item in data.detail.items)
        Card(
          elevation: 0,
          color: Colors.white,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.productName,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                Text('${item.productCode} · Lô ${item.lotNumber}'),
                Text('Yêu cầu: ${item.requested.vietnamese} ${item.unitName}'),
              ],
            ),
          ),
        ),
      if (row.status == 'requested' &&
          data.requestedBy == widget.controller.profile?.userId)
        const Text('Người lập không được tự duyệt hoặc từ chối phiếu.'),
      if (row.status == 'requested' && !data.canApprove && !data.canReject)
        const Text(
          'Tài khoản hiện không có quyền xử lý phiếu trong phạm vi này.',
        ),
    ];
  }
}
