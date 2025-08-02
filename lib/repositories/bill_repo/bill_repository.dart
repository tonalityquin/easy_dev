import '../../models/bill_model.dart';
import '../../models/regular_bill_model.dart';

/// 조정 데이터에 대한 추상 인터페이스
abstract class BillRepository {
  /// ✅ 일반 정산 데이터 조회 (.get())
  Future<List<BillModel>> getBillOnce(String area);

  /// ✅ 정기 정산 데이터 조회 (.get())
  Future<List<RegularBillModel>> getRegularBillOnce(String area);

  /// ✅ 일반 정산 데이터 추가
  Future<void> addNormalBill(BillModel bill);

  /// ✅ 정기 정산 데이터 추가
  Future<void> addRegularBill(RegularBillModel regularBill);

  /// ✅ 데이터 삭제 (공통)
  Future<void> deleteBill(List<String> ids);
  Future<({
  List<BillModel> generalBills,
  List<RegularBillModel> regularBills,
  })> getAllBills(String area);

}
