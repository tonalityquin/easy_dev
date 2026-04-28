import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../plate/domain/enums/plate_type.dart';
import '../../../plate/domain/repositories/plate_tts_listener_repository.dart';
class FirestorePlateTtsListenerRepository implements PlateTtsListenerRepository {
  FirestorePlateTtsListenerRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  PlateTtsChangeType _mapType(DocumentChangeType type) {
    switch (type) {
      case DocumentChangeType.added:
        return PlateTtsChangeType.added;
      case DocumentChangeType.modified:
        return PlateTtsChangeType.modified;
      case DocumentChangeType.removed:
        return PlateTtsChangeType.removed;
    }
  }

  @override
  Future<PlateTtsBaselineCursor> fetchBaseline({
    required String area,
    required List<PlateType> types,
  }) async {
    final safeArea = area.trim();
    if (safeArea.isEmpty || types.isEmpty) {
      return const PlateTtsBaselineCursor(updatedAt: null, docId: null);
    }

    final qs = await _firestore
        .collection('plates')
        .where('area', isEqualTo: safeArea)
        .where('type', whereIn: types.map((e) => e.firestoreValue).toList(growable: false))
        .orderBy('updatedAt', descending: true)
        .orderBy(FieldPath.documentId, descending: true)
        .limit(1)
        .get();

    if (qs.docs.isEmpty) {
      return const PlateTtsBaselineCursor(updatedAt: null, docId: null);
    }

    final doc = qs.docs.first;
    final data = doc.data();
    final ts = data['updatedAt'];
    if (ts is Timestamp) {
      return PlateTtsBaselineCursor(updatedAt: ts.toDate(), docId: doc.id);
    }

    return const PlateTtsBaselineCursor(updatedAt: null, docId: null);
  }

  @override
  Stream<PlateTtsChangeBatch> watchChanges({
    required String area,
    required List<PlateType> types,
    DateTime? startAfterUpdatedAt,
    String? startAfterDocumentId,
  }) {
    final safeArea = area.trim();
    if (safeArea.isEmpty || types.isEmpty) {
      return const Stream<PlateTtsChangeBatch>.empty();
    }

    Query<Map<String, dynamic>> query = _firestore
        .collection('plates')
        .where('area', isEqualTo: safeArea)
        .where('type', whereIn: types.map((e) => e.firestoreValue).toList(growable: false))
        .orderBy('updatedAt')
        .orderBy(FieldPath.documentId);

    if (startAfterUpdatedAt != null &&
        (startAfterDocumentId?.trim().isNotEmpty ?? false)) {
      query = query.startAfter([
        Timestamp.fromDate(startAfterUpdatedAt),
        startAfterDocumentId!.trim(),
      ]);
    }

    return query.snapshots().map((snapshot) {
      final changes = snapshot.docChanges
          .map((change) => PlateTtsDocChange(
                type: _mapType(change.type),
                docId: change.doc.id,
                data: change.doc.data(),
              ))
          .toList(growable: false);

      return PlateTtsChangeBatch(
        isFromCache: snapshot.metadata.isFromCache,
        hasPendingWrites: snapshot.metadata.hasPendingWrites,
        changes: changes,
      );
    });
  }
}
