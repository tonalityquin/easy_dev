import '../../models/adjustment_model.dart';

/// 조정 데이터에 대한 추상 인터페이스
abstract class AdjustmentRepository {
  /// 🔁 실시간 스트림 방식 (기존 방식)
  Stream<List<AdjustmentModel>> getAdjustmentStream(String currentArea);

  /// ✅ 새로 추가된 단발성 조회 방식 (.get())
  Future<List<AdjustmentModel>> getAdjustmentsOnce(String area);

  /// 신규 조정 데이터 추가
  Future<void> addAdjustment(AdjustmentModel adjustment);

  /// 여러 조정 데이터 삭제
  Future<void> deleteAdjustment(List<String> ids);
}
