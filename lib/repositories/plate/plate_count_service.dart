import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../../enums/plate_type.dart';
import '../../screens/type_pages/debugs/firestore_logger.dart';

class PlateCountService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  final Map<String, int> _areaCountCache = {};
  final Map<String, DateTime> _areaFetchTimeCache = {};

  Future<int> getPlateCountForTypePage(
      PlateType type,
      String area,
      ) async {
    await FirestoreLogger()
        .log('getPlateCountForTypePage called: type=${type.name}, area=$area');

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

  Future<int> getPlateCountToCurrentArea(String area) async {
    final now = DateTime.now();

    final isCacheValid = _areaCountCache.containsKey(area) &&
        _areaFetchTimeCache.containsKey(area) &&
        now.difference(_areaFetchTimeCache[area]!) <
            const Duration(minutes: 3);

    if (isCacheValid) {
      final cachedCount = _areaCountCache[area]!;
      debugPrint('📦 캐시된 plate count 반환: $cachedCount (area=$area)');
      await FirestoreLogger().log(
          'getPlateCountToCurrentArea: returned from cache → count=$cachedCount');
      return cachedCount;
    }

    debugPrint('📡 Firestore에서 plate count 쿼리 수행 (area=$area)');
    await FirestoreLogger()
        .log('getPlateCountToCurrentArea: querying Firestore (area=$area)');

    try {
      final allowedTypes = [
        PlateType.parkingRequests.firestoreValue,
        PlateType.parkingCompleted.firestoreValue,
        PlateType.departureRequests.firestoreValue,
      ];

      final snapshot = await _firestore
          .collection('plates')
          .where('area', isEqualTo: area)
          .where('type', whereIn: allowedTypes)
          .count()
          .get();

      final count = snapshot.count ?? 0;

      _areaCountCache[area] = count;
      _areaFetchTimeCache[area] = now;

      debugPrint('✅ Firestore에서 plate count 수신: $count (area=$area)');
      await FirestoreLogger()
          .log('getPlateCountToCurrentArea success: count=$count');

      return count;
    } catch (e) {
      debugPrint('❌ Firestore plate count 실패: $e');
      await FirestoreLogger().log('getPlateCountToCurrentArea failed: $e');
      return 0;
    }
  }

  Future<int> getPlateCountForClockInPage(
      PlateType type, {
        DateTime? selectedDate,
        required String area,
      }) async {
    if (type != PlateType.parkingRequests &&
        type != PlateType.departureRequests) {
      return 0;
    }

    await FirestoreLogger().log(
        'getPlateCountForClockInPage called: type=${type.name}, area=$area, selectedDate=$selectedDate');

    try {
      final query = _firestore
          .collection('plates')
          .where('type', isEqualTo: type.firestoreValue)
          .where('area', isEqualTo: area);

      final result = await query.count().get();
      final count = result.count ?? 0;

      await FirestoreLogger()
          .log('getPlateCountForClockInPage success: $count');
      return count;
    } catch (e) {
      await FirestoreLogger().log('getPlateCountForClockInPage error: $e');
      return 0;
    }
  }

  Future<int> getPlateCountForClockOutPage(
      PlateType type, {
        DateTime? selectedDate,
        required String area,
      }) async {
    if (type != PlateType.parkingCompleted &&
        type != PlateType.departureCompleted) {
      return 0;
    }

    await FirestoreLogger().log(
        'getPlateCountForClockOutPage called: type=${type.name}, area=$area, selectedDate=$selectedDate');

    try {
      Query<Map<String, dynamic>> query = _firestore
          .collection('plates')
          .where('type', isEqualTo: type.firestoreValue)
          .where('area', isEqualTo: area);

      if (selectedDate != null && type == PlateType.departureCompleted) {
        final start =
        DateTime(selectedDate.year, selectedDate.month, selectedDate.day);
        final end = start.add(const Duration(days: 1));

        query = query
            .where('request_time', isGreaterThanOrEqualTo: start)
            .where('request_time', isLessThan: end);
      }

      final result = await query.count().get();
      final count = result.count ?? 0;

      await FirestoreLogger()
          .log('getPlateCountForClockOutPage success: $count');
      return count;
    } catch (e) {
      await FirestoreLogger().log('getPlateCountForClockOutPage error: $e');
      return 0;
    }
  }
  // ---------------------------------------------------------------------------
  // type == parking_completed && area == currentArea
  // 시간 필터 없음. count() → get().size 폴백.
  // ---------------------------------------------------------------------------
  Future<int> getParkingCompletedCountAll(String area) async {
    await FirestoreLogger().log(
        'getParkingCompletedCountAll called: area=$area (parking_completed)');

    final baseQuery = _firestore
        .collection('plates')
        .where('type', isEqualTo: PlateType.parkingCompleted.firestoreValue)
        .where('area', isEqualTo: area);

    try {
      final agg = await baseQuery.count().get();
      final int? serverCount = agg.count;
      if (serverCount != null) {
        await FirestoreLogger().log(
            'getParkingCompletedCountAll success (aggregate): $serverCount');
        return serverCount;
      }
    } catch (e) {
      await FirestoreLogger().log(
          'getParkingCompletedCountAll aggregate failed: $e → fallback to get().size');
    }

    final snap = await baseQuery.get();
    final count = snap.size;
    await FirestoreLogger()
        .log('getParkingCompletedCountAll success (fallback): $count');
    return count;
  }


  // ---------------------------------------------------------------------------
  // type == departure_completed && isLockedFee == true && area == currentArea
  // 시간 필터 없음. count() → get().size 폴백.
  // ---------------------------------------------------------------------------
  Future<int> getLockedDepartureCountAll(String area) async {
    await FirestoreLogger().log(
        'getLockedDepartureCountAll called: area=$area (departure_completed && isLockedFee == true)');

    final baseQuery = _firestore
        .collection('plates')
        .where('type', isEqualTo: PlateType.departureCompleted.firestoreValue)
        .where('area', isEqualTo: area)
        .where('isLockedFee', isEqualTo: true);

    try {
      final agg = await baseQuery.count().get();
      final int? serverCount = agg.count;
      if (serverCount != null) {
        await FirestoreLogger()
            .log('getLockedDepartureCountAll success (aggregate): $serverCount');
        return serverCount;
      }
    } catch (e) {
      await FirestoreLogger().log(
          'getLockedDepartureCountAll aggregate failed: $e → fallback to get().size');
    }

    final snap = await baseQuery.get();
    final count = snap.size;
    await FirestoreLogger()
        .log('getLockedDepartureCountAll success (fallback): $count');
    return count;
  }
}
