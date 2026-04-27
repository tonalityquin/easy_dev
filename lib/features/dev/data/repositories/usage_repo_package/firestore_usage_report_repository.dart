import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../domain/repositories/usage_repo_package/usage_report_repository.dart';

class FirestoreUsageReportRepository implements UsageReportRepository {
  FirestoreUsageReportRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  static const int maxBatchWrites = 450;

  final FirebaseFirestore _firestore;

  @override
  Future<void> flushDocUpdates(List<UsageCounterDocUpdate> updates) async {
    if (updates.isEmpty) return;

    var cursor = 0;
    while (cursor < updates.length) {
      final end = (cursor + maxBatchWrites < updates.length)
          ? cursor + maxBatchWrites
          : updates.length;

      final batch = _firestore.batch();

      for (var i = cursor; i < end; i++) {
        final upd = updates[i];
        final docRef = _firestore.doc(upd.documentPath);

        final payload = <String, dynamic>{
          'date': upd.date,
          'tenantId': upd.area,
          'userId': upd.userKey,
          'updatedAt': FieldValue.serverTimestamp(),
        };

        if (upd.reads > 0) payload['reads'] = FieldValue.increment(upd.reads);
        if (upd.writes > 0) payload['writes'] = FieldValue.increment(upd.writes);
        if (upd.deletes > 0) payload['deletes'] = FieldValue.increment(upd.deletes);

        if (upd.hasTrace) {
          payload['lastTraceAt'] = FieldValue.serverTimestamp();
          if (upd.lastTraceSource != null) {
            payload['lastTraceSource'] = upd.lastTraceSource;
          }
          if (upd.lastTraceExtra != null) {
            payload['lastTraceExtra'] = upd.lastTraceExtra;
          }
        }

        batch.set(docRef, payload, SetOptions(merge: true));
      }

      await batch.commit();
      cursor = end;
    }
  }
}
