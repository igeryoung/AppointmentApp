import '../database/connection.dart';
import 'account_auth_service.dart';

class BookAccessService {
  final DatabaseConnection db;
  late final AccountAuthService _accountAuth;

  BookAccessService(this.db) {
    _accountAuth = AccountAuthService(db);
  }

  Future<bool> verifyBookAccess(
    String deviceId,
    String bookUuid, {
    bool requireWrite = false,
  }) async {
    return _accountAuth.verifyBookAccess(
      deviceId,
      bookUuid,
      requireWrite: requireWrite,
    );
  }

  Future<void> grantBookAccess({
    required String bookUuid,
    required String deviceId,
  }) async {
    await _accountAuth.grantBookAccessToDevice(
      bookUuid: bookUuid,
      deviceId: deviceId,
    );
  }
}
