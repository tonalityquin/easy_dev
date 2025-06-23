import '../../models/user_model.dart';

abstract class UserRepository {
  /// 전화번호로 사용자 정보 조회
  Future<UserModel?> getUserByPhone(String phone);

  /// ID로 사용자 정보 조회
  Future<UserModel?> getUserById(String userId);

  /// 사용자의 currentArea를 업데이트
  Future<void> updateCurrentArea(String phone, String area, String currentArea);

  /// 사용자 상태 업데이트 (근무 여부, 저장 여부 등)
  Future<void> updateUserStatus(
    String phone,
    String area, {
    bool? isWorking,
    bool? isSaved,
  });

  /// 사용자 추가
  Future<void> addUser(UserModel user);

  /// 사용자 삭제
  Future<void> deleteUsers(List<String> ids);

  /// 선택 상태 토글
  Future<void> toggleUserSelection(String id, bool isSelected);

  /// selectedArea 필드 기준 사용자 필터링
  Stream<List<UserModel>> getUsersBySelectedAreaStream(String selectedArea);
}
