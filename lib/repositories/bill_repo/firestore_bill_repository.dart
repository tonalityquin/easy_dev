import '../../models/bill_model.dart';
import 'bill_delete_service.dart';
import 'bill_read_service.dart';
import 'bill_repository.dart';
import 'bill_write_service.dart';

class FirestoreBillRepository implements BillRepository {
  final BillReadService _readService = BillReadService();
  final BillWriteService _writeService = BillWriteService();
  final BillDeleteService _deleteService = BillDeleteService();

  @override
  Future<List<BillModel>> getBillOnce(String area) {
    return _readService.getBillOnce(area);
  }

  @override
  Future<void> addBill(BillModel bill) {
    return _writeService.addBill(bill);
  }

  @override
  Future<void> deleteBill(List<String> ids) {
    return _deleteService.deleteBill(ids);
  }
}
