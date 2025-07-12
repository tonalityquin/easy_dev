import '../../models/user_model.dart';
import 'user_read_service.dart';
import 'user_repository.dart';
import 'user_status_service.dart';
import 'user_write_service.dart';

class FirestoreUserRepository implements UserRepository {
  final UserReadService _readService = UserReadService();
  final UserWriteService _writeService = UserWriteService();
  final UserStatusService _statusService = UserStatusService();

  @override
  Future<UserModel?> getUserById(String userId) {
    return _readService.getUserById(userId);
  }

  @override
  Future<UserModel?> getUserByPhone(String phone) {
    return _readService.getUserByPhone(phone);
  }

  @override
  Future<List<UserModel>> getUsersByAreaOnceWithCache(String selectedArea) {
    return _readService.getUsersByAreaOnceWithCache(selectedArea);
  }

  @override
  Future<List<UserModel>> refreshUsersBySelectedArea(String selectedArea) {
    return _readService.refreshUsersBySelectedArea(selectedArea);
  }

  @override
  Future<String?> getEnglishNameByArea(String area, String division) {
    return _readService.getEnglishNameByArea(area, division);
  }

  @override
  Future<void> addUserCard(UserModel user) {
    return _writeService.addUserCard(user);
  }

  @override
  Future<void> updateUser(UserModel user) {
    return _writeService.updateUser(user);
  }

  @override
  Future<void> deleteUsers(List<String> ids) {
    return _writeService.deleteUsers(ids);
  }

  @override
  Future<void> updateLoadUserStatus(
    String phone,
    String area, {
    bool? isWorking,
    bool? isSaved,
  }) {
    return _statusService.updateLoadUserStatus(
      phone,
      area,
      isWorking: isWorking,
      isSaved: isSaved,
    );
  }

  @override
  Future<void> updateLogOutUserStatus(
    String phone,
    String area, {
    bool? isWorking,
    bool? isSaved,
  }) {
    return _statusService.updateLogOutUserStatus(
      phone,
      area,
      isWorking: isWorking,
      isSaved: isSaved,
    );
  }

  @override
  Future<void> updateWorkingUserStatus(
    String phone,
    String area, {
    bool? isWorking,
    bool? isSaved,
  }) {
    return _statusService.updateWorkingUserStatus(
      phone,
      area,
      isWorking: isWorking,
      isSaved: isSaved,
    );
  }

  @override
  Future<void> updateLoadCurrentArea(
    String phone,
    String area,
    String currentArea,
  ) {
    return _statusService.updateLoadCurrentArea(phone, area, currentArea);
  }

  @override
  Future<void> areaPickerCurrentArea(
    String phone,
    String area,
    String currentArea,
  ) {
    return _statusService.areaPickerCurrentArea(phone, area, currentArea);
  }
}
