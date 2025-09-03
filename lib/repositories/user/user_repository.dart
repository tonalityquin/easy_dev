import '../../models/tablet_model.dart';
import '../../models/user_model.dart';

/// 데이터 소스(Firestore + 캐시)를 추상화한 저장소 인터페이스.
///
/// - 사람/일반 계정: `user_accounts` (UserModel)
/// - 태블릿 전용 계정: `tablet_accounts` (TabletModel)
///
/// 태블릿 화면(UI)에서는 TabletModel을 사용하되,
/// 기존 상태/목록은 UserModel 기준으로 호환될 수 있도록 설계합니다.
abstract class UserRepository {
  // ===== 단건 조회 =====

  /// 📥 전화번호로 사용자(UserModel) 조회
  Future<UserModel?> getUserByPhone(String phone);

  /// 📥 ID(docId)로 사용자(UserModel) 조회
  Future<UserModel?> getUserById(String userId);

  /// 📥 (선택) handle로 사용자(UserModel) 조회
  /// - 1) user_accounts의 'handle' 필드가 있으면 우선 검색
  /// - 2) 과거 호환: 'phone' == handle 로도 검색
  Future<UserModel?> getUserByHandle(String handle);

  /// 📥 handle로 태블릿 계정(TabletModel) 조회 (tablet_accounts)
  Future<TabletModel?> getTabletByHandle(String handle);

  /// 📥 handle + areaName(한글 지역명)으로 태블릿 계정 직조회
  ///    (docId = "$handle-$areaName")
  Future<TabletModel?> getTabletByHandleAndAreaName(String handle, String areaName);

  // ===== 상태 업데이트 =====

  /// 📝 앱 시작 시 현재 지역(currentArea) 동기화
  Future<void> updateLoadCurrentArea(
      String phone,
      String area,
      String currentArea,
      );

  /// 📝 지역 피커로 currentArea 변경
  Future<void> areaPickerCurrentArea(
      String phone,
      String area,
      String currentArea,
      );

  /// 🔄 로그아웃 시 상태 업데이트
  Future<void> updateLogOutUserStatus(
      String phone,
      String area, {
        bool? isWorking,
        bool? isSaved,
      });

  /// 🔄 근무 상태 토글/업데이트
  Future<void> updateWorkingUserStatus(
      String phone,
      String area, {
        bool? isWorking,
        bool? isSaved,
      });

  // ===== 생성/수정/삭제 =====

  /// ➕ 사용자(UserModel) 추가 → user_accounts
  Future<void> addUserCard(UserModel user);

  /// ➕ 태블릿(TabletModel) 추가 → tablet_accounts
  Future<void> addTabletCard(TabletModel tablet);

  /// ✏️ 사용자(UserModel) 전체 업데이트(업서트) → user_accounts
  Future<void> updateUser(UserModel user);

  /// ✏️ 태블릿(TabletModel) 전체 업데이트(업서트) → tablet_accounts
  Future<void> updateTablet(TabletModel tablet);

  /// ❌ 사용자 삭제 → user_accounts
  Future<void> deleteUsers(List<String> ids);

  /// ❌ 태블릿 삭제 → tablet_accounts
  Future<void> deleteTablets(List<String> ids);

  // ===== 리스트 조회(캐시/네트워크) =====

  /// 📂 캐시 우선 사용자 목록 조회 (area 기준, 없으면 빈 리스트)
  Future<List<UserModel>> getUsersByAreaOnceWithCache(String selectedArea);

  /// 🔄 Firestore에서 사용자 목록 새로고침 + 캐시 갱신 → user_accounts
  Future<List<UserModel>> refreshUsersBySelectedArea(String selectedArea);

  /// 🔄 Firestore에서 태블릿 목록 새로고침 + (UserModel로 변환하여) 캐시 갱신 → tablet_accounts
  ///
  /// 주의: 반환 타입은 화면/상태 호환을 위해 `List<UserModel>` 입니다.
  /// (TabletModel의 handle을 UserModel.phone 슬롯에 매핑)
  Future<List<UserModel>> refreshTabletsBySelectedArea(String selectedArea);

  // ===== 부가 조회 =====

  /// 🧭 areas 컬렉션에서 division-area 문서의 englishName 가져오기
  Future<String?> getEnglishNameByArea(String area, String division);
}
