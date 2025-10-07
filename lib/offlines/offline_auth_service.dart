import 'offline_auth_repository.dart';
import 'offline_session_model.dart';

class OfflineAuthService {
  OfflineAuthService._(this._repo);
  static final OfflineAuthService instance =
  OfflineAuthService._(OfflineAuthRepository());

  final OfflineAuthRepository _repo;

  Future<void> signInOffline({
    required String userId,
    required String name,
    required String position,
    required String phone,
    required String area,
  }) async {
    final session = OfflineSession(
      userId: userId,
      name: name,
      position: position,
      phone: phone,
      area: area,
      createdAt: DateTime.now(),
    );
    await _repo.saveSession(session);
  }

  Future<bool> hasSession() async {
    final s = await _repo.getSession();
    return s != null;
  }

  Future<OfflineSession?> currentSession() => _repo.getSession();

  Future<void> signOutOffline() => _repo.clearSession();
}
