import 'dart:convert';

import '../core/numbers.dart';
import 'models.dart';

class TransferWarehouse {
  TransferWarehouse.fromJson(TransferJson json)
    : id = jsonId(json['id']),
      branchId = jsonId(json['branch_id']),
      chainId = jsonId(json['chain_id']),
      name = json['name'] as String,
      branchName = json['branch_name'] as String;

  final String id, branchId, chainId, name, branchName;
  String get label => '$branchName · $name';
}

class TransferStock {
  TransferStock.fromJson(TransferJson json)
    : warehouseId = jsonId(json['warehouse_id']),
      lotId = jsonId(json['lot_id']),
      quantity = FixedDecimal.parse(
        json['quantity'] as String,
        scale: 3,
        wholeDigits: 15,
      ),
      lotNo = json['lot_no'] as String,
      productCode = json['product_code'] as String,
      productName = json['product_name'] as String,
      unitName = json['unit_name'] as String {
    if (quantity.atoms <= BigInt.zero) throw const FormatException('Sai tồn.');
  }

  final String warehouseId, lotId, lotNo, productCode, productName, unitName;
  final FixedDecimal quantity;
  String get label => '$productCode · $productName · Lô $lotNo';
}

class TransferOptions {
  TransferOptions.fromJson(TransferJson json)
    : sources = List.unmodifiable(
        (json['sources'] as List).map(
          (e) => TransferWarehouse.fromJson(e as TransferJson),
        ),
      ),
      destinations = List.unmodifiable(
        (json['destinations'] as List).map(
          (e) => TransferWarehouse.fromJson(e as TransferJson),
        ),
      ),
      stock = List.unmodifiable(
        (json['lots'] as List).map(
          (e) => TransferStock.fromJson(e as TransferJson),
        ),
      ) {
    if (sources.map((e) => e.id).toSet().length != sources.length ||
        destinations.map((e) => e.id).toSet().length != destinations.length ||
        stock.map((e) => '${e.warehouseId}|${e.lotId}').toSet().length !=
            stock.length) {
      throw const FormatException('Options trùng khóa.');
    }
  }

  final List<TransferWarehouse> sources, destinations;
  final List<TransferStock> stock;

  List<TransferWarehouse> sourcesFor(String branch, String chain) =>
      sources.where((e) => e.branchId == branch && e.chainId == chain).toList();
  List<TransferWarehouse> destinationsFor(TransferWarehouse source) =>
      destinations
          .where((e) => e.chainId == source.chainId && e.id != source.id)
          .toList();
  List<TransferStock> lotsFor(String warehouse) =>
      stock.where((e) => e.warehouseId == warehouse).toList();

  void validate(TransferPayload payload, String chain) {
    final source = sourcesFor(
      payload.branchId,
      chain,
    ).where((e) => e.id == payload.fromId).firstOrNull;
    if (source == null ||
        !destinationsFor(source).any((e) => e.id == payload.toId)) {
      throw const FormatException('Kho không thuộc phạm vi yêu cầu hiện tại.');
    }
    for (final line in payload.lines) {
      final lot = lotsFor(
        source.id,
      ).where((e) => e.lotId == line.lotId).firstOrNull;
      if (lot == null || line.quantity.compareTo(lot.quantity) > 0) {
        throw const FormatException('Số lượng vượt tồn khả dụng của lô.');
      }
    }
  }
}

class TransferRequestLine {
  TransferRequestLine(String lot, String quantity)
    : lotId = jsonId(lot),
      quantity = FixedDecimal.parse(quantity, scale: 3, wholeDigits: 15) {
    if (this.quantity.atoms <= BigInt.zero) {
      throw const FormatException('Số lượng phải lớn hơn 0.');
    }
  }

  final String lotId;
  final FixedDecimal quantity;
  TransferJson toJson() => {
    'lot_id': lotId,
    'requested_quantity': quantity.toString(),
  };
}

class TransferPayload {
  TransferPayload({
    required String branchId,
    required String fromId,
    required String toId,
    required List<TransferRequestLine> lines,
  }) : branchId = jsonId(branchId),
       fromId = jsonId(fromId),
       toId = jsonId(toId),
       lines = List.unmodifiable(lines) {
    if (fromId == toId ||
        lines.isEmpty ||
        lines.length > 50 ||
        lines.map((e) => e.lotId).toSet().length != lines.length) {
      throw const FormatException('Chọn hai kho khác nhau và 1–50 lô riêng.');
    }
  }

  factory TransferPayload.fromJson(TransferJson json, String branch) {
    if (json.keys.toSet().difference({
      'from_warehouse_id',
      'to_warehouse_id',
      'items',
    }).isNotEmpty) {
      throw const FormatException('Sai payload.');
    }
    return TransferPayload(
      branchId: branch,
      fromId: jsonId(json['from_warehouse_id']),
      toId: jsonId(json['to_warehouse_id']),
      lines: (json['items'] as List).map((e) {
        final row = e as TransferJson;
        if (row.length != 2) throw const FormatException('Sai dòng.');
        return TransferRequestLine(
          jsonId(row['lot_id']),
          row['requested_quantity'] as String,
        );
      }).toList(),
    );
  }

  final String branchId, fromId, toId;
  final List<TransferRequestLine> lines;
  TransferJson toJson() => {
    'from_warehouse_id': fromId,
    'to_warehouse_id': toId,
    'items': lines.map((e) => e.toJson()).toList(),
  };
  String get fingerprint => jsonEncode(toJson());

  bool matches(TransferDetail detail, String creator, TransferJson raw) =>
      (raw['data'] as TransferJson)['requested_by'] == creator &&
      detail.transfer.fromBranchId == branchId &&
      detail.transfer.fromWarehouseId == fromId &&
      detail.transfer.toWarehouseId == toId &&
      detail.items.length == lines.length &&
      lines.every(
        (line) => detail.items.any(
          (e) =>
              e.lotId == line.lotId &&
              e.requested.compareTo(line.quantity) == 0,
        ),
      );
}
