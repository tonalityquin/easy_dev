
import '../models/tablet/tablet_model.dart';
import '../models/user/user_model.dart';

abstract class UserRepository {
  Future<UserModel?> getUserByPhone(String phone);
  Future<List<UserModel>> searchUsersByPhone(String phone);
  Future<UserModel?> getUserById(String userId);
  Future<UserModel?> getUserByHandle(String handle);
  Future<TabletModel?> getTabletByHandle(String handle);
  Future<TabletModel?> getTabletByHandleAndAreaName(String handle, String areaName);

  Future<void> updateLoadCurrentArea(String phone, String area, String currentArea);
  Future<void> areaPickerCurrentArea(String phone, String area, String currentArea);
  Future<void> updateLogOutUserStatus(String phone, String area, {bool? isWorking, bool? isSaved});
  Future<void> updateWorkingUserStatus(String phone, String area, {bool? isWorking, bool? isSaved});

  Future<void> setUserActiveStatus(String userId, {required bool isActive});

  Future<void> updateLoadCurrentAreaTablet(String handle, String areaName, String currentArea);
  Future<void> areaPickerCurrentAreaTablet(String handle, String areaName, String currentArea);
  Future<void> updateLogOutTabletStatus(String handle, String areaName, {bool? isWorking, bool? isSaved});
  Future<void> updateWorkingTabletStatus(String handle, String areaName, {bool? isWorking, bool? isSaved});

  Future<void> addUserCard(UserModel user);
  Future<void> addTabletCard(TabletModel tablet);
  Future<void> updateUser(UserModel user);
  Future<void> updateTablet(TabletModel tablet);
  Future<void> deleteUsers(List<String> ids);
  Future<void> deleteTablets(List<String> ids);

  Future<List<UserModel>> getUsersByAreaOnceWithCache(String selectedArea);
  Future<List<TabletModel>> getTabletsByAreaOnceWithCache(String selectedArea);

  Future<List<UserModel>> refreshUsersBySelectedArea(String selectedArea);
  Future<List<UserModel>> refreshUsersByDivisionAreaFromShow(String division, String area);
  Future<List<TabletModel>> refreshTabletsBySelectedArea(String selectedArea);

  Future<void> updateUsersCache(String selectedArea, List<UserModel> users);
  Future<void> updateTabletsCache(String selectedArea, List<TabletModel> tablets);

  Future<void> clearUsersCache(String selectedArea);
  Future<void> clearTabletsCache(String selectedArea);

  Future<String?> getEnglishNameByArea(String area, String division);
}
