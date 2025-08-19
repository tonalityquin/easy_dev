import '../../models/bill_model.dart';
import '../../models/regular_bill_model.dart';

abstract class BillRepository {
  Future<List<BillModel>> getBillOnce(String area);

  Future<List<RegularBillModel>> getRegularBillOnce(String area);

  Future<void> addNormalBill(BillModel bill);

  Future<void> addRegularBill(RegularBillModel regularBill);

  Future<void> deleteBill(List<String> ids);

  Future<
      ({
        List<BillModel> generalBills,
        List<RegularBillModel> regularBills,
      })> getAllBills(String area);
}
