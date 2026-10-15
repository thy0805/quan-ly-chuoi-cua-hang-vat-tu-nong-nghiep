import 'dart:async';
import 'package:flutter/material.dart';
import '../auth/auth_controller.dart';
import 'confirmation.dart';
import 'models.dart';

class ConfirmWorkspace extends StatefulWidget {
  const ConfirmWorkspace({super.key, required this.controller});
  final AuthController controller;
  @override
  State<ConfirmWorkspace> createState() => _ConfirmWorkspaceState();
}

class _ConfirmWorkspaceState extends State<ConfirmWorkspace> {
  final _amount = TextEditingController();
  final _note = TextEditingController();
  late final String _owner, _origin;
  late final String? _orderId;
  late final Listenable _changes;
  String? _method = 'cash';
  String? _formError;
  bool _transferChecked = false;
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _owner = widget.controller.profile!.userId;
    _origin = widget.controller.api.storageNamespace;
    _orderId = widget.controller.drafts.attempt?.orderId;
    _changes = Listenable.merge([widget.controller, widget.controller.drafts]);
    unawaited(widget.controller.drafts.reloadDetail());
  }

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _confirm() async {
    if (widget.controller.drafts.attempt?.orderId != _orderId ||
        !widget.controller.drafts.canConfirm ||
        widget.controller.profile?.userId != _owner) {
      return;
    }
    try {
      final payment = InitialPayment(
        amount: _amount.text.trim(),
        method: _method,
        note: _note.text,
      );
      payment.validate(widget.controller.drafts.detail!);
      if (payment.amount.atoms > BigInt.zero &&
          payment.method == 'bank_transfer' &&
          !_transferChecked) {
        throw const FormatException(
          'Xác nhận đã kiểm tra tiền chuyển khoản thực tế.',
        );
      }
      setState(() => _formError = null);
      await widget.controller.drafts.confirm(payment);
    } on FormatException catch (error) {
      if (mounted) setState(() => _formError = error.message);
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _changes,
    builder: (context, _) {
      final auth = widget.controller;
      final coordinator = auth.drafts;
      final allowed =
          auth.stage == AuthStage.ready &&
          !auth.busy &&
          auth.profile?.userId == _owner &&
          auth.api.storageNamespace == _origin &&
          (coordinator.attempt == null ||
              coordinator.attempt?.orderId == _orderId);
      final detail = allowed ? coordinator.detail : null;
      String? validation;
      if (detail != null) {
        try {
          verifiedSaleTotal(detail);
        } on FormatException catch (error) {
          validation = error.message;
        }
        validation ??= coordinator.invoiceIssue;
        if (!_initialized && detail.order.isDraft && validation == null) {
          _amount.text = detail.draftTotal!.toString();
          _initialized = true;
        }
      }
      final invoice =
          detail != null && !detail.order.isDraft && validation == null;
      final enabled = allowed && coordinator.canConfirm;
      return Scaffold(
        appBar: AppBar(
          title: Text(invoice ? 'Hóa đơn nội bộ' : 'Xác nhận bán hàng'),
        ),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 540),
              child: ListView(
                key: const ValueKey('confirm-scroll'),
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                children: [
                  if (!allowed)
                    const Text(
                      'Phiên hoặc quyền đã thay đổi. Dấu vết được giữ cho đúng tài khoản.',
                    )
                  else ...[
                    if (coordinator.busy) ...[
                      const LinearProgressIndicator(),
                      const SizedBox(height: 16),
                      const Text('Đang xác minh. Không gửi lại yêu cầu.'),
                    ],
                    if (coordinator.state.name == 'storageBlocked') ...[
                      const SaleCard(
                        children: [
                          Text(
                            'Tạm khóa thao tác',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            'Không xác minh được bộ nhớ. Giữ dấu vết, không xóa dữ liệu ứng dụng để bỏ qua.',
                          ),
                        ],
                      ),
                      OutlinedButton(
                        onPressed: coordinator.busy
                            ? null
                            : coordinator.restore,
                        child: const Text('Đọc lại bộ nhớ'),
                      ),
                    ],
                    if (coordinator.attempt != null) ...[
                      Text(
                        auth.branch!.name,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 12),
                      if (auth.branch?.id !=
                          coordinator.attempt!.payload.branchId)
                        Text(
                          'Chọn lại chi nhánh ${coordinator.attempt!.payload.branchId} để đối chiếu đơn.',
                        ),
                      OutlinedButton.icon(
                        key: const ValueKey('reload-confirm'),
                        onPressed:
                            coordinator.busy ||
                                auth.branch?.id !=
                                    coordinator.attempt!.payload.branchId
                            ? null
                            : coordinator.reloadDetail,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Tải lại đúng đơn'),
                      ),
                    ],
                    if (coordinator.confirmUncertain && !invoice)
                      const SaleCard(
                        children: [
                          Text(
                            'Chưa xác minh kết quả xác nhận',
                            style: TextStyle(
                              fontSize: 21,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            'Máy chủ có thể đã bán hàng và ghi tiền thu. Chỉ tải lại đúng đơn; không xác nhận hoặc thu lần hai.',
                          ),
                          Text(
                            'Đơn vẫn là nháp trong một lần tải không chứng minh yêu cầu trước đã kết thúc.',
                          ),
                        ],
                      ),
                    if (validation != null)
                      SaleCard(
                        children: [
                          Text(
                            validation,
                            style: const TextStyle(color: Color(0xFF9B3B22)),
                          ),
                        ],
                      ),
                    if (detail != null) ...[
                      SaleCard(
                        children: [
                          Text(
                            detail.order.number,
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            detail.order.isDraft
                                ? 'Nháp · chưa trừ tồn, chưa thu tiền'
                                : 'Đã xác nhận trên hệ thống',
                          ),
                          Text(detail.order.customerName ?? 'Khách lẻ'),
                          for (final item in detail.items) ...[
                            const Divider(),
                            Text(
                              '${item.name} · ${item.lotNo}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              '${item.quantity.vietnamese} × ${item.price.vnd}',
                            ),
                            Text('Chiết khấu: ${item.discount.vnd}'),
                            Text(
                              item.tax == null
                                  ? 'Thiếu snapshot thuế'
                                  : 'Thuế: ${item.tax!.vnd}',
                            ),
                          ],
                          const Divider(),
                          Text(
                            validation == null
                                ? 'Tổng theo máy chủ: ${detail.displayedTotal!.vnd}'
                                : 'Chưa xác minh tổng tiền',
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                      if (invoice) _invoice(detail),
                      if (detail.order.isDraft &&
                          validation == null &&
                          !coordinator.confirmUncertain) ...[
                        if (detail.createdBy != _owner)
                          const Text(
                            'Chỉ người lập đơn còn quyền mới được xác nhận.',
                          ),
                        SaleCard(
                          children: [
                            const Text(
                              'Thu tiền ban đầu',
                              style: TextStyle(
                                fontSize: 21,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            if (detail.order.customerId == null)
                              const Text('Khách lẻ cần thanh toán đủ.')
                            else
                              const Text(
                                'Khách đã lưu có thể trả đủ, trả một phần hoặc trả sau.',
                              ),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                OutlinedButton(
                                  onPressed: enabled
                                      ? () => setState(
                                          () => _amount.text = detail
                                              .draftTotal!
                                              .toString(),
                                        )
                                      : null,
                                  child: const Text('Thu đủ'),
                                ),
                                if (detail.order.customerId != null)
                                  OutlinedButton(
                                    onPressed: enabled
                                        ? () => setState(
                                            () => _amount.text = '0.00',
                                          )
                                        : null,
                                    child: const Text('Trả sau'),
                                  ),
                              ],
                            ),
                            TextField(
                              key: const ValueKey('initial-amount'),
                              controller: _amount,
                              enabled: enabled,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              decoration: const InputDecoration(
                                labelText: 'Số tiền đã thu (VND)',
                                helperText:
                                    'Nhập số, dấu chấm cho phần thập phân.',
                              ),
                            ),
                            DropdownButtonFormField<String>(
                              initialValue: _method,
                              isExpanded: true,
                              decoration: const InputDecoration(
                                labelText: 'Phương thức',
                              ),
                              items: const [
                                DropdownMenuItem(
                                  value: 'cash',
                                  child: Text('Tiền mặt'),
                                ),
                                DropdownMenuItem(
                                  value: 'bank_transfer',
                                  child: Text('Chuyển khoản thủ công'),
                                ),
                              ],
                              onChanged: enabled
                                  ? (value) => setState(() {
                                      _method = value;
                                      _transferChecked = false;
                                    })
                                  : null,
                            ),
                            if (_method == 'bank_transfer')
                              CheckboxListTile(
                                contentPadding: EdgeInsets.zero,
                                value: _transferChecked,
                                title: const Text(
                                  'Đã kiểm tra tiền chuyển khoản thực tế',
                                ),
                                onChanged: enabled
                                    ? (value) => setState(
                                        () => _transferChecked = value ?? false,
                                      )
                                    : null,
                              ),
                            TextField(
                              key: const ValueKey('payment-note'),
                              controller: _note,
                              enabled: enabled,
                              maxLength: 200,
                              decoration: const InputDecoration(
                                labelText: 'Mã tham chiếu / ghi chú (tùy chọn)',
                              ),
                            ),
                            const Text(
                              'Xác nhận sẽ trừ tồn và tạo hóa đơn. Chuyển khoản được ghi nhận thủ công; không có xác nhận ngân hàng tự động.',
                            ),
                            FilledButton.icon(
                              key: const ValueKey('confirm-sale'),
                              onPressed: enabled ? _confirm : null,
                              icon: const Icon(Icons.check_circle_outline),
                              label: const Text('Xác nhận bán hàng'),
                            ),
                          ],
                        ),
                      ],
                    ],
                    if (detail == null &&
                        coordinator.attempt != null &&
                        !coordinator.busy)
                      const Text(
                        'Chưa tải được chi tiết đã xác minh. Giữ ID, không gửi lại.',
                      ),
                    if (coordinator.attempt == null && coordinator.canCreate)
                      SaleCard(
                        children: [
                          const Text(
                            'Đã lưu nhật ký hoàn tất',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const Text(
                            'Có thể quay về chuẩn bị giỏ cho đơn tiếp theo.',
                          ),
                          FilledButton(
                            onPressed: () => Navigator.of(context).pop(),
                            child: const Text('Về giỏ hàng / trang chính'),
                          ),
                        ],
                      ),
                    if (_formError != null)
                      Text(
                        _formError!,
                        style: const TextStyle(color: Color(0xFF9B3B22)),
                      ),
                    if (coordinator.error != null) ...[
                      Text(
                        coordinator.error!.message,
                        style: const TextStyle(color: Color(0xFF9B3B22)),
                      ),
                      for (final entry
                          in coordinator.error!.fieldErrors.entries)
                        Text(
                          '${_label(entry.key)}: ${entry.value.join(' ')}',
                          style: const TextStyle(color: Color(0xFF9B3B22)),
                        ),
                    ],
                  ],
                ],
              ),
            ),
          ),
        ),
      );
    },
  );

  Widget _invoice(SalesOrderDetail detail) => SaleCard(
    children: [
      Text(
        detail.order.invoiceNumber!,
        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
      ),
      Text(saleDate(detail.issuedAt)),
      Text('Tiền hàng: ${detail.subtotal!.vnd}'),
      Text('Chiết khấu: ${detail.discount!.vnd}'),
      Text('Thuế: ${detail.tax!.vnd}'),
      const Divider(),
      Text(
        'Đã thu: ${detail.paid!.vnd}',
        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
      ),
      Text(
        'Còn phải thu: ${detail.remaining!.vnd}',
        style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
      ),
      const Text(
        'Hóa đơn nội bộ, không phải hóa đơn điện tử. Thu nợ sau bán được xử lý riêng.',
      ),
      FilledButton.icon(
        key: const ValueKey('complete-sale'),
        onPressed: widget.controller.drafts.canComplete
            ? widget.controller.drafts.complete
            : null,
        icon: const Icon(Icons.task_alt),
        label: const Text('Hoàn tất và tạo đơn tiếp theo'),
      ),
      const Text(
        'Nhật ký phải được lưu và đọc lại thành công trước khi mở đơn mới.',
      ),
    ],
  );

  String _label(String field) => switch (field) {
    'amount' => 'Số tiền thu',
    'method' => 'Phương thức',
    'reference_note' => 'Ghi chú',
    'items' => 'Vật tư / lô',
    'branch_id' => 'Chi nhánh',
    _ => 'Dữ liệu yêu cầu',
  };
}

class SaleCard extends StatelessWidget {
  const SaleCard({super.key, required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.symmetric(vertical: 8),
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: const Color(0xFFDFE5DC)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) const SizedBox(height: 12),
          children[i],
        ],
      ],
    ),
  );
}
