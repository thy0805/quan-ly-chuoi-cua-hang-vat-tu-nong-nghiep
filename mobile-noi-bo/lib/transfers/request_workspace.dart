import 'dart:async';

import 'package:flutter/material.dart';

import '../auth/auth_controller.dart';
import '../core/numbers.dart';
import 'models.dart';
import 'request_models.dart';
import 'request_submission.dart';

class TransferRequestWorkspace extends StatefulWidget {
  const TransferRequestWorkspace({super.key, required this.controller});
  final AuthController controller;

  @override
  State<TransferRequestWorkspace> createState() =>
      _TransferRequestWorkspaceState();
}

class _Entry {
  _Entry(this.stock)
    : quantity = TextEditingController(
        text: stock.quantity.compareTo(FixedDecimal.parse('1', scale: 3)) < 0
            ? stock.quantity.toString()
            : '1',
      );
  final TransferStock stock;
  final TextEditingController quantity;
}

class _TransferRequestWorkspaceState extends State<TransferRequestWorkspace> {
  TransferSubmission get submission => widget.controller.transfers;
  final List<_Entry> _entries = [];
  final _scroll = ScrollController();
  TransferRequestState? _shownState;
  TransferOptions? _shownOptions;
  String? _source, _target, _validation;
  String? _user, _branch;
  TransferPayload? _review;
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    _user = widget.controller.profile?.userId;
    _branch = widget.controller.branch?.id;
    widget.controller.addListener(_authChanged);
    submission.addListener(_changed);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(submission.open());
    });
  }

  void _clearEntries() {
    for (final entry in _entries) {
      entry.quantity.dispose();
    }
    _entries.clear();
    _review = null;
    _validation = null;
  }

  void _changed() {
    if (!mounted) return;
    if (submission.options != _shownOptions) {
      _shownOptions = submission.options;
      _source = null;
      _target = null;
      _clearEntries();
    }
    final stateChanged = _shownState != submission.state;
    _shownState = submission.state;
    setState(() {});
    if (stateChanged) _scrollTop();
  }

  void _scrollTop() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _scroll.hasClients) _scroll.jumpTo(0);
    });
  }

  void _authChanged() {
    final auth = widget.controller;
    if (!_closing &&
        (auth.stage != AuthStage.ready ||
            auth.busy ||
            auth.profile?.userId != _user ||
            auth.branch?.id != _branch)) {
      _closing = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
      });
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_authChanged);
    submission.removeListener(_changed);
    _clearEntries();
    _scroll.dispose();
    super.dispose();
  }

  void _reviewRequest() {
    try {
      final payload = TransferPayload(
        branchId: _branch!,
        fromId: _source ?? '',
        toId: _target ?? '',
        lines: _entries
            .map(
              (e) => TransferRequestLine(e.stock.lotId, e.quantity.text.trim()),
            )
            .toList(),
      );
      submission.options!.validate(payload, widget.controller.branch!.chainId);
      FocusScope.of(context).unfocus();
      setState(() {
        _review = payload;
        _validation = null;
      });
      _scrollTop();
    } on FormatException catch (_) {
      setState(
        () => _validation =
            'Chọn kho nguồn, kho đích khác nguồn và 1–50 lô không trùng. Số lượng phải lớn hơn 0, không vượt tồn; tối đa 15 số nguyên và 3 số lẻ (dấu chấm).',
      );
    }
  }

  Future<void> _pickLot() async {
    final options = submission.options;
    if (options == null || _source == null || _entries.length >= 50) return;
    final choices = options
        .lotsFor(_source!)
        .where((e) => !_entries.any((entry) => entry.stock.lotId == e.lotId))
        .toList();
    final picked = await showDialog<TransferStock>(
      context: context,
      builder: (context) => _LotPicker(stock: choices),
    );
    if (!mounted ||
        _closing ||
        picked == null ||
        !submission.canCreate ||
        !identical(options, submission.options) ||
        picked.warehouseId != _source) {
      return;
    }
    setState(() => _entries.add(_Entry(picked)));
  }

  Widget _notice(String text, {bool error = false}) => Container(
    margin: const EdgeInsets.only(bottom: 16),
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: error ? const Color(0xFFFFEDE6) : const Color(0xFFE4EDD9),
      borderRadius: BorderRadius.circular(16),
    ),
    child: Semantics(liveRegion: true, child: Text(text)),
  );

  @override
  Widget build(BuildContext context) {
    final flow = submission;
    return Scaffold(
      appBar: AppBar(title: const Text('Yêu cầu điều chuyển')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: ListView(
              controller: _scroll,
              padding: const EdgeInsets.all(20),
              children: [
                Text(
                  widget.controller.branch?.name ?? 'Đang kiểm tra phạm vi',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 16),
                if (flow.busy) const LinearProgressIndicator(),
                if (flow.error != null)
                  _notice(flow.error!.message, error: true),
                if (_validation != null) _notice(_validation!, error: true),
                if (flow.state == TransferRequestState.loading)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('Đang đọc dấu vết điều chuyển…'),
                  ),
                if (flow.state == TransferRequestState.storageBlocked) ...[
                  _notice(
                    'Đã tạm khóa gửi. Cần xác minh dấu vết đã lưu trước khi tạo yêu cầu.',
                  ),
                  OutlinedButton(
                    onPressed: flow.busy ? null : flow.open,
                    child: const Text('Đọc lại bộ nhớ'),
                  ),
                ],
                if (flow.state == TransferRequestState.unknownOutcome) ...[
                  _notice(
                    'Chưa xác định kết quả. Chưa rõ máy chủ đã tạo yêu cầu hay chưa. Không gửi lại. Giữ dấu vết để đối chiếu với quản lý.',
                  ),
                  if (flow.attempt != null)
                    SelectableText('Mã lần gửi: ${flow.attempt!.attemptId}'),
                  const Text(
                    'Không tìm thấy trong lịch sử không chứng minh yêu cầu chưa tồn tại.',
                  ),
                  OutlinedButton(
                    onPressed: flow.busy ? null : flow.open,
                    child: const Text('Đọc lại dấu vết đã lưu'),
                  ),
                ],
                if (flow.state == TransferRequestState.rejected) ...[
                  _notice(
                    'Yêu cầu bị từ chối. Lần gửi này không tạo phiếu; ứng dụng không tự gửi lại.',
                  ),
                  for (final entry
                      in flow.error?.fieldErrors.entries ??
                          <MapEntry<String, List<String>>>[])
                    Text('${entry.key}: ${entry.value.join(' ')}'),
                  OutlinedButton(
                    onPressed: flow.busy ? null : flow.editRejected,
                    child: const Text('Lưu dấu vết và chuẩn bị yêu cầu mới'),
                  ),
                ],
                if (flow.state == TransferRequestState.sending)
                  _notice(
                    'Đang gửi một lần. Không đóng ứng dụng hoặc gửi lại.',
                  ),
                if (flow.state == TransferRequestState.knownId) ..._known(),
                if (flow.state == TransferRequestState.editing) ..._form(),
                if (flow.journal.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  ExpansionTile(
                    title: Text('Dấu vết đã lưu (${flow.journal.length})'),
                    children: [
                      for (final row in flow.journal)
                        ListTile(
                          title: Text(
                            (row['attempt'] as TransferJson)['transfer_id'] ==
                                    null
                                ? 'Lần gửi bị từ chối'
                                : 'Phiếu #${(row['attempt'] as TransferJson)['transfer_id']}',
                          ),
                          subtitle: Text(row['archived_at'] as String),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _known() {
    final flow = submission, detail = submission.detail;
    return [
      _notice(
        'Đã lưu mã phiếu ${flow.attempt?.transferId}. Có thể tải lại chi tiết, không tạo lại yêu cầu.',
      ),
      if (flow.attempt?.payload.branchId != _branch)
        _notice(
          'Dấu vết thuộc chi nhánh khác. Chuyển về chi nhánh nguồn để đối chiếu; không xóa dấu vết.',
        ),
      if (detail != null) ...[
        Text(
          detail.transfer.number,
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 12),
        Text(detail.transfer.statusLabel),
        Text('Kho nguồn: ${detail.transfer.fromWarehouseName}'),
        Text('Kho đích: ${detail.transfer.toWarehouseName}'),
        const SizedBox(height: 12),
        for (final item in detail.items)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(item.productName),
                  Text('Lô ${item.lotNumber}'),
                  const SizedBox(height: 8),
                  Text(
                    'Yêu cầu: ${item.requested.vietnamese} ${item.unitName}',
                  ),
                ],
              ),
            ),
          ),
        const Text(
          'Tạo yêu cầu chưa phải duyệt hay xuất hàng. Các bước xử lý kho không có trên màn này.',
        ),
        const SizedBox(height: 16),
        FilledButton(
          key: const Key('complete-transfer'),
          onPressed: flow.canComplete ? flow.complete : null,
          child: const Text('Lưu nhật ký và hoàn tất'),
        ),
      ],
      OutlinedButton(
        onPressed: flow.busy ? null : flow.reloadDetail,
        child: const Text('Tải lại đúng phiếu đã lưu'),
      ),
    ];
  }

  List<Widget> _form() {
    final flow = submission, options = submission.options;
    if (options == null) {
      return [
        const Text('Chưa tải được danh sách kho và lô.'),
        OutlinedButton(
          onPressed: flow.busy ? null : flow.open,
          child: const Text('Tải lại danh sách'),
        ),
      ];
    }
    final sources = options.sourcesFor(
      _branch!,
      widget.controller.branch!.chainId,
    );
    if (sources.isEmpty) {
      return [
        _notice(
          'Không có kho nguồn được phép lập yêu cầu tại chi nhánh này. Quyền do API xác định từ phân công đang hiệu lực.',
        ),
        OutlinedButton(
          onPressed: flow.busy ? null : flow.open,
          child: const Text('Cập nhật phạm vi kho'),
        ),
      ];
    }
    final source = sources.where((e) => e.id == _source).firstOrNull;
    final targets = source == null
        ? <TransferWarehouse>[]
        : options.destinationsFor(source);
    final target = targets.where((e) => e.id == _target).firstOrNull;
    if (_review != null) {
      return [
        Text(
          'Xem lại trước khi gửi',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 16),
        Text('Nguồn: ${source!.label}'),
        Text('Đích: ${target!.label}'),
        const SizedBox(height: 16),
        for (final line in _review!.lines)
          Card(
            child: ListTile(
              title: Text(
                _entries
                    .firstWhere((e) => e.stock.lotId == line.lotId)
                    .stock
                    .label,
              ),
              subtitle: Text(
                'Yêu cầu: ${line.quantity.vietnamese} ${_entries.firstWhere((e) => e.stock.lotId == line.lotId).stock.unitName}',
              ),
            ),
          ),
        _notice(
          'Gửi sẽ tạo một yêu cầu chờ duyệt, chưa giữ hay trừ tồn. Nếu mất phản hồi, không gửi lại.',
        ),
        FilledButton(
          key: const Key('submit-transfer'),
          onPressed: flow.canCreate ? () => flow.submit(_review!) : null,
          child: const Text('Gửi yêu cầu một lần'),
        ),
        TextButton(
          onPressed: flow.busy ? null : () => setState(() => _review = null),
          child: const Text('Quay lại chỉnh'),
        ),
      ];
    }
    return [
      _notice(
        'Danh sách là snapshot tại lúc tải, chưa giữ hàng. Máy chủ kiểm lại tồn và quyền khi gửi yêu cầu.',
      ),
      DropdownButtonFormField<String>(
        key: ValueKey('transfer-source-${_source ?? ''}'),
        initialValue: _source,
        isExpanded: true,
        decoration: const InputDecoration(labelText: 'Kho nguồn'),
        items: [
          for (final row in sources)
            DropdownMenuItem(
              value: row.id,
              child: Text(row.label, overflow: TextOverflow.ellipsis),
            ),
        ],
        onChanged: !flow.canCreate
            ? null
            : (value) => setState(() {
                _source = value;
                _target = null;
                _clearEntries();
              }),
      ),
      const SizedBox(height: 16),
      DropdownButtonFormField<String>(
        key: ValueKey('transfer-target-${_source ?? ''}-${_target ?? ''}'),
        initialValue: _target,
        isExpanded: true,
        decoration: const InputDecoration(labelText: 'Kho đích cùng chuỗi'),
        items: [
          for (final row in targets)
            DropdownMenuItem(
              value: row.id,
              child: Text(row.label, overflow: TextOverflow.ellipsis),
            ),
        ],
        onChanged: !flow.canCreate || targets.isEmpty
            ? null
            : (value) => setState(() {
                _target = value;
                _review = null;
              }),
      ),
      if (source != null && targets.isEmpty)
        const Text('Chưa có kho đích khác nguồn trong cùng chuỗi.'),
      const SizedBox(height: 20),
      for (final entry in _entries)
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  entry.stock.label,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                Text(
                  'Tồn snapshot: ${entry.stock.quantity.vietnamese} ${entry.stock.unitName}',
                ),
                const SizedBox(height: 12),
                TextField(
                  key: ValueKey('transfer-qty-${entry.stock.lotId}'),
                  controller: entry.quantity,
                  enabled: flow.canCreate,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Số lượng yêu cầu',
                    helperText: 'Tối đa 3 số lẻ, dùng dấu chấm',
                    helperMaxLines: 2,
                  ),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: !flow.canCreate
                        ? null
                        : () => setState(() {
                            _entries.remove(entry);
                            entry.quantity.dispose();
                            _review = null;
                          }),
                    icon: const Icon(Icons.remove_circle_outline),
                    label: const Text('Bỏ lô'),
                  ),
                ),
              ],
            ),
          ),
        ),
      OutlinedButton.icon(
        key: const Key('add-transfer-lot'),
        onPressed: !flow.canCreate || source == null || _entries.length >= 50
            ? null
            : _pickLot,
        icon: const Icon(Icons.add),
        label: Text('Chọn lô (${_entries.length}/50)'),
      ),
      const SizedBox(height: 12),
      FilledButton(
        key: const Key('review-transfer'),
        onPressed: flow.canCreate ? _reviewRequest : null,
        child: const Text('Xem lại yêu cầu'),
      ),
      TextButton(
        onPressed: flow.busy ? null : flow.open,
        child: const Text('Tải lại kho/lô và làm mới form'),
      ),
    ];
  }
}

class _LotPicker extends StatefulWidget {
  const _LotPicker({required this.stock});
  final List<TransferStock> stock;
  @override
  State<_LotPicker> createState() => _LotPickerState();
}

class _LotPickerState extends State<_LotPicker> {
  String query = '';
  @override
  Widget build(BuildContext context) {
    final rows = widget.stock
        .where((e) => e.label.toLowerCase().contains(query.toLowerCase()))
        .toList();
    return Dialog(
      child: SizedBox(
        width: 520,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                decoration: const InputDecoration(
                  labelText: 'Tìm vật tư hoặc lô',
                ),
                onChanged: (value) => setState(() => query = value),
              ),
              const SizedBox(height: 12),
              Flexible(
                child: rows.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.all(16),
                        child: Text('Không còn lô phù hợp để thêm.'),
                      )
                    : ListView(
                        shrinkWrap: true,
                        children: [
                          for (final row in rows)
                            ListTile(
                              key: ValueKey('pick-transfer-${row.lotId}'),
                              title: Text(row.label),
                              subtitle: Text(
                                '${row.quantity.vietnamese} ${row.unitName} khả dụng',
                              ),
                              onTap: () => Navigator.of(context).pop(row),
                            ),
                        ],
                      ),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Đóng'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
