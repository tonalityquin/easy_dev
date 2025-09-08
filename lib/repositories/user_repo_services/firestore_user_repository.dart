import '../../models/tablet_model.dart';
import '../../models/user_model.dart';
import 'user_read_service.dart';
import 'user_repository.dart';
import 'user_status_service.dart';
import 'user_write_service.dart';

class FirestoreUserRepository implements UserRepository {
  final UserReadService _readService = UserReadService();
  final UserWriteService _writeService = UserWriteService();
  final UserStatusService _statusService = UserStatusService();

  // ===== 단건 조회 =====
  @override
  Future<UserModel?> getUserById(String userId) {
    return _readService.getUserById(userId);
  }

  @override
  Future<UserModel?> getUserByPhone(String phone) {
    return _readService.getUserByPhone(phone);
  }

  @override
  Future<UserModel?> getUserByHandle(String handle) {
    return _readService.getUserByHandle(handle);
  }

  @override
  Future<TabletModel?> getTabletByHandle(String handle) {
    return _readService.getTabletByHandle(handle);
  }

  @override
  Future<TabletModel?> getTabletByHandleAndAreaName(String handle, String areaName) {
    return _readService.getTabletByHandleAndAreaName(handle, areaName);
  }

  // ===== 리스트 조회(캐시/네트워크) =====
  @override
  Future<List<UserModel>> getUsersByAreaOnceWithCache(String selectedArea) {
    return _readService.getUsersByAreaOnceWithCache(selectedArea);
  }

  @override
  Future<List<UserModel>> refreshUsersBySelectedArea(String selectedArea) {
    return _readService.refreshUsersBySelectedArea(selectedArea);
  }

  @override
  Future<List<UserModel>> refreshTabletsBySelectedArea(String selectedArea) {
    return _readService.refreshTabletsBySelectedArea(selectedArea);
  }

  // ===== 부가 조회 =====
  @override
  Future<String?> getEnglishNameByArea(String area, String division) {
    return _readService.getEnglishNameByArea(area, division);
  }

  // ===== 생성/수정/삭제 =====
  @override
  Future<void> addUserCard(UserModel user) {
    return _writeService.addUserCard(user);
  }

  @override
  Future<void> addTabletCard(TabletModel tablet) {
    return _writeService.addTabletCard(tablet);
  }

  @override
  Future<void> updateUser(UserModel user) {
    return _writeService.updateUser(user);
  }

  @override
  Future<void> updateTablet(TabletModel tablet) {
    return _writeService.updateTablet(tablet);
  }

  @override
  Future<void> deleteUsers(List<String> ids) {
    return _writeService.deleteUsers(ids);
  }

  @override
  Future<void> deleteTablets(List<String> ids) {
    return _writeService.deleteTablets(ids);
  }

  // ===== 상태 업데이트: user_accounts =====
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

  // ===== 상태 업데이트: tablet_accounts (handle 기반) =====
  @override
  Future<void> updateLogOutTabletStatus(
      String handle,
      String area, {
        bool? isWorking,
        bool? isSaved,
      }) {
    return _statusService.updateLogOutTabletStatus(
      handle,
      area,
      isWorking: isWorking,
      isSaved: isSaved,
    );
  }

  @override
  Future<void> updateWorkingTabletStatus(
      String handle,
      String area, {
        bool? isWorking,
        bool? isSaved,
      }) {
    return _statusService.updateWorkingTabletStatus(
      handle,
      area,
      isWorking: isWorking,
      isSaved: isSaved,
    );
  }

  @override
  Future<void> updateLoadCurrentAreaTablet(
      String handle,
      String area,
      String currentArea,
      ) {
    return _statusService.updateLoadCurrentAreaTablet(handle, area, currentArea);
  }

  @override
  Future<void> areaPickerCurrentAreaTablet(
      String handle,
      String area,
      String currentArea,
      ) {
    return _statusService.areaPickerCurrentAreaTablet(handle, area, currentArea);
  }
}
