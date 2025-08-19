import 'package:cloud_firestore/cloud_firestore.dart';
import '../../enums/plate_type.dart';
import '../../models/plate_model.dart';
import '../../screens/type_pages/debugs/firestore_logger.dart';

class PlateStreamService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Stream<List<PlateModel>> streamToCurrentArea(
    PlateType type,
    String area, {
    bool descending = true,
    String? location,
  }) {
    FirestoreLogger().log(
      'streamToCurrentArea called: type=${type.name}, area=$area, descending=$descending, location=$location',
    );

    final query = _buildPlateQuery(
      type: type,
      area: area,
      location: location,
      descending: descending,
    );

    return query.snapshots().map((snapshot) {
      final results = snapshot.docs
          .map((doc) {
            try {
              return PlateModel.fromDocument(doc);
            } catch (e) {
              FirestoreLogger().log('❌ streamToCurrentArea parsing error: $e');
              return null;
            }
          })
          .whereType<PlateModel>()
          .toList();

      FirestoreLogger().log('✅ streamToCurrentArea loaded: ${results.length} items');
      return results;
    });
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> departureUnpaidSnapshots({
    required String area,
    bool descending = true,
  }) {
    final query = _firestore
        .collection('plates')
        .where('type', isEqualTo: PlateType.departureCompleted.firestoreValue)
        .where('area', isEqualTo: area)
        .where('isLockedFee', isEqualTo: false)
        .orderBy('request_time', descending: descending);

    FirestoreLogger().log(
      'departureUnpaidSnapshots called: area=$area, descending=$descending',
    );

    return query.snapshots();
  }

  Query<Map<String, dynamic>> _buildPlateQuery({
    required PlateType type,
    required String area,
    String? location,
    bool descending = true,
  }) {
    Query<Map<String, dynamic>> query =
        _firestore.collection('plates').where('type', isEqualTo: type.firestoreValue).where('area', isEqualTo: area);

    if (type == PlateType.departureCompleted) {
      query = query.where('isLockedFee', isEqualTo: false);
    }

    if (type == PlateType.parkingCompleted && location != null && location.isNotEmpty) {
      query = query.where('location', isEqualTo: location);
    }

    query = query.orderBy('request_time', descending: descending);

    return query;
  }
}
