import 'package:flutter/material.dart';

import '../auth/auth_controller.dart';
import 'receive_models.dart';
import 'receive_submission.dart';
import 'models.dart';

class TransferReceiveWorkspace extends StatefulWidget {
  const TransferReceiveWorkspace({
    super.key,
    required this.controller,
    this.id,
  });
  final AuthController controller;
  final String? id;
  @override
  State<TransferReceiveWorkspace> createState() =>
      _TransferReceiveWorkspaceState();
}

class _TransferReceiveWorkspaceState extends State<TransferReceiveWorkspace> {
  final _scroll = ScrollController();
  final _values = <String, String>{};
  String? _formIdentity, _validation;
  TransferReceives get flow => widget.controller.transferReceives;

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
    if (detail == null || !flow.canReceive) return;
    List<ReceiveLine> lines;
    try {
      lines = [
        for (final item in detail.detail.items)
          ReceiveLine(item.lotId, (_values[item.lotId] ?? '').trim()),
      ];
      detail.validate(lines);
    } catch (e) {
      setState(
        () => _validation = e is FormatException
            ? e.message
            : 'Kiểm tra số nhận của từng lô.',
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
              flow.canReceive &&
              flow.detail?.fingerprint == detail.fingerprint &&
              _formIdentity == identity;
          return AlertDialog(
            scrollable: true,
            title: Text(
              allowed
                  ? 'Nhận hàng và cộng tồn đích?'
                  : 'Phiên hoặc quyền đã đổi',
            ),
            content: allowed
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(detail.detail.transfer.number),
                      const SizedBox(height: 12),
                      const Text(
                        'Xác nhận sẽ cộng đúng số thực nhận vào kho đích. Nhận thiếu tạo chênh lệch, không tự cộng bù.',
                      ),
                      const SizedBox(height: 12),
                      Text(
                        detail.expectedStatus(lines) == 'received'
                            ? 'Dự kiến nhận đủ tất cả các lô.'
                            : 'Dự kiến có chênh lệch do nhận thiếu. Phần thiếu chờ đối soát riêng.',
                        key: const Key('receive-outcome-preview'),
                      ),
                      const SizedBox(height: 12),
                      for (final line in lines)
                        Text(
                          'Lô ${detail.detail.items.singleWhere((e) => e.lotId == line.lotId).lotNumber}: ${line.quantity.vietnamese}',
                        ),
                      const SizedBox(height: 12),
                      const Text(
                        'Quyền, phiếu và số đã xuất sẽ được tải lại trước khi gửi một lần.',
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
                  key: const Key('confirm-transfer-receive'),
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Xác nhận nhận hàng'),
                ),
            ],
          );
        },
      ),
    );
    if (!mounted ||
        agreed != true ||
        !flow.canReceive ||
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
      title: const Text('Nhận điều chuyển', style: TextStyle(fontSize: 18)),
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
                        key: const Key('transfer-receive-status'),
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
                      key: const Key('transfer-receive-error'),
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
                        'Chọn lại chi nhánh đích của thao tác đang lưu để kiểm tra kết quả.',
                      ),
                  ],
                  if (flow.detail != null) ..._detail(flow.detail!),
                  if (_validation != null && flow.canReceive) ...[
                    const SizedBox(height: 12),
                    Text(
                      _validation!,
                      key: const Key('receive-validation'),
                      style: const TextStyle(color: Color(0xFF9B321C)),
                    ),
                  ],
                  const SizedBox(height: 20),
                  if (flow.canReceive)
                    FilledButton.icon(
                      key: const Key('receive-transfer'),
                      onPressed: _confirm,
                      icon: const Icon(Icons.move_to_inbox_outlined),
                      label: const Text('Kiểm tra nhận hàng'),
                    ),
                  if (flow.canComplete)
                    FilledButton(
                      key: const Key('complete-transfer-receive'),
                      onPressed: () async {
                        await flow.complete();
                        if (mounted && _scroll.hasClients) _scroll.jumpTo(0);
                      },
                      child: const Text('Lưu dấu vết và hoàn tất'),
                    ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    key: const Key('reload-transfer-receive'),
                    onPressed: flow.busy
                        ? null
                        : () => flow.state == ReceiveState.storageBlocked
                              ? flow.open(id: widget.id)
                              : flow.reload(),
                    icon: const Icon(Icons.refresh),
                    label: Text(
                      flow.state == ReceiveState.storageBlocked
                          ? 'Đọc lại bộ nhớ'
                          : 'Tải lại phiếu',
                    ),
                  ),
                  if (flow.journal.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    Text(
                      'Dấu vết nhận hàng đã lưu (${flow.journal.length})',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    for (final entry in flow.journal.reversed) ...[
                      const Divider(),
                      Text('Phiếu ${(entry['attempt'] as Map)['transfer_id']}'),
                      Text(switch ((entry['attempt'] as Map)['phase']) {
                        'verified' =>
                          'Đã đối chiếu người nhận, thời điểm và số lượng.',
                        'handled_elsewhere' =>
                          'Phiếu đã nhận theo kết quả khác.',
                        _ => 'API đã từ chối yêu cầu.',
                      }),
                    ],
                  ],
                  const SizedBox(height: 24),
                  const Text(
                    'Số đã xuất và quyền vừa tải là ảnh chụp tại thời điểm đọc. Backend kiểm tra lần cuối khi nhận; phần thiếu chờ đối soát riêng.',
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
    ReceiveState.loading => 'Đang đọc dấu vết nhận hàng…',
    ReceiveState.ready =>
      flow.detail == null
          ? 'Chưa có thao tác nhận đang chờ. Mở phiếu đã xuất trong mục Điều chuyển kho.'
          : 'Kiểm tra từng lô và số lượng trước khi nhận',
    ReceiveState.sending => 'Đang gửi một lần. Vui lòng chờ.',
    ReceiveState.unknown =>
      'Chưa xác định kết quả nhận. Chỉ tải lại đúng phiếu, không gửi lại.',
    ReceiveState.verified =>
      'Đã đối chiếu nhận hàng từ phiếu: người nhận, thời điểm và số lượng.',
    ReceiveState.handledElsewhere =>
      'Phiếu đã nhận theo kết quả khác. Không ghi nhận thao tác này thành công.',
    ReceiveState.denied =>
      'API từ chối yêu cầu nhận. Kiểm tra phiếu rồi lưu dấu vết.',
    ReceiveState.storageBlocked =>
      'Bộ nhớ chưa được xác minh. Đã khóa gửi nhận hàng.',
  };

  List<Widget> _detail(ReceiveDetail data) {
    final row = data.detail.transfer;
    final identity =
        '${widget.controller.profile!.userId}|${widget.controller.branch!.id}|${data.fingerprint}';
    if (_formIdentity != identity) {
      _formIdentity = identity;
      _values.clear();
      _validation = null;
      for (final item in data.detail.items) {
        _values[item.lotId] = item.dispatched.toString();
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
      if (data.receivedBy != null) Text('Người nhận (ID): ${data.receivedBy}'),
      if (data.detail.times['received_at'] != null)
        Text('Nhận lúc: ${transferDate(data.detail.times['received_at']!)}'),
      const SizedBox(height: 16),
      if (flow.canReceive)
        const Card(
          elevation: 0,
          color: Color(0xFFFFF0D9),
          child: Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'Nhận hàng cộng đúng số thực nhận vào kho đích. Có thể nhận 0; phần thiếu giữ chênh lệch để đối soát riêng.',
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
                if (flow.canReceive) ...[
                  const SizedBox(height: 14),
                  TextFormField(
                    key: ValueKey('receive-quantity-${item.lotId}-$identity'),
                    initialValue: _values[item.lotId],
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Số lượng thực nhận',
                      helperText: 'Từ 0 đến số đã xuất, tối đa 3 số lẻ.',
                    ),
                    onChanged: (value) {
                      _values[item.lotId] = value;
                    },
                  ),
                ] else
                  Text(
                    'Thực nhận: ${item.received.vietnamese} ${item.unitName}',
                  ),
              ],
            ),
          ),
        ),
      if (!data.allowed(widget.controller.branch!.id) && flow.attempt == null)
        const Text('Chỉ nhận phiếu đã xuất khi có quyền tại chi nhánh đích.'),
    ];
  }
}
