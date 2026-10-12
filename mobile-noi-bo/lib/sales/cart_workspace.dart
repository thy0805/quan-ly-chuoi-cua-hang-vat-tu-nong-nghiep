import 'package:flutter/material.dart';

import '../auth/api_client.dart';
import '../auth/auth_controller.dart';
import 'cart.dart';
import 'models.dart';
import 'repository.dart';

class CartWorkspace extends StatefulWidget {
  const CartWorkspace({super.key, required this.controller});
  final AuthController controller;

  @override
  State<CartWorkspace> createState() => _CartWorkspaceState();
}

class _CartWorkspaceState extends State<CartWorkspace> {
  SalesCart? _cart;
  ApiFailure? _error;
  bool _loading = true;
  bool _closing = false;
  int _generation = 0;
  int _warehouseRevision = 0;
  Route<dynamic>? _overlayRoute;
  String get _scope =>
      '${widget.controller.profile?.userId}/${widget.controller.branch?.id}';
  bool get _allowed =>
      widget.controller.stage == AuthStage.ready && !widget.controller.busy;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_authChanged);
    _load();
  }

  void _authChanged() {
    if (!mounted) return;
    _generation++;
    final overlay = _overlayRoute;
    _overlayRoute = null;
    if (overlay != null) {
      final navigator = Navigator.of(context);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (overlay.isActive) navigator.removeRoute(overlay);
      });
    }
    setState(() {
      _cart = null;
      _error = null;
      _loading = true;
    });
    if (widget.controller.busy) return;
    if (!_allowed) {
      if (!_closing) {
        _closing = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            final route = ModalRoute.of(context);
            if (route != null && route.isActive) {
              Navigator.of(context).removeRoute(route);
            }
          }
        });
      }
    } else {
      _load();
    }
  }

  Future<void> _load() async {
    if (!_allowed || _closing) return;
    final generation = ++_generation;
    final scope = _scope;
    final branch = widget.controller.branch!;
    setState(() {
      _loading = true;
      _cart = null;
      _error = null;
    });
    try {
      final options = await SalesRepository(widget.controller).options();
      if (!mounted ||
          generation != _generation ||
          !_allowed ||
          scope != _scope) {
        return;
      }
      setState(() {
        _cart = SalesCart(options, branch.id, branch.chainId);
        if (_cart!.options.warehouses.length == 1) {
          _cart!.selectWarehouse(_cart!.options.warehouses.single.id);
        }
      });
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

  Future<bool> _discard(String title) async {
    if (_cart?.lines.isEmpty ?? true) return true;
    final cart = _cart;
    final scope = _scope;
    final result = await showDialog<bool>(
      context: context,
      builder: (context) {
        _overlayRoute = ModalRoute.of(context);
        return AlertDialog(
          title: Text(title),
          content: const Text(
            'Các dòng trong giỏ sẽ được bỏ. Chưa có chứng từ nào được tạo.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Giữ giỏ'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Bỏ giỏ'),
            ),
          ],
        );
      },
    );
    _overlayRoute = null;
    return mounted &&
        _allowed &&
        identical(cart, _cart) &&
        scope == _scope &&
        result == true;
  }

  Future<void> _pickStock() async {
    final cart = _cart;
    if (cart == null || !_allowed || cart.warehouseId == null) return;
    final scope = _scope;
    final item = await showModalBottomSheet<SalesStock>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) {
        _overlayRoute = ModalRoute.of(context);
        return ListenableBuilder(
          listenable: widget.controller,
          builder: (_, _) => !_allowed || scope != _scope
              ? const SizedBox.shrink()
              : _StockPicker(cart: cart),
        );
      },
    );
    _overlayRoute = null;
    if (!mounted ||
        !_allowed ||
        cart != _cart ||
        scope != _scope ||
        item == null) {
      return;
    }
    try {
      setState(() => cart.add(item, DateTime.now()));
    } on FormatException catch (error) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
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
    canPop: !_allowed || (_cart?.lines.isEmpty ?? true),
    onPopInvokedWithResult: (didPop, _) async {
      if (!didPop && await _discard('Rời giỏ hàng?') && mounted) {
        setState(() => _cart?.clear());
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) Navigator.of(context).pop();
        });
      }
    },
    child: Scaffold(
      appBar: AppBar(
        title: const Text('Giỏ bán hàng', style: TextStyle(fontSize: 18)),
        actions: [
          IconButton(
            tooltip: 'Tải lại dữ liệu',
            onPressed: !_allowed || _loading
                ? null
                : () async {
                    if (await _discard('Tải lại dữ liệu?')) await _load();
                  },
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
                : ListView(
                    key: const ValueKey('cart-scroll'),
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                    children: [
                      Text(
                        widget.controller.branch!.name,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 12),
                      const _Notice(
                        'Giỏ chỉ nằm trên màn hình này, chưa tạo đơn hoặc giữ hàng. Giá, thuế và tồn kho là dữ liệu tại lúc tải; máy chủ sẽ kiểm lại khi xác nhận bán.',
                      ),
                      const SizedBox(height: 20),
                      if (_error != null) ...[
                        _Notice(_error!.message, error: true),
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          onPressed: _load,
                          icon: const Icon(Icons.refresh),
                          label: const Text('Tải lại'),
                        ),
                      ] else if (_cart!.options.warehouses.isEmpty)
                        const _Notice(
                          'Chưa có kho được phép bán trong chi nhánh này.',
                        )
                      else
                        ..._cartWidgets(_cart!),
                    ],
                  ),
          ),
        ),
      ),
    ),
  );

  List<Widget> _cartWidgets(SalesCart cart) {
    CartTotals? totals;
    String? totalError;
    try {
      totals = cart.totals(DateTime.now());
    } on FormatException catch (error) {
      totalError =
          cart.lines.any(
            (line) => line.quantityError != null || line.discountError != null,
          )
          ? 'Kiểm tra số lượng hoặc chiết khấu đang báo lỗi.'
          : error.message;
    }
    return [
      DropdownButtonFormField<String>(
        key: ValueKey('warehouse-${cart.warehouseId}-$_warehouseRevision'),
        initialValue: cart.warehouseId,
        isExpanded: true,
        decoration: const InputDecoration(labelText: 'Kho xuất'),
        hint: const Text('Chọn kho'),
        items: [
          for (final item in cart.options.warehouses)
            DropdownMenuItem(
              value: item.id,
              child: Text(item.name, overflow: TextOverflow.ellipsis),
            ),
        ],
        onChanged: (id) async {
          if (id == null || id == cart.warehouseId) return;
          if (await _discard('Đổi kho xuất?') &&
              mounted &&
              identical(cart, _cart)) {
            setState(() => cart.selectWarehouse(id));
          } else if (mounted) {
            setState(() => _warehouseRevision++);
          }
        },
      ),
      const SizedBox(height: 16),
      DropdownButtonFormField<String>(
        key: ValueKey('customer-${cart.customerId}'),
        initialValue: cart.customerId ?? '',
        isExpanded: true,
        decoration: const InputDecoration(labelText: 'Khách hàng'),
        items: [
          const DropdownMenuItem(value: '', child: Text('Khách lẻ')),
          for (final item in cart.options.customers)
            DropdownMenuItem(
              value: item.id,
              child: Text(item.name, overflow: TextOverflow.ellipsis),
            ),
        ],
        onChanged: (id) =>
            setState(() => cart.selectCustomer(id == '' ? null : id)),
      ),
      const SizedBox(height: 24),
      Text(
        'Giỏ hàng · ${cart.lines.length}/50 lô',
        style: Theme.of(context).textTheme.titleLarge,
      ),
      const SizedBox(height: 8),
      const Text(
        'Dùng dấu phẩy hoặc dấu chấm cho phần lẻ, không nhập dấu phân cách hàng nghìn. Số lượng tối đa 3 số lẻ; chiết khấu tối đa 2 số lẻ.',
        style: TextStyle(color: Colors.black54, height: 1.5),
      ),
      const SizedBox(height: 16),
      if (cart.lines.isEmpty)
        const _Notice('Giỏ đang trống. Chọn kho rồi thêm vật tư theo lô.')
      else
        for (final line in cart.lines)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _LineEditor(
              key: ObjectKey(line),
              line: line,
              changed: () => setState(() {}),
              remove: () => setState(() => cart.remove(line)),
            ),
          ),
      const SizedBox(height: 12),
      OutlinedButton.icon(
        onPressed: cart.warehouseId == null || cart.lines.length >= 50
            ? null
            : _pickStock,
        icon: const Icon(Icons.add),
        label: const Text('Thêm vật tư / lô'),
      ),
      const SizedBox(height: 20),
      if (totalError != null)
        _Notice('Chưa thể tính tổng: $totalError', error: true)
      else if (cart.lines.isNotEmpty)
        _Panel(
          children: [
            Text(
              'Tạm tính giỏ hàng',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            _Amount('Trước chiết khấu', totals!.gross.vnd),
            _Amount('Chiết khấu', totals.discount.vnd),
            _Amount('Trước thuế', totals.net.vnd),
            _Amount('Thuế', totals.tax.vnd),
            const Divider(height: 24),
            _Amount('Tổng dự kiến', totals.total.vnd, strong: true),
            const SizedBox(height: 8),
            const Text(
              'Chưa thu tiền, chưa trừ tồn.',
              style: TextStyle(color: Colors.black54),
            ),
          ],
        ),
    ];
  }
}

class _StockPicker extends StatefulWidget {
  const _StockPicker({required this.cart});
  final SalesCart cart;
  @override
  State<_StockPicker> createState() => _StockPickerState();
}

class _StockPickerState extends State<_StockPicker> {
  String _search = '';
  @override
  Widget build(BuildContext context) {
    final rows = widget.cart.stock
        .where(
          (item) => '${item.name} ${item.code} ${item.lotNo}'
              .toLowerCase()
              .contains(_search.trim().toLowerCase()),
        )
        .toList();
    return FractionallySizedBox(
      heightFactor: 0.88,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          16,
          20,
          12 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: ListView(
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Chọn vật tư / lô',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                  ),
                ),
                IconButton(
                  tooltip: 'Đóng',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              decoration: const InputDecoration(
                labelText: 'Tìm tên, mã vật tư hoặc lô',
                prefixIcon: Icon(Icons.search),
              ),
              onChanged: (value) => setState(() => _search = value),
            ),
            const SizedBox(height: 12),
            if (rows.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Text('Không có lô phù hợp trong kho này.'),
              )
            else
              for (final item in rows) ...[
                Builder(
                  builder: (context) {
                    final error = widget.cart.unavailable(item, DateTime.now());
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        item.name,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(
                        '${item.code} · Lô ${item.lotNo}\nTồn lúc tải: ${item.quantity.vietnamese} ${item.unitName}\n${item.price.vnd} / ${item.unitName} · Thuế ${item.taxRate?.vietnamese ?? 'chưa cấu hình'}${item.taxRate == null ? '' : '%'}\nHạn: ${item.expiresOn ?? 'Không có'}${error == null ? '' : '\n$error'}',
                        style: TextStyle(
                          height: 1.5,
                          color: error == null
                              ? null
                              : Theme.of(context).colorScheme.error,
                        ),
                      ),
                      trailing: Icon(
                        error == null ? Icons.add_circle_outline : Icons.block,
                        color: error == null
                            ? Theme.of(context).colorScheme.primary
                            : Colors.grey,
                      ),
                      enabled: error == null,
                      onTap: error == null
                          ? () => Navigator.pop(context, item)
                          : null,
                    );
                  },
                ),
                const Divider(),
              ],
          ],
        ),
      ),
    );
  }
}

class _LineEditor extends StatelessWidget {
  const _LineEditor({
    super.key,
    required this.line,
    required this.changed,
    required this.remove,
  });
  final CartLine line;
  final VoidCallback changed, remove;
  @override
  Widget build(BuildContext context) {
    String? amount;
    String? amountError;
    try {
      amount = line.amounts(DateTime.now()).total.vnd;
    } on FormatException catch (error) {
      amountError = error.message;
    }
    return _Panel(
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                line.stock.name,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 17,
                ),
              ),
            ),
            IconButton(
              tooltip: 'Bỏ lô ${line.stock.lotNo}',
              onPressed: remove,
              icon: const Icon(Icons.delete_outline),
            ),
          ],
        ),
        Text(
          'Lô ${line.stock.lotNo} · ${line.stock.price.vnd} / ${line.stock.unitName}\nTồn lúc tải: ${line.stock.quantity.vietnamese} ${line.stock.unitName} · Thuế ${line.stock.taxRate?.vietnamese}%',
          style: const TextStyle(color: Colors.black54, height: 1.5),
        ),
        const SizedBox(height: 16),
        TextFormField(
          key: ValueKey('quantity-${line.stock.lotId}'),
          initialValue: line.quantityText,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: 'Số lượng (${line.stock.unitName})',
            errorText: line.quantityError,
            errorMaxLines: 4,
          ),
          onChanged: (value) {
            line.quantityText = value;
            changed();
          },
        ),
        const SizedBox(height: 16),
        TextFormField(
          key: ValueKey('discount-${line.stock.lotId}'),
          initialValue: line.discountText,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: 'Chiết khấu dòng (VND)',
            errorText: line.discountError,
            errorMaxLines: 4,
          ),
          onChanged: (value) {
            line.discountText = value;
            changed();
          },
        ),
        const SizedBox(height: 16),
        if (amount != null)
          _Amount('Dòng gồm thuế', amount)
        else if (line.quantityError == null && line.discountError == null)
          Text(
            amountError!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
      ],
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.children});
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: const Color(0xFFE0E5DD)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    ),
  );
}

class _Amount extends StatelessWidget {
  const _Amount(this.label, this.amount, {this.strong = false});
  final String label, amount;
  final bool strong;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Wrap(
      alignment: WrapAlignment.spaceBetween,
      spacing: 12,
      runSpacing: 4,
      children: [
        Text(label),
        Text(
          amount,
          style: TextStyle(
            fontWeight: strong ? FontWeight.w800 : FontWeight.w600,
            fontSize: strong ? 20 : 15,
          ),
        ),
      ],
    ),
  );
}

class _Notice extends StatelessWidget {
  const _Notice(this.text, {this.error = false});
  final String text;
  final bool error;
  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: error,
    child: Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: error ? const Color(0xFFFFEDE6) : const Color(0xFFE7EEE5),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        text,
        style: TextStyle(
          height: 1.5,
          color: error ? const Color(0xFF823D22) : const Color(0xFF153F36),
        ),
      ),
    ),
  );
}
