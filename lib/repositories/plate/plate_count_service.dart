import 'package:cloud_firestore/cloud_firestore.dart';
import '../../enums/plate_type.dart';
import '../../screens/type_pages/debugs/firestore_logger.dart';

class PlateCountService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Future<int> getPlateCountForTypePage(
    PlateType type,
    String area,
  ) async {
    await FirestoreLogger().log('getPlateCountForTypePage called: type=${type.name}, area=$area');

    final aggregateQuerySnapshot = await _firestore
        .collection('plates')
        .where('type', isEqualTo: type.firestoreValue)
        .where('area', isEqualTo: area)
        .count()
        .get();

    final count = aggregateQuerySnapshot.count ?? 0;
    await FirestoreLogger().log('getPlateCountForTypePage success: $count');
    return count;
  }

  Future<int> getParkingCompletedCountAll(String area) async {
    await FirestoreLogger().log('getParkingCompletedCountAll called: area=$area (parking_completed)');

    final baseQuery = _firestore
        .collection('plates')
        .where('type', isEqualTo: PlateType.parkingCompleted.firestoreValue)
        .where('area', isEqualTo: area);

    try {
      final agg = await baseQuery.count().get();
      final int? serverCount = agg.count;
      if (serverCount != null) {
        await FirestoreLogger().log('getParkingCompletedCountAll success (aggregate): $serverCount');
        return serverCount;
      }
    } catch (e) {
      await FirestoreLogger().log('getParkingCompletedCountAll aggregate failed: $e → fallback to get().size');
    }

    final snap = await baseQuery.get();
    final count = snap.size;
    await FirestoreLogger().log('getParkingCompletedCountAll success (fallback): $count');
    return count;
  }

  Future<int> getDepartureCompletedCountAll(String area) async {
    await FirestoreLogger()
        .log('getLockedDepartureCountAll called: area=$area (departure_completed && isLockedFee == true)');

    final baseQuery = _firestore
        .collection('plates')
        .where('type', isEqualTo: PlateType.departureCompleted.firestoreValue)
        .where('area', isEqualTo: area)
        .where('isLockedFee', isEqualTo: true);

    try {
      final agg = await baseQuery.count().get();
      final int? serverCount = agg.count;
      if (serverCount != null) {
        await FirestoreLogger().log('getLockedDepartureCountAll success (aggregate): $serverCount');
        return serverCount;
      }
    } catch (e) {
      await FirestoreLogger().log('getLockedDepartureCountAll aggregate failed: $e → fallback to get().size');
    }

    final snap = await baseQuery.get();
    final count = snap.size;
    await FirestoreLogger().log('getLockedDepartureCountAll success (fallback): $count');
    return count;
  }
}
