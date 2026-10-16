import '../auth/api_client.dart';
import '../auth/auth_controller.dart';
import '../core/numbers.dart';
import 'models.dart';

class TransferRepository {
  TransferRepository(this.auth);
  final AuthController auth;

  Future<T> _read<T>(String path, T Function(TransferJson) parse) async {
    final data = await auth.readTransfers(path);
    try {
      return parse(data);
    } on FormatException {
      throw const ApiFailure(
        'Dữ liệu phiếu điều chuyển không đúng định dạng. Hãy tải lại.',
        kind: ApiFailureKind.invalidResponse,
      );
    } on TypeError {
      throw const ApiFailure(
        'Dữ liệu phiếu điều chuyển không đúng định dạng. Hãy tải lại.',
        kind: ApiFailureKind.invalidResponse,
      );
    }
  }

  Future<TransferPage> page(int page) async {
    if (page < 1) throw ArgumentError.value(page);
    final branch = auth.branch?.id;
    if (branch == null) {
      throw const ApiFailure('Chưa chọn chi nhánh.', status: 403);
    }
    final result = await _read(
      '/api/stock-transfers?page=$page&per_page=50',
      TransferPage.fromJson,
    );
    if (result.current != page) {
      throw const ApiFailure(
        'Phản hồi không khớp trang được yêu cầu.',
        kind: ApiFailureKind.invalidResponse,
      );
    }
    return result.forBranch(branch);
  }

  Future<TransferDetail> detail(String id) async {
    jsonId(id);
    final branch = auth.branch?.id;
    final detail = await _read(
      '/api/stock-transfers/$id',
      TransferDetail.fromJson,
    );
    if (detail.transfer.id != id ||
        branch == null ||
        !detail.transfer.belongsTo(branch)) {
      throw const ApiFailure(
        'Không tìm thấy phiếu điều chuyển trong chi nhánh đang chọn.',
        status: 404,
      );
    }
    return detail;
  }
}
