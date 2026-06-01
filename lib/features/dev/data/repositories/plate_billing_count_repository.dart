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
    final snapshot = await _collection.where('month', isEqualTo: month).get();
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
    await _collection.doc(id).delete();
  }

  Future<int> deleteMonth(String month) async {
    final snapshot = await _collection.where('month', isEqualTo: month).get();
    if (snapshot.docs.isEmpty) return 0;
    var deleted = 0;
    for (var i = 0; i < snapshot.docs.length; i += 450) {
      final batch = _firestore.batch();
      final end = i + 450 > snapshot.docs.length ? snapshot.docs.length : i + 450;
      for (final doc in snapshot.docs.sublist(i, end)) {
        batch.delete(doc.reference);
      }
      await batch.commit();
      deleted += end - i;
    }
    return deleted;
  }
}
