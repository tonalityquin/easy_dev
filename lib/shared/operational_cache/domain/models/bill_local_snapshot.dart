import '../../../../features/payment/domain/models/bill_model.dart';
import '../../../../features/payment/domain/models/regular_bill_model.dart';

class BillLocalSnapshot {
  const BillLocalSnapshot({
    required this.generalBills,
    required this.regularBills,
  });

  final List<BillModel> generalBills;
  final List<RegularBillModel> regularBills;
}
