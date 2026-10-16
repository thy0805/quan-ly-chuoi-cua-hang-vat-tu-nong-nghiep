import 'package:flutter/material.dart';

import '../auth/auth_controller.dart';
import 'dispatch_models.dart';
import 'dispatch_submission.dart';
import 'models.dart';

class TransferDispatchWorkspace extends StatefulWidget {
  const TransferDispatchWorkspace({
    super.key,
    required this.controller,
    this.id,
  });
  final AuthController controller;
  final String? id;
  @override
  State<TransferDispatchWorkspace> createState() =>
      _TransferDispatchWorkspaceState();
}

class _TransferDispatchWorkspaceState extends State<TransferDispatchWorkspace> {
  final _scroll = ScrollController();
  final _values = <String, String>{};
  String? _formIdentity, _validation;
  TransferDispatches get flow => widget.controller.transferDispatches;

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
    if (detail == null || !flow.canDispatch) return;
    List<DispatchLine> lines;
    try {
      lines = [
        for (final item in detail.detail.items)
          DispatchLine(item.lotId, (_values[item.lotId] ?? '').trim()),
      ];
      detail.validate(lines);
    } catch (e) {
      setState(
        () => _validation = e is FormatException
            ? e.message
            : 'Kiểm tra số xuất của từng lô.',
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
              flow.canDispatch &&
              flow.detail?.fingerprint == detail.fingerprint &&
              _formIdentity == identity;
          return AlertDialog(
            scrollable: true,
            title: Text(
              allowed
                  ? 'Xuất hàng và giảm tồn nguồn?'
                  : 'Phiên hoặc quyền đã đổi',
            ),
            content: allowed
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(detail.detail.transfer.number),
                      const SizedBox(height: 12),
                      const Text(
                        'Xác nhận xuất sẽ trừ tồn kho nguồn. Chưa cộng tồn kho đích.',
                      ),
                      const SizedBox(height: 12),
                      for (final line in lines)
                        Text(
                          'Lô ${detail.detail.items.singleWhere((e) => e.lotId == line.lotId).lotNumber}: ${line.quantity.vietnamese}',
                        ),
                      const SizedBox(height: 12),
                      const Text(
                        'Quyền, phiếu và tồn sẽ được tải lại trước khi gửi một lần.',
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
                  key: const Key('confirm-transfer-dispatch'),
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Xác nhận xuất kho'),
                ),
            ],
          );
        },
      ),
    );
    if (!mounted ||
        agreed != true ||
        !flow.canDispatch ||
        flow.detail?.fingerprint != detail.fingerprint ||
        identity != _formIdentity) {
      return;
    }
    await flow.submit(lines);
    if (mounted && _scroll.hasClients) _scroll.jumpTo(0);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Xuất điều chuyển', style: TextStyle(fontSize: 18)),
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
                        key: const Key('transfer-dispatch-status'),
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
                      key: const Key('transfer-dispatch-error'),
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
                        'Lô ID ${line.lotId} · Số đã gửi: ${line.quantity.vietnamese}',
                      ),
                    if (flow.attempt!.branchId != widget.controller.branch?.id)
                      const Text(
                        'Chọn lại chi nhánh nguồn của thao tác đang lưu để kiểm tra kết quả.',
                      ),
                  ],
                  if (flow.detail != null) ..._detail(flow.detail!),
                  if (_validation != null && flow.canDispatch) ...[
                    const SizedBox(height: 12),
                    Text(
                      _validation!,
                      key: const Key('dispatch-validation'),
                      style: const TextStyle(color: Color(0xFF9B321C)),
                    ),
                  ],
                  const SizedBox(height: 20),
                  if (flow.canDispatch)
                    FilledButton.icon(
                      key: const Key('dispatch-transfer'),
                      onPressed: _confirm,
                      icon: const Icon(Icons.outbox_outlined),
                      label: const Text('Kiểm tra xuất kho'),
                    ),
                  if (flow.canComplete)
                    FilledButton(
                      key: const Key('complete-transfer-dispatch'),
                      onPressed: () async {
                        await flow.complete();
                        if (mounted && _scroll.hasClients) _scroll.jumpTo(0);
                      },
                      child: const Text('Lưu dấu vết và hoàn tất'),
                    ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    key: const Key('reload-transfer-dispatch'),
                    onPressed: flow.busy
                        ? null
                        : () => flow.state == DispatchState.storageBlocked
                              ? flow.open(id: widget.id)
                              : flow.reload(),
                    icon: const Icon(Icons.refresh),
                    label: Text(
                      flow.state == DispatchState.storageBlocked
                          ? 'Đọc lại bộ nhớ'
                          : 'Tải lại phiếu',
                    ),
                  ),
                  if (flow.journal.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    Text(
                      'Dấu vết xuất kho đã lưu (${flow.journal.length})',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    for (final entry in flow.journal.reversed) ...[
                      const Divider(),
                      Text('Phiếu ${(entry['attempt'] as Map)['transfer_id']}'),
                      Text(switch ((entry['attempt'] as Map)['phase']) {
                        'verified' =>
                          'Đã đối chiếu người xuất, thời điểm và số lượng.',
                        'handled_elsewhere' =>
                          'Phiếu đã xuất theo kết quả khác.',
                        _ => 'API đã từ chối yêu cầu.',
                      }),
                    ],
                  ],
                  const SizedBox(height: 24),
                  const Text(
                    'Tồn và quyền vừa tải là ảnh chụp tại thời điểm đọc, chưa giữ hàng. Backend kiểm tra lần cuối khi xuất.',
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
    DispatchState.loading => 'Đang đọc dấu vết xuất kho…',
    DispatchState.ready =>
      flow.detail == null
          ? 'Chưa có thao tác xuất đang chờ. Mở phiếu đã duyệt trong mục Điều chuyển kho.'
          : 'Kiểm tra từng lô và số lượng trước khi xuất',
    DispatchState.sending => 'Đang gửi một lần. Vui lòng chờ.',
    DispatchState.unknown =>
      'Chưa xác định kết quả xuất. Chỉ tải lại đúng phiếu, không gửi lại.',
    DispatchState.verified =>
      'Đã đối chiếu xuất kho từ phiếu: người xuất, thời điểm và số lượng.',
    DispatchState.handledElsewhere =>
      'Phiếu đã xuất theo kết quả khác. Không ghi nhận thao tác này thành công.',
    DispatchState.denied =>
      'API từ chối yêu cầu xuất. Kiểm tra phiếu rồi lưu dấu vết.',
    DispatchState.storageBlocked =>
      'Bộ nhớ chưa được xác minh. Đã khóa gửi xuất kho.',
  };

  List<Widget> _detail(DispatchDetail data) {
    final row = data.detail.transfer;
    final identity =
        '${widget.controller.profile!.userId}|${widget.controller.branch!.id}|${data.fingerprint}';
    if (_formIdentity != identity) {
      _formIdentity = identity;
      _values.clear();
      _validation = null;
      for (final item in data.detail.items) {
        _values[item.lotId] = item.requested.toString();
      }
    }
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
      if (data.dispatchedBy != null)
        Text('Người xuất (ID): ${data.dispatchedBy}'),
      if (data.detail.times['dispatched_at'] != null)
        Text('Xuất lúc: ${transferDate(data.detail.times['dispatched_at']!)}'),
      const SizedBox(height: 16),
      if (flow.canDispatch)
        const Card(
          elevation: 0,
          color: Color(0xFFFFF0D9),
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'Xuất kho làm giảm tồn nguồn ngay. Kho đích chưa được cộng tồn ở bước này.',
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
                Text('Yêu cầu: ${item.requested.vietnamese} ${item.unitName}'),
                if (flow.canDispatch) ...[
                  Text(
                    flow.stockFor(item.lotId) == null
                        ? 'Chưa có snapshot tồn khả dụng cho lô này. Backend sẽ kiểm tra khi xuất.'
                        : 'Tồn vừa tải: ${flow.stockFor(item.lotId)!.quantity.vietnamese} ${item.unitName}',
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    key: ValueKey('dispatch-quantity-${item.lotId}-$identity'),
                    initialValue: _values[item.lotId],
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Số lượng xuất',
                      helperText: 'Tối đa 3 số lẻ, dùng dấu chấm.',
                    ),
                    onChanged: (value) {
                      _values[item.lotId] = value;
                    },
                  ),
                ] else
                  Text(
                    'Đã xuất: ${item.dispatched.vietnamese} ${item.unitName}',
                  ),
              ],
            ),
          ),
        ),
      if (!data.allowed(widget.controller.branch!.id) && flow.attempt == null)
        const Text('Chỉ xuất phiếu đã duyệt khi có quyền tại chi nhánh nguồn.'),
    ];
  }
}
