import 'dart:async';

import 'package:flutter/material.dart';

import '../auth/auth_controller.dart';
import '../core/numbers.dart';
import 'cart.dart';
import 'draft_submission.dart';
import 'confirm_workspace.dart';

class DraftReview {
  DraftReview.fromCart(AuthController auth, SalesCart cart)
    : origin = auth.api.storageNamespace,
      userId = auth.profile!.userId,
      payload = DraftPayload.fromCart(cart, auth.branch!.id, DateTime.now()),
      previewTotal = cart.totals(DateTime.now()).total,
      warehouse = cart.options.warehouses
          .firstWhere((item) => item.id == cart.warehouseId)
          .name,
      customer = cart.customerId == null
          ? 'Khách lẻ'
          : cart.options.customers
                .firstWhere((item) => item.id == cart.customerId)
                .name,
      lines = List.unmodifiable(
        cart.lines.map((line) => '${line.stock.name} · ${line.stock.lotNo}'),
      );

  final String origin, userId, warehouse, customer;
  final DraftPayload payload;
  final FixedDecimal previewTotal;
  final List<String> lines;
}

class DraftWorkspace extends StatefulWidget {
  const DraftWorkspace({super.key, required this.controller, this.review});
  final AuthController controller;
  final DraftReview? review;

  @override
  State<DraftWorkspace> createState() => _DraftWorkspaceState();
}

class _DraftWorkspaceState extends State<DraftWorkspace> {
  late final String _owner;
  late final String _origin;
  late final Listenable _changes;

  @override
  void initState() {
    super.initState();
    _owner = widget.controller.profile!.userId;
    _origin = widget.controller.api.storageNamespace;
    _changes = Listenable.merge([widget.controller, widget.controller.drafts]);
    unawaited(widget.controller.drafts.restore());
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _changes,
    builder: (context, _) {
      final auth = widget.controller;
      final drafts = auth.drafts;
      final allowed =
          auth.stage == AuthStage.ready &&
          !auth.busy &&
          auth.profile?.userId == _owner &&
          auth.api.storageNamespace == _origin;
      final review = widget.review;
      final attempt = allowed ? drafts.attempt : null;
      final state = drafts.state;
      final detail = allowed ? drafts.detail : null;
      return Scaffold(
        appBar: AppBar(
          title: const Text('Đơn nháp', style: TextStyle(fontSize: 18)),
        ),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 540),
              child: ListView(
                key: const ValueKey('draft-scroll'),
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                children: [
                  if (!allowed)
                    const _Section(
                      children: [
                        Text('Phiên hoặc quyền làm việc đã thay đổi.'),
                        Text(
                          'Quay lại trang chính và đăng nhập đúng tài khoản để kiểm tra trạng thái. Dấu vết tạo đơn vẫn được giữ.',
                        ),
                      ],
                    )
                  else ...[
                    Text(
                      auth.branch!.name,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Đơn nháp chưa thu tiền, chưa trừ tồn và không giữ hàng. Chỉ xác nhận bán sau khi kiểm tra.',
                      style: TextStyle(height: 1.5, color: Colors.black54),
                    ),
                    const SizedBox(height: 20),
                    if (drafts.busy || state == DraftState.loading)
                      _Section(
                        children: [
                          const LinearProgressIndicator(),
                          Text(
                            state == DraftState.sending
                                ? 'Đang ghi nhận yêu cầu… Không gửi lại.'
                                : 'Đang kiểm tra trạng thái…',
                          ),
                        ],
                      ),
                    if (state == DraftState.storageBlocked) ...[
                      const _Section(
                        children: [
                          Text(
                            'Tạm khóa tạo nháp',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            'Không xác minh được bộ nhớ. Không gửi lại hoặc xóa dữ liệu ứng dụng để bỏ qua dấu vết.',
                          ),
                        ],
                      ),
                      OutlinedButton.icon(
                        onPressed: drafts.busy ? null : drafts.restore,
                        icon: const Icon(Icons.storage_outlined),
                        label: const Text('Đọc lại trạng thái đã lưu'),
                      ),
                    ] else if (state == DraftState.unknownOutcome) ...[
                      const _Section(
                        children: [
                          Text(
                            'Chưa xác định kết quả tạo đơn',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            'Máy chủ có thể đã tạo nháp. Lần gửi này được giữ lại để đối chiếu; không tạo lại.',
                          ),
                          Text(
                            'Có thể tra cứu lịch sử từ trang chính. Không tìm thấy trong danh sách gần đây không chứng minh đơn chưa tồn tại.',
                          ),
                        ],
                      ),
                    ] else if (state == DraftState.knownId &&
                        attempt != null) ...[
                      _Section(
                        children: [
                          const Text(
                            'Đã tạo đơn nháp',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          SelectableText('ID ${attempt.orderId}'),
                          if (auth.branch?.id != attempt.payload.branchId)
                            Text(
                              'Chọn lại chi nhánh ID ${attempt.payload.branchId} để tải chi tiết.',
                            ),
                          if (detail == null)
                            const Text(
                              'ID đã lưu. Chưa tải được chi tiết đã xác minh; không tạo lại đơn.',
                            ),
                        ],
                      ),
                      OutlinedButton.icon(
                        onPressed:
                            drafts.busy ||
                                auth.branch?.id != attempt.payload.branchId
                            ? null
                            : drafts.reloadDetail,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Tải lại chi tiết'),
                      ),
                      if (detail != null)
                        _Section(
                          children: [
                            Text(
                              detail.order.number,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              detail.order.isDraft
                                  ? 'Trạng thái: Nháp'
                                  : 'Trạng thái: Đã xác nhận trên hệ thống',
                            ),
                            for (final item in detail.items) ...[
                              Text('${item.name} · ${item.lotNo}'),
                              Text(
                                '${item.quantity.vietnamese} × ${item.price.vnd} · giảm ${item.discount.vnd}',
                              ),
                            ],
                            const Divider(),
                            Text(
                              detail.displayedTotal == null ||
                                      detail.items.any(
                                        (item) => item.taxRate == null,
                                      )
                                  ? 'Chưa xác minh được tổng do thiếu snapshot thuế.'
                                  : 'Tổng theo máy chủ: ${detail.displayedTotal!.vnd}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            FilledButton.icon(
                              key: const ValueKey('review-confirm'),
                              onPressed: drafts.busy
                                  ? null
                                  : () => Navigator.of(context).push(
                                      MaterialPageRoute<void>(
                                        builder: (_) =>
                                            ConfirmWorkspace(controller: auth),
                                      ),
                                    ),
                              icon: const Icon(Icons.receipt_long_outlined),
                              label: const Text('Xem lại bán hàng / hóa đơn'),
                            ),
                          ],
                        ),
                    ] else if (!drafts.busy && state != DraftState.loading) ...[
                      if (state == DraftState.rejected)
                        const _Section(
                          children: [
                            Text(
                              'Yêu cầu đã bị từ chối',
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              'Đơn chưa được tạo từ yêu cầu bị từ chối này. Kiểm tra dữ liệu trước một lần gửi mới có chủ đích.',
                            ),
                          ],
                        ),
                      if (review != null &&
                          review.origin == _origin &&
                          review.userId == _owner &&
                          review.payload.branchId == auth.branch?.id) ...[
                        _Section(
                          children: [
                            Text(
                              'Xem lại giỏ',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            Text('Kho: ${review.warehouse}'),
                            Text('Khách: ${review.customer}'),
                            for (
                              var i = 0;
                              i < review.payload.items.length;
                              i++
                            ) ...[
                              Text(review.lines[i]),
                              Text(
                                'Số lượng ${FixedDecimal.parse(review.payload.items[i]['quantity']!, scale: 3).vietnamese} · chiết khấu ${FixedDecimal.parse(review.payload.items[i]['discount_amount']!, scale: 2).vnd}',
                              ),
                            ],
                            const Divider(),
                            Text(
                              'Tổng dự kiến: ${review.previewTotal.vnd}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const Text(
                              'Giá và thuế chính thức được máy chủ tính khi tạo nháp.',
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        FilledButton.icon(
                          key: const ValueKey('create-draft'),
                          onPressed: drafts.canCreate
                              ? () => drafts.submit(
                                  review.payload,
                                  origin: review.origin,
                                  userId: review.userId,
                                )
                              : null,
                          icon: const Icon(Icons.note_add_outlined),
                          label: Text(
                            state == DraftState.rejected
                                ? 'Gửi yêu cầu mới từ giỏ đã xem lại'
                                : 'Tạo đơn nháp',
                          ),
                        ),
                      ] else
                        const _Section(
                          children: [
                            Text(
                              'Không có yêu cầu cần phục hồi. Mở giỏ hàng để chuẩn bị đơn nháp.',
                            ),
                          ],
                        ),
                    ],
                    if (attempt != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Text(
                          'Lần gửi ${attempt.attemptId}\nChi nhánh ${attempt.payload.branchId} · kho ${attempt.payload.warehouseId}',
                          style: const TextStyle(
                            color: Colors.black54,
                            height: 1.5,
                          ),
                        ),
                      ),
                    if (drafts.error != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        drafts.error!.message,
                        style: const TextStyle(
                          color: Color(0xFF9B3B22),
                          height: 1.5,
                        ),
                      ),
                      for (final entry in drafts.error!.fieldErrors.entries)
                        Text(
                          '${_fieldLabel(entry.key)}: ${entry.value.join(' ')}',
                          style: const TextStyle(
                            color: Color(0xFF9B3B22),
                            height: 1.5,
                          ),
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

  String _fieldLabel(String key) {
    final item = RegExp(
      r'^items\.(\d+)\.(quantity|discount_amount|lot_id)$',
    ).firstMatch(key);
    if (item != null) {
      final field = switch (item.group(2)) {
        'quantity' => 'Số lượng',
        'discount_amount' => 'Chiết khấu',
        _ => 'Lô',
      };
      return 'Dòng ${int.parse(item.group(1)!) + 1} · $field';
    }
    return switch (key) {
      'branch_id' => 'Chi nhánh',
      'warehouse_id' => 'Kho',
      'customer_id' => 'Khách hàng',
      'items' => 'Các dòng vật tư',
      _ => key,
    };
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFDFE5DC)),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const SizedBox(height: 10),
            children[i],
          ],
        ],
      ),
    ),
  );
}
