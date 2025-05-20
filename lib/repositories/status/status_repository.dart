import '../../models/status_model.dart';

/// 상태 관련 데이터 처리 추상 인터페이스
abstract class StatusRepository {
  /// 🔁 실시간 스트림 방식
  Stream<List<StatusModel>> getStatusStream(String area);

  /// ✅ 단발성 조회 방식 (추가됨)
  Future<List<StatusModel>> getStatusesOnce(String area);

  /// 상태 항목 추가
  Future<void> addToggleItem(StatusModel status);

  /// 상태 활성화/비활성화 토글
  Future<void> updateToggleStatus(String id, bool isActive);

  /// 상태 항목 삭제
  Future<void> deleteToggleItem(String id);
}
