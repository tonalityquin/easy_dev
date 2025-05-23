import '../../models/status_model.dart';

/// 상태 관련 데이터 처리 추상 인터페이스
abstract class StatusRepository {
  /// 🔁 실시간 상태 스트림 (선택 사용)
  Stream<List<StatusModel>> getStatusStream(String area);

  /// ✅ 단발성 상태 목록 조회 (.get() 기반)
  Future<List<StatusModel>> getStatusesOnce(String area);

  /// ➕ 새 상태 항목 추가
  Future<void> addToggleItem(StatusModel status);

  /// 🔄 상태 항목의 활성/비활성 전환
  Future<void> updateToggleStatus(String id, bool isActive);

  /// ❌ 상태 항목 삭제
  Future<void> deleteToggleItem(String id);
}
