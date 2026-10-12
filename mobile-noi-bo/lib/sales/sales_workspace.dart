import 'package:flutter/material.dart';

import '../auth/api_client.dart';
import '../auth/auth_controller.dart';
import '../core/numbers.dart';
import 'models.dart';
import 'repository.dart';

class SalesWorkspace extends StatefulWidget {
  const SalesWorkspace({super.key, required this.controller});
  final AuthController controller;

  @override
  State<SalesWorkspace> createState() => _SalesWorkspaceState();
}

class _SalesWorkspaceState extends State<SalesWorkspace> {
  late final SalesRepository _repository;
  List<SalesOrderSummary>? _orders;
  SalesOrderDetail? _detail;
  ApiFailure? _error;
  String? _selectedId;
  bool _loading = true;
  bool _closing = false;
  int _generation = 0;

  bool get _allowed =>
      widget.controller.stage == AuthStage.ready && !widget.controller.busy;
  String get _scope =>
      '${widget.controller.profile?.userId}/${widget.controller.branch?.id}';

  @override
  void initState() {
    super.initState();
    _repository = SalesRepository(widget.controller);
    widget.controller.addListener(_authChanged);
    _load();
  }

  void _authChanged() {
    if (!mounted) return;
    _generation++;
    setState(() {
      _orders = null;
      _detail = null;
      _error = null;
      _loading = true;
    });
    if (widget.controller.busy) return;
    if (!_allowed) {
      if (!_closing) {
        _closing = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) Navigator.of(context).pop();
        });
      }
    } else {
      _load();
    }
  }

  Future<void> _load({String? id, bool history = false}) async {
    if (!_allowed || !mounted || _closing) return;
    if (history) _selectedId = null;
    if (id != null) _selectedId = id;
    final selected = _selectedId;
    final scope = _scope;
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _orders = null;
      _detail = null;
      _error = null;
    });
    try {
      if (selected == null) {
        final orders = await _repository.history();
        if (!mounted ||
            generation != _generation ||
            !_allowed ||
            scope != _scope) {
          return;
        }
        setState(() => _orders = orders);
      } else {
        final detail = await _repository.detail(selected);
        if (!mounted ||
            generation != _generation ||
            !_allowed ||
            scope != _scope) {
          return;
        }
        setState(() => _detail = detail);
      }
    } on ApiFailure catch (error) {
      if (mounted && generation == _generation && _allowed && scope == _scope) {
        setState(() => _error = error);
      }
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  void dispose() {
    _generation++;
    widget.controller.removeListener(_authChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: _selectedId == null || !_allowed,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop && _allowed) _load(history: true);
    },
    child: Scaffold(
      appBar: AppBar(
        leading: BackButton(
          onPressed: () {
            if (_selectedId == null || !_allowed) {
              Navigator.of(context).pop();
            } else {
              _load(history: true);
            }
          },
        ),
        title: Text(
          _selectedId == null ? 'Lịch sử bán hàng' : 'Chi tiết đơn hàng',
          style: const TextStyle(fontSize: 18),
        ),
        actions: [
          IconButton(
            onPressed: !_allowed || _loading ? null : () => _load(),
            tooltip: 'Tải lại',
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 540),
            child: !_allowed || _loading
                ? const Center(child: CircularProgressIndicator())
                : RefreshIndicator(
                    onRefresh: _load,
                    child: ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                      children: [
                        Wrap(
                          spacing: 8,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            const Chip(
                              avatar: Icon(Icons.visibility_outlined, size: 18),
                              label: Text('Chỉ xem'),
                            ),
                            Text(
                              widget.controller.branch!.name,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        if (_error != null)
                          _FailureCard(error: _error!, reload: () => _load())
                        else if (_detail != null)
                          ..._detailWidgets(_detail!)
                        else ...[
                          const Text(
                            '50 đơn gần nhất trong phạm vi được cấp; chỉ hiển thị chi nhánh đang chọn.',
                            style: TextStyle(
                              color: Colors.black54,
                              height: 1.5,
                            ),
                          ),
                          const SizedBox(height: 20),
                          if (_orders?.isEmpty ?? true)
                            const _Panel(
                              children: [
                                Icon(Icons.receipt_long_outlined, size: 40),
                                SizedBox(height: 16),
                                Text(
                                  'Chưa có đơn hàng trong danh sách hiện tại.',
                                ),
                              ],
                            )
                          else
                            for (final order in _orders!) _orderCard(order),
                        ],
                      ],
                    ),
                  ),
          ),
        ),
      ),
    ),
  );

  Widget _orderCard(SalesOrderSummary order) => Card(
    margin: const EdgeInsets.only(bottom: 14),
    color: Colors.white,
    elevation: 0,
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      key: ValueKey('order-${order.id}'),
      onTap: () => _load(id: order.id),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 10,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  order.number,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 17,
                  ),
                ),
                _Status(draft: order.isDraft),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              order.customerId == null
                  ? 'Khách lẻ'
                  : order.customerName ?? 'Khách hàng đã lưu',
            ),
            const SizedBox(height: 6),
            Text(
              order.isDraft ? 'Chưa xác nhận' : saleDate(order.soldAt),
              style: const TextStyle(color: Colors.black54, fontSize: 12),
            ),
            const Divider(height: 26),
            Wrap(
              spacing: 12,
              runSpacing: 6,
              children: [
                Text(
                  order.isDraft ? 'Tổng chưa chốt' : order.total.vnd,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF153F36),
                  ),
                ),
                const Text(
                  'Xem chi tiết',
                  style: TextStyle(color: Color(0xFF153F36)),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );

  List<Widget> _detailWidgets(SalesOrderDetail detail) {
    final order = detail.order;
    String money(FixedDecimal? value) => value?.vnd ?? 'Chưa có dữ liệu';
    return [
      _Panel(
        children: [
          Text(
            order.number,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: Color(0xFF153F36),
            ),
          ),
          const SizedBox(height: 10),
          _Status(draft: order.isDraft),
          const SizedBox(height: 18),
          _Fact(
            label: 'Khách hàng',
            value: order.customerId == null
                ? 'Khách lẻ'
                : order.customerName ?? 'Khách hàng đã lưu',
          ),
          if (detail.customerPhone != null)
            _Fact(label: 'Điện thoại', value: detail.customerPhone!),
          if (order.invoiceNumber != null)
            _Fact(label: 'Hóa đơn', value: order.invoiceNumber!),
          if (!order.isDraft)
            _Fact(label: 'Xác nhận', value: saleDate(order.soldAt)),
          if (detail.createdBy == widget.controller.profile!.userId)
            const Text(
              'Đơn do bạn lập',
              style: TextStyle(color: Colors.black54),
            ),
        ],
      ),
      const SizedBox(height: 22),
      Text(
        'Vật tư • ${detail.items.length} dòng',
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
      ),
      const SizedBox(height: 12),
      for (final item in detail.items)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: _Panel(
            children: [
              Text(
                item.name,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '${item.code} • Lô ${item.lotNo}',
                style: const TextStyle(color: Colors.black54),
              ),
              const Divider(height: 24),
              _Fact(label: 'Số lượng', value: item.quantity.vietnamese),
              _Fact(label: 'Đơn giá', value: item.price.vnd),
              _Fact(label: 'Chiết khấu', value: item.discount.vnd),
              _Fact(label: 'Tiền sau giảm', value: item.net.vnd),
              _Fact(
                label:
                    'Thuế${item.taxRate == null ? '' : ' (${item.taxRate!.vietnamese}%)'}',
                value: money(item.tax),
              ),
            ],
          ),
        ),
      const SizedBox(height: 10),
      _Panel(
        children: [
          if (!order.isDraft) ...[
            _Fact(label: 'Tiền hàng', value: money(detail.subtotal)),
            _Fact(label: 'Chiết khấu', value: money(detail.discount)),
            _Fact(label: 'Thuế', value: money(detail.tax)),
            const Divider(height: 24),
          ],
          _Fact(
            label: order.isDraft ? 'Tổng theo dòng đã lưu' : 'Tổng hóa đơn',
            value: money(detail.displayedTotal),
            prominent: true,
          ),
          if (!order.isDraft) ...[
            const SizedBox(height: 12),
            _Fact(label: 'Đã thu', value: money(detail.paid)),
            _Fact(label: 'Còn phải thu', value: money(detail.remaining)),
          ],
        ],
      ),
      const SizedBox(height: 18),
      Text(
        order.isDraft
            ? 'Đơn nháp chưa có hóa đơn và chưa trừ tồn. Tổng được tính từ các dòng đã lưu; dòng thiếu dữ liệu thuế chưa thể xác định tổng.'
            : 'Thông tin hóa đơn và thanh toán được đọc từ máy chủ. Màn này không tạo đơn, xác nhận đơn hoặc ghi nhận khoản thu.',
        style: const TextStyle(color: Colors.black54, height: 1.5),
      ),
    ];
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    ),
  );
}

class _Status extends StatelessWidget {
  const _Status({required this.draft});
  final bool draft;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: draft ? const Color(0xFFFFF0D4) : const Color(0xFFE0F0DF),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      draft ? 'Nháp' : 'Đã xác nhận',
      style: TextStyle(
        color: draft ? const Color(0xFF735116) : const Color(0xFF153F36),
        fontSize: 12,
        fontWeight: FontWeight.w600,
      ),
    ),
  );
}

class _Fact extends StatelessWidget {
  const _Fact({
    required this.label,
    required this.value,
    this.prominent = false,
  });
  final String label, value;
  final bool prominent;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: LayoutBuilder(
      builder: (context, constraints) {
        final style = TextStyle(
          fontWeight: prominent ? FontWeight.w800 : FontWeight.w600,
          fontSize: prominent ? 20 : 15,
          color: const Color(0xFF153F36),
        );
        if (constraints.maxWidth < 280 ||
            MediaQuery.textScalerOf(context).scale(1) > 1.2) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(color: Colors.black54)),
              const SizedBox(height: 4),
              Text(value, style: style),
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(label, style: const TextStyle(color: Colors.black54)),
            ),
            const SizedBox(width: 12),
            Flexible(
              child: Text(value, textAlign: TextAlign.right, style: style),
            ),
          ],
        );
      },
    ),
  );
}

class _FailureCard extends StatelessWidget {
  const _FailureCard({required this.error, required this.reload});
  final ApiFailure error;
  final VoidCallback reload;
  @override
  Widget build(BuildContext context) => _Panel(
    children: [
      const Icon(Icons.cloud_off_outlined, size: 40, color: Color(0xFF823D22)),
      const SizedBox(height: 16),
      Text(error.message, style: const TextStyle(height: 1.5)),
      if (error.status != null)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            'HTTP ${error.status}',
            style: const TextStyle(color: Colors.black54),
          ),
        ),
      const SizedBox(height: 16),
      OutlinedButton.icon(
        onPressed: reload,
        icon: const Icon(Icons.refresh),
        label: const Text('Tải lại thông tin'),
      ),
    ],
  );
}
