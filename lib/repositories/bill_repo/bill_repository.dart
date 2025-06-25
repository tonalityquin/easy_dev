import '../../models/bill_model.dart';

/// 조정 데이터에 대한 추상 인터페이스
abstract class BillRepository {
  /// 🔁 실시간 스트림 방식 (기존 방식)
  Stream<List<BillModel>> getBillStream(String currentArea);

  /// ✅ 새로 추가된 단발성 조회 방식 (.get())
  Future<List<BillModel>> getBillOnce(String area);

  /// 신규 조정 데이터 추가
  Future<void> addBill(BillModel bill);

  /// 여러 조정 데이터 삭제
  Future<void> deleteBill(List<String> ids);
}
