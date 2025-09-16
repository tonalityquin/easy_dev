// lib/repositories/user_repo_services/user_repository.dart
import '../../models/tablet_model.dart';
import '../../models/user_model.dart';

/// 데이터 소스(Firestore + 캐시)를 추상화한 저장소 인터페이스.
/// - 사람/일반 계정: `user_accounts` (UserModel)
/// - 태블릿 전용 계정: `tablet_accounts` (TabletModel)
abstract class UserRepository {
  // ===== 단건 조회 =====
  Future<UserModel?> getUserByPhone(String phone);
  Future<UserModel?> getUserById(String userId);
  Future<UserModel?> getUserByHandle(String handle);
  Future<TabletModel?> getTabletByHandle(String handle);
  Future<TabletModel?> getTabletByHandleAndAreaName(String handle, String areaName);

  // ===== 상태 업데이트 (일반 user_accounts) =====
  Future<void> updateLoadCurrentArea(String phone, String area, String currentArea);
  Future<void> areaPickerCurrentArea(String phone, String area, String currentArea);
  Future<void> updateLogOutUserStatus(String phone, String area, {bool? isWorking, bool? isSaved});
  Future<void> updateWorkingUserStatus(String phone, String area, {bool? isWorking, bool? isSaved});

  // ===== 상태 업데이트 (tablet_accounts) =====
  Future<void> updateLoadCurrentAreaTablet(String handle, String areaName, String currentArea);
  Future<void> areaPickerCurrentAreaTablet(String handle, String areaName, String currentArea);
  Future<void> updateLogOutTabletStatus(String handle, String areaName, {bool? isWorking, bool? isSaved});
  Future<void> updateWorkingTabletStatus(String handle, String areaName, {bool? isWorking, bool? isSaved});

  // ===== 생성/수정/삭제 =====
  Future<void> addUserCard(UserModel user);
  Future<void> addTabletCard(TabletModel tablet);
  Future<void> updateUser(UserModel user);
  Future<void> updateTablet(TabletModel tablet);
  Future<void> deleteUsers(List<String> ids);
  Future<void> deleteTablets(List<String> ids);

  // ===== 리스트 조회(캐시/네트워크) =====
  Future<List<UserModel>> getUsersByAreaOnceWithCache(String selectedArea);
  Future<List<UserModel>> getTabletsByAreaOnceWithCache(String selectedArea);

  Future<List<UserModel>> refreshUsersBySelectedArea(String selectedArea);
  Future<List<UserModel>> refreshTabletsBySelectedArea(String selectedArea);

  // ===== 캐시 갱신(로컬에서 즉시 반영 용) =====
  Future<void> updateUsersCache(String selectedArea, List<UserModel> users);
  Future<void> updateTabletsCache(String selectedArea, List<UserModel> tablets);

  Future<void> clearUsersCache(String selectedArea);
  Future<void> clearTabletsCache(String selectedArea);

  // ===== 부가 조회 =====
  Future<String?> getEnglishNameByArea(String area, String division);
}
