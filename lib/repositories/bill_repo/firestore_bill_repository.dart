import '../../models/bill_model.dart';
import '../../models/regular_bill_model.dart';
import 'bill_delete_service.dart';
import 'bill_read_service.dart';
import 'bill_repository.dart';
import 'bill_write_service.dart';

class FirestoreBillRepository implements BillRepository {
  final BillReadService _readService = BillReadService();
  final BillWriteService _writeService = BillWriteService();
  final BillDeleteService _deleteService = BillDeleteService();

  @override
  Future<List<BillModel>> getBillOnce(String area) async {
    final result = await _readService.getBillOnce(area);
    return result.generalBills;
  }

  @override
  Future<List<RegularBillModel>> getRegularBillOnce(String area) async {
    final result = await _readService.getBillOnce(area);
    return result.regularBills;
  }

  @override
  Future<void> addNormalBill(BillModel bill) {
    return _writeService.addNormalBill(bill);
  }

  @override
  Future<void> addRegularBill(RegularBillModel regularBill) {
    return _writeService.addRegularBill(regularBill);
  }

  @override
  Future<void> deleteBill(List<String> ids) {
    return _deleteService.deleteBill(ids);
  }

  @override
  Future<
      ({
        List<BillModel> generalBills,
        List<RegularBillModel> regularBills,
      })> getAllBills(String area) {
    return _readService.getBillOnce(area);
  }
}
