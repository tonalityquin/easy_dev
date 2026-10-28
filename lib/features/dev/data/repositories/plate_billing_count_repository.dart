import '../../../../app/firebase_activity/firebase_activity_write_scope.dart';
import '../../../../app/firebase_activity/firebase_activity_monitor.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../../shared/plate/domain/services/plate_billing_count_service.dart';
import '../../domain/models/plate_billing_count_model.dart';

class PlateBillingCountRepository {
  PlateBillingCountRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _collection =>
      _firestore.collection(PlateBillingCountService.collectionName);

  Future<List<PlateBillingCountModel>> fetchByMonth(String month) async {
    final snapshot = await FirebaseActivityMonitor.track(FirebaseActivityKind.read, () => _collection.where('month', isEqualTo: month).get(), source: 'plate_billing_count_repository.get');
    final rows = snapshot.docs
        .where((doc) => doc.data()['aggregationAxis'] == 'division_area')
        .map(PlateBillingCountModel.fromDoc)
        .toList(growable: false);
    final sorted = rows.toList();
    sorted.sort((a, b) {
      final companyCompare = a.company.compareTo(b.company);
      if (companyCompare != 0) return companyCompare;
      final areaCompare = a.area.compareTo(b.area);
      if (areaCompare != 0) return areaCompare;
      return a.id.compareTo(b.id);
    });
    return sorted;
  }

  Future<void> deleteDocument(String id) async {
    await FirebaseActivityMonitor.track(FirebaseActivityKind.delete, () => _collection.doc(id).delete(), source: 'plate_billing_count_repository.delete');
  }

  Future<int> deleteMonth(String month) async {
    final snapshot = await FirebaseActivityMonitor.track(FirebaseActivityKind.read, () => _collection.where('month', isEqualTo: month).get(), source: 'plate_billing_count_repository.get');
    if (snapshot.docs.isEmpty) return 0;
    var deleted = 0;
    for (var i = 0; i < snapshot.docs.length; i += 450) {
      final batch = _firestore.batch();
      final end = i + 450 > snapshot.docs.length ? snapshot.docs.length : i + 450;
      for (final doc in snapshot.docs.sublist(i, end)) {
        FirebaseActivityWriteScope.batchCommand(batch, FirebaseActivityDocumentCommand.delete, () => batch.delete(doc.reference));
      }
      await FirebaseActivityMonitor.track(FirebaseActivityKind.batch, () => batch.commit(), batch: batch, source: 'plate_billing_count_repository.commit');
      deleted += end - i;
    }
    return deleted;
  }
}
