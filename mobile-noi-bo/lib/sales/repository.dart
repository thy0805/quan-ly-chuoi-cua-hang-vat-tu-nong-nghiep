import '../auth/api_client.dart';
import '../auth/auth_controller.dart';
import '../core/numbers.dart';
import 'models.dart';

class SalesRepository {
  SalesRepository(this.auth);
  final AuthController auth;

  Future<T> _read<T>(String path, T Function(Json) parse) async {
    final json = await auth.readSales(path);
    try {
      return parse(json);
    } on FormatException {
      throw const ApiFailure(
        'Dữ liệu đơn hàng không đúng định dạng. Không sử dụng số tiền chưa xác minh.',
        kind: ApiFailureKind.invalidResponse,
      );
    } on TypeError {
      throw const ApiFailure(
        'Dữ liệu đơn hàng không đúng định dạng. Không sử dụng số tiền chưa xác minh.',
        kind: ApiFailureKind.invalidResponse,
      );
    }
  }

  Future<SalesOptions> options() async {
    final branch = auth.branch;
    if (branch == null) {
      throw const ApiFailure('Chưa chọn chi nhánh.', status: 403);
    }
    final result = await _read(
      '/api/sales-orders/options',
      SalesOptions.fromJson,
    );
    return result.forBranch(branch.id, branch.chainId);
  }

  Future<List<SalesOrderSummary>> history() async {
    final branchId = auth.branch?.id;
    if (branchId == null) {
      throw const ApiFailure('Chưa chọn chi nhánh.', status: 403);
    }
    final result = await _read('/api/sales-orders', SalesOrderSummary.list);
    return List.unmodifiable(result.where((item) => item.branchId == branchId));
  }

  Future<SalesOrderDetail> detail(String id) async {
    jsonId(id);
    final branchId = auth.branch?.id;
    final result = await _read(
      '/api/sales-orders/$id',
      SalesOrderDetail.fromJson,
    );
    if (result.order.id != id || result.order.branchId != branchId) {
      throw const ApiFailure(
        'Không tìm thấy đơn hàng trong chi nhánh đang chọn.',
        status: 404,
      );
    }
    return result;
  }
}
