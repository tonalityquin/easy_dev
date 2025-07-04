import '../../models/user_model.dart';

abstract class UserRepository {
  /// 📥 전화번호로 사용자 정보 조회
  Future<UserModel?> getUserByPhone(String phone);

  /// 📥 ID로 사용자 정보 조회
  Future<UserModel?> getUserById(String userId);

  /// 📝 사용자의 currentArea를 업데이트

  Future<void> updateLoadUserStatus(
    String phone,
    String area, {
    bool? isWorking,
    bool? isSaved,
  });

  Future<void> updateLoadCurrentArea(
    String phone,
    String area,
    String currentArea,
  );

  Future<void> areaPickerCurrentArea(
    String phone,
    String area,
    String currentArea,
  );

  /// 🔄 사용자 상태 업데이트 (근무 여부, 저장 여부 등)
  Future<void> updateLogOutUserStatus(
    String phone,
    String area, {
    bool? isWorking,
    bool? isSaved,
  });

  Future<void> updateWorkingUserStatus(
    String phone,
    String area, {
    bool? isWorking,
    bool? isSaved,
  });

  /// ➕ 사용자 추가
  Future<void> addUserCard(UserModel user);

  Future<void> updateUser(UserModel user);

  /// ❌ 사용자 삭제
  Future<void> deleteUsers(List<String> ids);

  /// 📂 캐시에 우선 조회
  Future<List<UserModel>> getUsersByAreaOnceWithCache(String selectedArea);

  /// 🔄 Firestore 호출 + 캐시 갱신
  Future<List<UserModel>> refreshUsersBySelectedArea(String selectedArea);

  /// 🧭 areas 컬렉션에서 division(=area) 기준 englishName 조회
  Future<String?> getEnglishNameByArea(String area, String division);
}
