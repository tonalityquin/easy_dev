import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../enums/plate_type.dart';

class PlateCountService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Future<int> getPlateCountForTypePage(
      PlateType type,
      String area,
      ) async {

    final aggregateQuerySnapshot = await _firestore
        .collection('plates')
        .where('type', isEqualTo: type.firestoreValue)
        .where('area', isEqualTo: area)
        .count()
        .get();

    final count = aggregateQuerySnapshot.count ?? 0;
    return count;
  }

  Future<int> getParkingCompletedCountAll(String area) async {

    final baseQuery = _firestore
        .collection('plates')
        .where('type', isEqualTo: PlateType.parkingCompleted.firestoreValue)
        .where('area', isEqualTo: area);

    try {
      final agg = await baseQuery.count().get().timeout(const Duration(seconds: 10));
      final int count = agg.count ?? 0; // ← int로 정제
      return count;
    } catch (e) {
      rethrow;
    }
  }

  Future<int> getDepartureCompletedCountAll(String area) async {

    final baseQuery = _firestore
        .collection('plates')
        .where('type', isEqualTo: PlateType.departureCompleted.firestoreValue)
        .where('area', isEqualTo: area)
        .where('isLockedFee', isEqualTo: true);

    try {
      final agg = await baseQuery.count().get().timeout(const Duration(seconds: 10));
      final int count = agg.count ?? 0; // ← int로 정제
      return count;
    } catch (e) {
      rethrow;
    }
  }
}
