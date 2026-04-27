import '../../domain/models/tablet/tablet_model.dart';
import '../../domain/models/user/user_model.dart';
import '../../domain/repositories/user_repository.dart';
import '../services/user_read_service.dart';
import '../services/user_status_service.dart';
import '../services/user_write_service.dart';
class FirestoreUserRepository implements UserRepository {
  final UserReadService _readService = UserReadService();
  final UserWriteService _writeService = UserWriteService();
  final UserStatusService _statusService = UserStatusService();

  @override
  Future<UserModel?> getUserById(String userId) => _readService.getUserById(userId);

  @override
  Future<UserModel?> getUserByPhone(String phone) => _readService.getUserByPhone(phone);

  @override
  Future<List<UserModel>> searchUsersByPhone(String phone) => _readService.searchUsersByPhone(phone);

  @override
  Future<UserModel?> getUserByHandle(String handle) => _readService.getUserByHandle(handle);

  @override
  Future<TabletModel?> getTabletByHandle(String handle) => _readService.getTabletByHandle(handle);

  @override
  Future<TabletModel?> getTabletByHandleAndAreaName(String handle, String areaName) =>
      _readService.getTabletByHandleAndAreaName(handle, areaName);

  @override
  Future<List<UserModel>> getUsersByAreaOnceWithCache(String selectedArea) =>
      _readService.getUsersByAreaOnceWithCache(selectedArea);

  @override
  Future<List<TabletModel>> getTabletsByAreaOnceWithCache(String selectedArea) =>
      _readService.getTabletsByAreaOnceWithCache(selectedArea);

  @override
  Future<List<UserModel>> refreshUsersBySelectedArea(String selectedArea) =>
      _readService.refreshUsersBySelectedArea(selectedArea);

  @override
  Future<List<UserModel>> refreshUsersByDivisionAreaFromShow(String division, String area) =>
      _readService.refreshUsersByDivisionAreaFromShow(division, area);

  @override
  Future<List<TabletModel>> refreshTabletsBySelectedArea(String selectedArea) =>
      _readService.refreshTabletsBySelectedArea(selectedArea);

  @override
  Future<void> updateUsersCache(String selectedArea, List<UserModel> users) =>
      _readService.updateCacheWithUsers(selectedArea, users);

  @override
  Future<void> updateTabletsCache(String selectedArea, List<TabletModel> tablets) =>
      _readService.updateCacheWithTablets(selectedArea, tablets);

  @override
  Future<void> clearUsersCache(String selectedArea) => _readService.clearUserCache(selectedArea);

  @override
  Future<void> clearTabletsCache(String selectedArea) => _readService.clearTabletCache(selectedArea);

  @override
  Future<String?> getEnglishNameByArea(String area, String division) =>
      _readService.getEnglishNameByArea(area, division);

  @override
  Future<void> addUserCard(UserModel user) => _writeService.addUserCard(user);

  @override
  Future<void> addTabletCard(TabletModel tablet) => _writeService.addTabletCard(tablet);

  @override
  Future<void> updateUser(UserModel user) => _writeService.updateUser(user);

  @override
  Future<void> updateTablet(TabletModel tablet) => _writeService.updateTablet(tablet);

  @override
  Future<void> deleteUsers(List<String> ids) => _writeService.deleteUsers(ids);

  @override
  Future<void> deleteTablets(List<String> ids) => _writeService.deleteTablets(ids);

  @override
  Future<void> setUserActiveStatus(String userId, {required bool isActive}) =>
      _writeService.setUserActiveStatus(userId, isActive: isActive);

  @override
  Future<void> updateLogOutUserStatus(String phone, String area, {bool? isWorking, bool? isSaved}) =>
      _statusService.updateLogOutUserStatus(phone, area, isWorking: isWorking, isSaved: isSaved);

  @override
  Future<void> updateWorkingUserStatus(String phone, String area, {bool? isWorking, bool? isSaved}) =>
      _statusService.updateWorkingUserStatus(phone, area, isWorking: isWorking, isSaved: isSaved);

  @override
  Future<void> updateLoadCurrentArea(String phone, String area, String currentArea) =>
      _statusService.updateLoadCurrentArea(phone, area, currentArea);

  @override
  Future<void> areaPickerCurrentArea(String phone, String area, String currentArea) =>
      _statusService.areaPickerCurrentArea(phone, area, currentArea);

  @override
  Future<void> updateLogOutTabletStatus(String handle, String area, {bool? isWorking, bool? isSaved}) =>
      _statusService.updateLogOutTabletStatus(handle, area, isWorking: isWorking, isSaved: isSaved);

  @override
  Future<void> updateWorkingTabletStatus(String handle, String area, {bool? isWorking, bool? isSaved}) =>
      _statusService.updateWorkingTabletStatus(handle, area, isWorking: isWorking, isSaved: isSaved);

  @override
  Future<void> updateLoadCurrentAreaTablet(String handle, String area, String currentArea) =>
      _statusService.updateLoadCurrentAreaTablet(handle, area, currentArea);

  @override
  Future<void> areaPickerCurrentAreaTablet(String handle, String area, String currentArea) =>
      _statusService.areaPickerCurrentAreaTablet(handle, area, currentArea);
}
