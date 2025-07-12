import 'package:cloud_firestore/cloud_firestore.dart';
import '../../screens/type_pages/debugs/firestore_logger.dart';

class LocationCountService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// ✅ 단일 위치의 입차 수 조회
  Future<int> getPlateCount({
    required String locationName,
    required String area,
    String type = 'parking_completed',
  }) async {
    await FirestoreLogger().log(
      'getPlateCount called (location=$locationName, area=$area, type=$type)',
    );

    try {
      final snapshot = await _firestore
          .collection('plates')
          .where('location', isEqualTo: locationName)
          .where('area', isEqualTo: area)
          .where('type', isEqualTo: type)
          .count()
          .get();

      await FirestoreLogger().log(
        'getPlateCount success: count=${snapshot.count}, location=$locationName',
      );

      return snapshot.count ?? 0; // ✅ null 안전 처리
    } catch (e) {
      await FirestoreLogger().log('getPlateCount error: $e');
      rethrow;
    }
  }

  /// ✅ 여러 위치의 입차 수 일괄 조회
  Future<Map<String, int>> getPlateCountsForLocations({
    required List<String> locationNames,
    required String area,
    String type = 'parking_completed',
  }) async {
    await FirestoreLogger().log(
      'getPlateCountsForLocations called (${locationNames.length} locations, area=$area, type=$type)',
    );

    try {
      // ✅ 병렬 요청 처리
      final futures = locationNames.map((name) async {
        final count = await getPlateCount(
          locationName: name,
          area: area,
          type: type,
        );
        return MapEntry(name, count);
      }).toList();

      final entries = await Future.wait(futures);
      final result = Map.fromEntries(entries);

      await FirestoreLogger().log(
        'getPlateCountsForLocations success: total=${result.length}',
      );

      return result;
    } catch (e) {
      await FirestoreLogger().log('getPlateCountsForLocations error: $e');
      rethrow;
    }
  }
}
