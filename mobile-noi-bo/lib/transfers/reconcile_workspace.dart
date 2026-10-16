import 'package:flutter/material.dart';

import '../auth/auth_controller.dart';
import 'reconcile_models.dart';
import 'reconcile_submission.dart';
import 'models.dart';

class TransferReconcileWorkspace extends StatefulWidget {
  const TransferReconcileWorkspace({
    super.key,
    required this.controller,
    this.id,
  });
  final AuthController controller;
  final String? id;
  @override
  State<TransferReconcileWorkspace> createState() =>
      _TransferReconcileWorkspaceState();
}

class _TransferReconcileWorkspaceState
    extends State<TransferReconcileWorkspace> {
  final _scroll = ScrollController();
  final _values = <String, String>{};
  String? _formIdentity, _validation;
  String _reason = '';
  TransferReconciliations get flow => widget.controller.transferReconciliations;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) flow.open(id: widget.id);
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _confirm() async {
    final detail = flow.detail;
    if (detail == null || !flow.canReconcile) return;
    List<ReconcileLine> lines;
    late final String reason;
    try {
      reason = reconcileReason(_reason);
      lines = [
        for (final item in detail.detail.items)
          ReconcileLine(
            item.lotId,
            (_values['${item.lotId}:0'] ?? '').trim(),
            (_values['${item.lotId}:1'] ?? '').trim(),
            (_values['${item.lotId}:2'] ?? '').trim(),
          ),
      ];
      detail.validate(lines);
    } catch (e) {
      setState(
        () => _validation = e is FormatException
            ? e.message
            : 'Kiểm tra số đối soát của từng lô.',
      );
      return;
    }
    final identity = _formIdentity;
    FocusScope.of(context).unfocus();
    final agreed = await showDialog<bool>(
      context: context,
      builder: (context) => AnimatedBuilder(
        animation: flow,
        builder: (context, _) {
          final allowed =
              flow.canReconcile &&
              flow.detail?.fingerprint == detail.fingerprint &&
              _formIdentity == identity;
          return AlertDialog(
            scrollable: true,
            title: Text(
              allowed ? 'Đối soát chênh lệch?' : 'Phiên hoặc quyền đã đổi',
            ),
            content: allowed
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(detail.detail.transfer.number),
                      const SizedBox(height: 12),
                      const Text(
                        'Nhận bổ sung cộng kho đích. Hoàn nguồn cộng kho nguồn. Hao hụt không cộng vào kho nào. Phiếu đã đối soát không được sửa lại.',
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Lý do: $reason',
                        key: const Key('reconcile-reason-preview'),
                      ),
                      const SizedBox(height: 12),
                      for (final line in lines)
                        Text(
                          'Lô ${detail.detail.items.singleWhere((e) => e.lotId == line.lotId).lotNumber}: bổ sung ${line.supplemental.vietnamese} · hoàn nguồn ${line.returned.vietnamese} · hao hụt ${line.lost.vietnamese}',
                        ),
                      const SizedBox(height: 12),
                      const Text(
                        'Quyền, phiếu và số thiếu sẽ được tải lại trước khi gửi một lần.',
                      ),
                    ],
                  )
                : const Text(
                    'Đóng hộp thoại và kiểm tra lại phạm vi làm việc.',
                  ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(allowed ? 'Quay lại' : 'Đóng'),
              ),
              if (allowed)
                FilledButton(
                  key: const Key('confirm-transfer-reconcile'),
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Xác nhận đối soát'),
                ),
            ],
          );
        },
      ),
    );
    if (!mounted ||
        agreed != true ||
        !flow.canReconcile ||
        flow.detail?.fingerprint != detail.fingerprint ||
        identity != _formIdentity) {
      return;
    }
    await flow.submit(lines, reason);
    if (mounted && _scroll.hasClients) _scroll.jumpTo(0);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Đối soát điều chuyển', style: TextStyle(fontSize: 18)),
    ),
    body: SafeArea(
      child: AnimatedBuilder(
        animation: flow,
        builder: (context, _) => Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 540),
            child: ListView(
              controller: _scroll,
              padding: const EdgeInsets.all(20),
              children: [
                if (!flow.visible)
                  const Text(
                    'Phiên hoặc chi nhánh đã đổi. Quay lại để chọn phạm vi làm việc.',
                  )
                else ...[
                  Card(
                    elevation: 0,
                    color: const Color(0xFFF0F4EE),
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Text(
                        _status,
                        key: const Key('transfer-reconcile-status'),
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          height: 1.5,
                        ),
                      ),
                    ),
                  ),
                  if (flow.busy)
                    const Padding(
                      padding: EdgeInsets.all(20),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                  if (flow.error != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      flow.error!.message,
                      key: const Key('transfer-reconcile-error'),
                      style: const TextStyle(color: Color(0xFF9B321C)),
                    ),
                    for (final errors in flow.error!.fieldErrors.values)
                      for (final message in errors) Text(message),
                  ],
                  if (flow.attempt != null) ...[
                    const SizedBox(height: 16),
                    Text('Mã phiếu đang lưu: ${flow.attempt!.id}'),
                    for (final line in flow.attempt!.lines)
                      Text(
                        'Lô ID ${line.lotId} · Số đã gửi: bổ sung ${line.supplemental.vietnamese} · hoàn nguồn ${line.returned.vietnamese} · hao hụt ${line.lost.vietnamese}',
                      ),
                    if (flow.attempt!.branchId != widget.controller.branch?.id)
                      const Text(
                        'Chọn lại chi nhánh của thao tác đang lưu để kiểm tra kết quả.',
                      ),
                  ],
                  if (flow.detail != null) ..._detail(flow.detail!),
                  if (_validation != null && flow.canReconcile) ...[
                    const SizedBox(height: 12),
                    Text(
                      _validation!,
                      key: const Key('reconcile-validation'),
                      style: const TextStyle(color: Color(0xFF9B321C)),
                    ),
                  ],
                  const SizedBox(height: 20),
                  if (flow.canReconcile)
                    FilledButton.icon(
                      key: const Key('reconcile-transfer'),
                      onPressed: _confirm,
                      icon: const Icon(Icons.move_to_inbox_outlined),
                      label: const Text('Kiểm tra đối soát'),
                    ),
                  if (flow.canComplete)
                    FilledButton(
                      key: const Key('complete-transfer-reconcile'),
                      onPressed: () async {
                        await flow.complete();
                        if (mounted && _scroll.hasClients) _scroll.jumpTo(0);
                      },
                      child: const Text('Lưu dấu vết và hoàn tất'),
                    ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    key: const Key('reload-transfer-reconcile'),
                    onPressed: flow.busy
                        ? null
                        : () => flow.state == ReconcileState.storageBlocked
                              ? flow.open(id: widget.id)
                              : flow.reload(),
                    icon: const Icon(Icons.refresh),
                    label: Text(
                      flow.state == ReconcileState.storageBlocked
                          ? 'Đọc lại bộ nhớ'
                          : 'Tải lại phiếu',
                    ),
                  ),
                  if (flow.journal.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    Text(
                      'Dấu vết đối soát đã lưu (${flow.journal.length})',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    for (final entry in flow.journal.reversed) ...[
                      const Divider(),
                      Text('Phiếu ${(entry['attempt'] as Map)['transfer_id']}'),
                      Text(switch ((entry['attempt'] as Map)['phase']) {
                        'verified' =>
                          'Đã đối chiếu người đối soát, thời điểm, lý do và ba số lượng.',
                        'handled_elsewhere' =>
                          'Phiếu đã đối soát theo kết quả khác.',
                        _ => 'API đã từ chối yêu cầu.',
                      }),
                    ],
                  ],
                  const SizedBox(height: 24),
                  const Text(
                    'Phiếu và quyền vừa tải là ảnh chụp tại thời điểm đọc. Backend kiểm tra lần cuối khi đối soát; ứng dụng không tự cộng tồn.',
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

  String get _status => switch (flow.state) {
    ReconcileState.loading => 'Đang đọc dấu vết đối soát…',
    ReconcileState.ready =>
      flow.detail == null
          ? 'Chưa có thao tác đối soát đang chờ. Mở phiếu chênh lệch trong mục Điều chuyển kho.'
          : 'Phân bổ phần thiếu và ghi lý do trước đối soát',
    ReconcileState.sending => 'Đang gửi một lần. Vui lòng chờ.',
    ReconcileState.unknown =>
      'Chưa xác định kết quả đối soát. Chỉ tải lại đúng phiếu, không gửi lại.',
    ReconcileState.verified =>
      'Đã đối chiếu người đối soát, thời điểm, lý do và ba số lượng từ phiếu.',
    ReconcileState.handledElsewhere =>
      'Phiếu đã đối soát theo kết quả khác. Không ghi nhận thao tác này thành công.',
    ReconcileState.denied =>
      'API từ chối yêu cầu đối soát. Kiểm tra phiếu rồi lưu dấu vết.',
    ReconcileState.storageBlocked =>
      'Bộ nhớ chưa được xác minh. Đã khóa gửi đối soát.',
  };

  List<Widget> _detail(ReconcileDetail data) {
    final row = data.detail.transfer;
    final identity =
        '${widget.controller.profile!.userId}|${widget.controller.branch!.id}|${data.fingerprint}';
    if (_formIdentity != identity) {
      _formIdentity = identity;
      _values.clear();
      _reason = '';
      _validation = null;
      for (final item in data.detail.items) {
        for (var i = 0; i < 3; i++) {
          _values['${item.lotId}:$i'] = '0';
        }
      }
    }
    const labels = ['Nhận bổ sung', 'Hoàn nguồn', 'Hao hụt'];
    const directions = ['Cộng kho đích', 'Cộng kho nguồn', 'Không cộng kho'];
    return [
      const SizedBox(height: 20),
      Text(
        row.number,
        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
      ),
      const SizedBox(height: 8),
      Text(row.statusLabel),
      const Divider(height: 28),
      Text('Kho nguồn: ${row.fromBranchName} · ${row.fromWarehouseName}'),
      const SizedBox(height: 10),
      Text('Kho đích: ${row.toBranchName} · ${row.toWarehouseName}'),
      if (data.reconciledBy != null)
        Text('Người đối soát (ID): ${data.reconciledBy}'),
      if (data.detail.times['reconciled_at'] != null)
        Text(
          'Đối soát lúc: ${transferDate(data.detail.times['reconciled_at']!)}',
        ),
      if (data.detail.reconciliationReason != null)
        Text('Lý do: ${data.detail.reconciliationReason}'),
      const SizedBox(height: 16),
      if (flow.canReconcile)
        const Card(
          elevation: 0,
          color: Color(0xFFFFF0D9),
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'Phân bổ đúng phần thiếu của từng lô. Nhận bổ sung cộng kho đích; hoàn nguồn cộng kho nguồn; hao hụt không cộng kho. Phiếu đã đối soát không được sửa lại.',
            ),
          ),
        ),
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
                Text('Đã xuất: ${item.dispatched.vietnamese} ${item.unitName}'),
                Text('Thực nhận: ${item.received.vietnamese} ${item.unitName}'),
                Text(
                  'Phần thiếu: ${(item.dispatched - item.received).vietnamese} ${item.unitName}',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                if (flow.canReconcile)
                  for (var i = 0; i < 3; i++) ...[
                    const SizedBox(height: 14),
                    TextFormField(
                      key: ValueKey(
                        'reconcile-quantity-${item.lotId}-$i-$identity',
                      ),
                      initialValue: _values['${item.lotId}:$i'],
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(
                        labelText: labels[i],
                        helperText:
                            '${directions[i]}. Không âm, tối đa 3 số lẻ.',
                        helperMaxLines: 3,
                        labelStyle: const TextStyle(fontSize: 14),
                      ),
                      onChanged: (value) {
                        _values['${item.lotId}:$i'] = value;
                      },
                    ),
                  ]
                else ...[
                  Text(
                    'Nhận bổ sung: ${item.supplemental.vietnamese} ${item.unitName}',
                  ),
                  Text(
                    'Hoàn nguồn: ${item.returned.vietnamese} ${item.unitName}',
                  ),
                  Text('Hao hụt: ${item.lost.vietnamese} ${item.unitName}'),
                ],
              ],
            ),
          ),
        ),
      if (flow.canReconcile) ...[
        const SizedBox(height: 16),
        TextFormField(
          key: ValueKey('reconcile-reason-$identity'),
          initialValue: _reason,
          maxLines: 3,
          decoration: const InputDecoration(
            labelText: 'Lý do đối soát',
            helperText: 'Từ 3 đến 1000 ký tự sau khi bỏ khoảng trắng đầu cuối.',
            helperMaxLines: 3,
          ),
          onChanged: (value) {
            _reason = value;
          },
        ),
      ],
      if (!data.allowed(widget.controller.branch!.id) && flow.attempt == null)
        const Text(
          'Chỉ đối soát phiếu chênh lệch khi được cấp quyền phù hợp trên cả hai đầu kho.',
        ),
    ];
  }
}
