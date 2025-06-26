import '../../models/status_model.dart';

/// 상태 관련 데이터 처리 추상 인터페이스
abstract class StatusRepository {
  /// ✅ 단발성 상태 목록 조회 (Firestore 호출)
  Future<List<StatusModel>> getStatusesOnce(String area);

  /// ✨ 캐싱 우선 상태 목록 조회
  ///
  /// - SharedPreferences 캐시에 유효한 데이터가 있으면 캐시 반환
  /// - 유효기간 초과 또는 캐시 없음 → Firestore 호출 후 캐시 갱신
  Future<List<StatusModel>> getStatusesOnceWithCache(String area);

  /// ➕ 새 상태 항목 추가
  Future<void> addToggleItem(StatusModel status);

  /// 🔄 상태 항목의 활성/비활성 전환
  Future<void> updateToggleStatus(String id, bool isActive);

  /// ❌ 상태 항목 삭제
  Future<void> deleteToggleItem(String id);
}
