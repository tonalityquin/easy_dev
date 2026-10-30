import '../models/tablet/tablet_model.dart';
import '../models/user/user_model.dart';

abstract class UserRepository {
  Future<UserModel?> getUserByAccountCode(String accountCode);
  Future<List<UserModel>> searchUsersByCodeNumber(String codeNumber);
  Future<List<UserModel>> searchUsersByName(String name);
  Future<UserModel?> getUserById(String userId);
  Future<UserModel?> getUserByIdFromServer(String userId);
  Future<UserModel?> getUserByHandle(String handle);
  Future<TabletModel?> getTabletByCodeNumber(String codeNumber);
  Future<List<TabletModel>> searchTabletsByCodeNumber(String codeNumber);
  Future<TabletModel?> getTabletByCodeNumberAndAreaName(String codeNumber, String areaName);

  Future<void> updateLoadCurrentArea(String codeNumber, String area, String currentArea);
  Future<void> areaPickerCurrentArea(String codeNumber, String area, String currentArea);
  Future<void> updateLogOutUserStatus(String userId, {bool? isWorking, bool? isSaved});
  Future<void> updateWorkingUserStatus(String userId, {bool? isWorking, bool? isSaved});
  Future<void> updateLoginSession({
    required String userId,
    required bool isSaved,
    String? currentArea,
    String? selectedArea,
  });

  Future<void> setUserActiveStatus(String userId, {required bool isActive});

  Future<void> updateLoadCurrentAreaTablet(String tabletId, String currentArea);
  Future<void> areaPickerCurrentAreaTablet(String tabletId, String currentArea);
  Future<void> updateLogOutTabletStatus(String tabletId, {bool? isWorking, bool? isSaved});
  Future<void> updateWorkingTabletStatus(String tabletId, {bool? isWorking, bool? isSaved});

  Future<void> addUserCard(UserModel user);
  Future<void> addTabletCard(TabletModel tablet);
  Future<void> updateUser(UserModel user, {String? previousId});
  Future<void> updateTablet(TabletModel tablet, {String? previousId});
  Future<void> deleteUsers(List<String> ids, {void Function(String)? onDiagnostic});
  Future<void> deleteTablets(List<String> ids);

  Future<List<UserModel>> getUsersByAreaOnceWithCache(String selectedArea, {String? companyId});
  Future<List<TabletModel>> getTabletsByAreaOnceWithCache(String selectedArea, {String? companyId});

  Future<List<UserModel>> refreshUsersBySelectedArea(String selectedArea, {required String companyId});
  Future<List<UserModel>> refreshUsersByDivisionAreaFromShow(String division, String area);
  Future<List<TabletModel>> refreshTabletsBySelectedArea(String selectedArea, {String? companyId});

  Future<void> updateUsersCache(String selectedArea, List<UserModel> users, {String? companyId});
  Future<void> updateTabletsCache(String selectedArea, List<TabletModel> tablets, {String? companyId});

  Future<void> clearUsersCache(String selectedArea, {String? companyId});
  Future<void> clearTabletsCache(String selectedArea, {String? companyId});

  Future<String?> getEnglishNameByArea(String area, String division);
}

