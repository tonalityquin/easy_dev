import 'dart:async';
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
      final agg = await baseQuery.count().get().timeout(const Duration(seconds: 10));
      final int count = agg.count ?? 0; // ← int로 정제
      await FirestoreLogger().log('getParkingCompletedCountAll success (aggregate): $count');
      return count;
    } catch (e) {
      await FirestoreLogger().log('getParkingCompletedCountAll aggregate failed: $e');
      rethrow;
    }
  }

  Future<int> getDepartureCompletedCountAll(String area) async {
    await FirestoreLogger()
        .log('getDepartureCompletedCountAll called: area=$area (departure_completed && isLockedFee == true)');

    final baseQuery = _firestore
        .collection('plates')
        .where('type', isEqualTo: PlateType.departureCompleted.firestoreValue)
        .where('area', isEqualTo: area)
        .where('isLockedFee', isEqualTo: true);

    try {
      final agg = await baseQuery.count().get().timeout(const Duration(seconds: 10));
      final int count = agg.count ?? 0; // ← int로 정제
      await FirestoreLogger().log('getDepartureCompletedCountAll success (aggregate): $count');
      return count;
    } catch (e) {
      await FirestoreLogger().log('getDepartureCompletedCountAll aggregate failed: $e');
      rethrow;
    }
  }
}
