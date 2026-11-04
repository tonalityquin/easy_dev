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
  Future<UserModel?> getUserByIdFromServer(String userId) =>
      _readService.getUserByIdFromServer(userId);

  @override
  Future<UserModel?> getUserByAccountCode(String accountCode) =>
      _readService.getUserByAccountCode(accountCode);

  @override
  Future<List<UserModel>> searchUsersByCodeNumber(String codeNumber) =>
      _readService.searchUsersByCodeNumber(codeNumber);

  @override
  Future<List<UserModel>> searchUsersByName(String name) =>
      _readService.searchUsersByName(name);

  @override
  Future<UserModel?> getUserByHandle(String handle) => _readService.getUserByHandle(handle);

  @override
  Future<TabletModel?> getTabletByCodeNumber(String codeNumber) => _readService.getTabletByCodeNumber(codeNumber);

  @override
  Future<List<TabletModel>> searchTabletsByCodeNumber(String codeNumber) =>
      _readService.searchTabletsByCodeNumber(codeNumber);

  @override
  Future<TabletModel?> getTabletByCodeNumberAndAreaName(String codeNumber, String areaName) =>
      _readService.getTabletByCodeNumberAndAreaName(codeNumber, areaName);

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
  Future<void> addUserCard(UserModel user) async {
    _statusService.invalidateConfirmedFields();
    try {
      await _writeService.addUserCard(user);
    } finally {
      _statusService.invalidateConfirmedFields();
    }
  }

  @override
  Future<void> addTabletCard(TabletModel tablet) async {
    _statusService.invalidateConfirmedFields();
    try {
      await _writeService.addTabletCard(tablet);
    } finally {
      _statusService.invalidateConfirmedFields();
    }
  }

  @override
  Future<void> updateUser(UserModel user, {String? previousId}) async {
    _statusService.invalidateConfirmedFields();
    try {
      await _writeService.updateUser(user, previousId: previousId);
    } finally {
      _statusService.invalidateConfirmedFields();
    }
  }

  @override
  Future<void> updateTablet(TabletModel tablet, {String? previousId}) async {
    _statusService.invalidateConfirmedFields();
    try {
      await _writeService.updateTablet(tablet, previousId: previousId);
    } finally {
      _statusService.invalidateConfirmedFields();
    }
  }

  @override
  Future<void> deleteUsers(List<String> ids) async {
    _statusService.invalidateConfirmedFields();
    try {
      await _writeService.deleteUsers(ids);
    } finally {
      _statusService.invalidateConfirmedFields();
    }
  }

  @override
  Future<void> deleteTablets(List<String> ids) async {
    _statusService.invalidateConfirmedFields();
    try {
      await _writeService.deleteTablets(ids);
    } finally {
      _statusService.invalidateConfirmedFields();
    }
  }

  @override
  Future<void> setUserActiveStatus(String userId, {required bool isActive}) =>
      _writeService.setUserActiveStatus(userId, isActive: isActive);

  @override
  Future<void> updateLogOutUserStatus(String codeNumber, String area, {bool? isWorking, bool? isSaved}) =>
      _statusService.updateLogOutUserStatus(codeNumber, area, isWorking: isWorking, isSaved: isSaved);

  @override
  Future<void> updateWorkingUserStatus(String codeNumber, String area, {bool? isWorking, bool? isSaved}) =>
      _statusService.updateWorkingUserStatus(codeNumber, area, isWorking: isWorking, isSaved: isSaved);

  @override
  Future<bool> updateLoginSession({
    required String userId,
    required bool isSaved,
    String? currentArea,
    String? selectedArea,
  }) =>
      _statusService.updateLoginSession(
        userId: userId,
        isSaved: isSaved,
        currentArea: currentArea,
        selectedArea: selectedArea,
      );

  @override
  Future<void> updateLoadCurrentArea(String codeNumber, String area, String currentArea) =>
      _statusService.updateLoadCurrentArea(codeNumber, area, currentArea);

  @override
  Future<bool> areaPickerCurrentArea(String codeNumber, String area, String currentArea) =>
      _statusService.areaPickerCurrentArea(codeNumber, area, currentArea);

  @override
  Future<void> updateLogOutTabletStatus(String tabletId, {bool? isWorking, bool? isSaved}) =>
      _statusService.updateLogOutTabletStatus(tabletId, isWorking: isWorking, isSaved: isSaved);

  @override
  Future<void> updateWorkingTabletStatus(String tabletId, {bool? isWorking, bool? isSaved}) =>
      _statusService.updateWorkingTabletStatus(tabletId, isWorking: isWorking, isSaved: isSaved);

  @override
  Future<void> updateLoadCurrentAreaTablet(String tabletId, String currentArea) =>
      _statusService.updateLoadCurrentAreaTablet(tabletId, currentArea);

  @override
  Future<bool> areaPickerCurrentAreaTablet(String tabletId, String currentArea) =>
      _statusService.areaPickerCurrentAreaTablet(tabletId, currentArea);
}
