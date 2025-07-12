import 'package:cloud_firestore/cloud_firestore.dart';
import '../../models/location_model.dart';
import '../../screens/type_pages/debugs/firestore_logger.dart';

class LocationReadService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// 특정 지역의 위치 정보를 1회 조회합니다.
  Future<List<LocationModel>> getLocationsOnce(String area) async {
    await FirestoreLogger().log('getLocationsOnce called (area=$area)');

    try {
      final snapshot = await _firestore
          .collection('locations')
          .where('area', isEqualTo: area)
          .get();

      final result = snapshot.docs
          .map((doc) => LocationModel.fromMap(doc.id, doc.data()))
          .toList();

      await FirestoreLogger()
          .log('getLocationsOnce success: ${result.length} items loaded');

      return result;
    } catch (e) {
      await FirestoreLogger().log('getLocationsOnce error: $e');
      rethrow;
    }
  }
}
