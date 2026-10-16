import 'package:flutter/material.dart';

import '../auth/api_client.dart';
import '../auth/auth_controller.dart';
import 'models.dart';
import 'repository.dart';

const _ink = Color(0xFF153F36);

class TransferWorkspace extends StatefulWidget {
  const TransferWorkspace({super.key, required this.controller});
  final AuthController controller;

  @override
  State<TransferWorkspace> createState() => _TransferWorkspaceState();
}

class _TransferWorkspaceState extends State<TransferWorkspace> {
  late final TransferRepository _repository;
  TransferPage? _page;
  TransferDetail? _detail;
  ApiFailure? _error;
  String? _selectedId;
  int _pageNumber = 1;
  int _generation = 0;
  bool _loading = true;
  bool _closing = false;

  bool get _allowed =>
      widget.controller.stage == AuthStage.ready && !widget.controller.busy;
  String get _scope =>
      '${widget.controller.profile?.userId}/${widget.controller.branch?.id}';

  @override
  void initState() {
    super.initState();
    _repository = TransferRepository(widget.controller);
    widget.controller.addListener(_authChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _load();
    });
  }

  void _authChanged() {
    if (!mounted) return;
    _generation++;
    setState(() {
      _page = null;
      _detail = null;
      _error = null;
      _loading = true;
    });
    if (widget.controller.busy) return;
    if (!_allowed) {
      if (_closing) return;
      _closing = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).pop();
      });
    } else {
      _pageNumber = 1;
      _load();
    }
  }

  Future<void> _load({String? id, int? page, bool list = false}) async {
    if (!mounted || !_allowed || _closing) return;
    if (list) _selectedId = null;
    if (id != null) _selectedId = id;
    if (page != null) _pageNumber = page;
    final selected = _selectedId;
    final scope = _scope;
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _error = null;
      _page = null;
      _detail = null;
    });
    try {
      if (selected == null) {
        final result = await _repository.page(_pageNumber);
        if (mounted &&
            generation == _generation &&
            _allowed &&
            scope == _scope) {
          setState(() => _page = result);
        }
      } else {
        final result = await _repository.detail(selected);
        if (mounted &&
            generation == _generation &&
            _allowed &&
            scope == _scope) {
          setState(() => _detail = result);
        }
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

  void _back() {
    if (_selectedId == null || !_allowed) {
      Navigator.of(context).pop();
    } else {
      _load(list: true);
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
      if (!didPop && _allowed) _load(list: true);
    },
    child: Scaffold(
      appBar: AppBar(
        leading: BackButton(onPressed: _back),
        title: Text(
          _selectedId == null ? 'Điều chuyển kho' : 'Chi tiết điều chuyển',
          style: const TextStyle(fontSize: 18),
        ),
        actions: [
          IconButton(
            key: const Key('reload-transfers'),
            tooltip: 'Tải lại',
            onPressed: !_allowed || _loading ? null : () => _load(),
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
                    onRefresh: () => _load(),
                    child: ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                      children: [
                        Wrap(
                          spacing: 10,
                          runSpacing: 6,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            const Chip(
                              avatar: Icon(Icons.visibility_outlined, size: 18),
                              label: Text('Chỉ xem'),
                            ),
                            Text(widget.controller.branch!.name),
                          ],
                        ),
                        const SizedBox(height: 16),
                        if (_error != null)
                          _failure()
                        else if (_detail != null)
                          ..._detailWidgets(_detail!)
                        else if (_page != null)
                          ..._listWidgets(_page!),
                      ],
                    ),
                  ),
          ),
        ),
      ),
    ),
  );

  List<Widget> _listWidgets(TransferPage page) => [
    const Text(
      'Phiếu có kho nguồn hoặc kho đích thuộc chi nhánh đang chọn. Danh sách được phân trang theo phạm vi API cấp.',
      style: TextStyle(color: Colors.black54, height: 1.5),
    ),
    const SizedBox(height: 20),
    if (page.rows.isEmpty)
      const _Panel(
        children: [
          Icon(Icons.local_shipping_outlined, size: 40, color: _ink),
          SizedBox(height: 14),
          Text('Chưa có phiếu phù hợp trên trang này.'),
          SizedBox(height: 8),
          Text('Bạn có thể kiểm tra trang khác nếu còn trang tiếp theo.'),
        ],
      ),
    for (final row in page.rows)
      Card(
        margin: const EdgeInsets.only(bottom: 14),
        color: Colors.white,
        elevation: 0,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: ValueKey('transfer-${row.id}'),
          onTap: () => _load(id: row.id),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  row.number,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                _Status(transfer: row),
                const Divider(height: 26),
                _Fact(
                  label: 'Từ',
                  value: '${row.fromBranchName} · ${row.fromWarehouseName}',
                ),
                _Fact(
                  label: 'Đến',
                  value: '${row.toBranchName} · ${row.toWarehouseName}',
                ),
                Text(
                  transferDate(row.requestedAt),
                  style: const TextStyle(color: Colors.black54),
                ),
              ],
            ),
          ),
        ),
      ),
    const SizedBox(height: 12),
    Text('Trang ${page.current} / ${page.last}', textAlign: TextAlign.center),
    const SizedBox(height: 10),
    Wrap(
      alignment: WrapAlignment.center,
      spacing: 12,
      runSpacing: 8,
      children: [
        OutlinedButton.icon(
          key: const Key('previous-transfers'),
          onPressed: page.current > 1
              ? () => _load(page: page.current - 1)
              : null,
          icon: const Icon(Icons.chevron_left),
          label: const Text('Trang trước'),
        ),
        OutlinedButton.icon(
          key: const Key('next-transfers'),
          onPressed: page.hasNext ? () => _load(page: page.current + 1) : null,
          icon: const Icon(Icons.chevron_right),
          label: const Text('Trang sau'),
        ),
      ],
    ),
  ];

  List<Widget> _detailWidgets(TransferDetail detail) {
    final row = detail.transfer;
    const timeLabels = {
      'approved_at': 'Duyệt lúc',
      'rejected_at': 'Từ chối lúc',
      'dispatched_at': 'Xuất kho lúc',
      'received_at': 'Nhận hàng lúc',
      'reconciled_at': 'Đối soát lúc',
    };
    return [
      _Panel(
        children: [
          Text(
            row.number,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: _ink,
            ),
          ),
          const SizedBox(height: 12),
          _Status(transfer: row),
          const Divider(height: 28),
          _Fact(
            label: 'Kho nguồn',
            value: '${row.fromBranchName} · ${row.fromWarehouseName}',
          ),
          _Fact(
            label: 'Kho đích',
            value: '${row.toBranchName} · ${row.toWarehouseName}',
          ),
          _Fact(label: 'Người lập', value: row.requesterName),
          _Fact(label: 'Lập lúc', value: transferDate(row.requestedAt)),
          for (final entry in detail.times.entries)
            _Fact(
              label: timeLabels[entry.key]!,
              value: transferDate(entry.value),
            ),
          if (detail.rejectionReason != null)
            _Fact(label: 'Lý do từ chối', value: detail.rejectionReason!),
          if (detail.reconciliationReason != null)
            _Fact(label: 'Lý do đối soát', value: detail.reconciliationReason!),
        ],
      ),
      const SizedBox(height: 20),
      Text(
        'Vật tư và số lượng (${detail.items.length})',
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
      ),
      const SizedBox(height: 12),
      if (detail.items.isEmpty)
        const _Panel(children: [Text('Phiếu chưa có dòng vật tư.')]),
      for (final item in detail.items)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: _Panel(
            children: [
              Text(
                item.productName,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 17,
                ),
              ),
              const SizedBox(height: 8),
              Text('${item.productCode} · Lô ${item.lotNumber}'),
              const Divider(height: 26),
              _Fact(
                label: 'Yêu cầu',
                value: '${item.requested.vietnamese} ${item.unitName}',
              ),
              _Fact(
                label: 'Đã xuất',
                value: '${item.dispatched.vietnamese} ${item.unitName}',
              ),
              _Fact(
                label: 'Thực nhận ban đầu',
                value: '${item.received.vietnamese} ${item.unitName}',
              ),
              _Fact(
                label: 'Nhận bổ sung',
                value: '${item.supplemental.vietnamese} ${item.unitName}',
              ),
              _Fact(
                label: 'Hoàn kho nguồn',
                value: '${item.returned.vietnamese} ${item.unitName}',
              ),
              _Fact(
                label: 'Hao hụt đã xác nhận',
                value: '${item.lost.vietnamese} ${item.unitName}',
              ),
            ],
          ),
        ),
      const Text(
        'Số liệu theo phiếu đã tải. Màn hình này không thay đổi tồn kho.',
        style: TextStyle(color: Colors.black54, height: 1.5),
      ),
    ];
  }

  Widget _failure() => _Panel(
    children: [
      const Icon(Icons.cloud_off_outlined, size: 34, color: _ink),
      const SizedBox(height: 12),
      Text(
        _error!.status == 404
            ? 'Không tìm thấy phiếu điều chuyển trong phạm vi được cấp.'
            : _error!.message,
        key: const Key('transfer-error'),
      ),
      if (_error!.status != null) ...[
        const SizedBox(height: 8),
        Text(
          'HTTP ${_error!.status}',
          style: const TextStyle(color: Colors.black54),
        ),
      ],
      const SizedBox(height: 16),
      OutlinedButton.icon(
        key: const Key('retry-transfers'),
        onPressed: () => _load(),
        icon: const Icon(Icons.refresh),
        label: const Text('Thử tải lại'),
      ),
    ],
  );
}

class _Panel extends StatelessWidget {
  const _Panel({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
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

class _Fact extends StatelessWidget {
  const _Fact({required this.label, required this.value});
  final String label, value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(color: Colors.black54, fontSize: 12),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: const TextStyle(fontWeight: FontWeight.w600, color: _ink),
        ),
      ],
    ),
  );
}

class _Status extends StatelessWidget {
  const _Status({required this.transfer});
  final TransferSummary transfer;

  @override
  Widget build(BuildContext context) {
    final attention = {'discrepancy', 'rejected'}.contains(transfer.status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: attention ? const Color(0xFFFFF1D8) : const Color(0xFFE0F0DF),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        transfer.statusLabel,
        style: TextStyle(
          fontWeight: FontWeight.w600,
          color: attention ? const Color(0xFF735116) : _ink,
        ),
      ),
    );
  }
}
