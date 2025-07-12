import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../../enums/plate_type.dart';
import '../../screens/type_pages/debugs/firestore_logger.dart';

class PlateCountService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  int? _cachedPlateCount;
  DateTime? _lastFetchTime;

  /// 특정 type + area 에 해당하는 plate 개수
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

  /// 현재 지역(area)에 존재하는 plate 수 반환 (캐시 포함)
  Future<int> getPlateCountToCurrentArea(String area) async {
    final now = DateTime.now();

    final isCacheValid = _cachedPlateCount != null &&
        _lastFetchTime != null &&
        now.difference(_lastFetchTime!) < const Duration(minutes: 3);

    if (isCacheValid) {
      debugPrint('📦 캐시된 plate count 반환: $_cachedPlateCount (area=$area)');
      await FirestoreLogger().log('getPlateCountToCurrentArea: returned from cache → count=$_cachedPlateCount');
      return _cachedPlateCount!;
    }

    debugPrint('📡 Firestore에서 plate count 쿼리 수행 (area=$area)');
    await FirestoreLogger().log('getPlateCountToCurrentArea: querying Firestore (area=$area)');

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

      _cachedPlateCount = count;
      _lastFetchTime = now;

      debugPrint('✅ Firestore에서 plate count 수신: $count (area=$area)');
      await FirestoreLogger().log('getPlateCountToCurrentArea success: count=$count');

      return count;
    } catch (e) {
      debugPrint('❌ Firestore plate count 실패: $e');
      await FirestoreLogger().log('getPlateCountToCurrentArea failed: $e');
      return 0;
    }
  }

  /// 출근 페이지용 plate 개수 (요청 상태만 허용)
  Future<int> getPlateCountForClockInPage(
      PlateType type, {
        DateTime? selectedDate,
        required String area,
      }) async {
    if (type != PlateType.parkingRequests && type != PlateType.departureRequests) {
      return 0;
    }

    await FirestoreLogger()
        .log('getPlateCountForClockInPage called: type=${type.name}, area=$area, selectedDate=$selectedDate');

    try {
      final query = _firestore
          .collection('plates')
          .where('type', isEqualTo: type.firestoreValue)
          .where('area', isEqualTo: area);

      final result = await query.count().get();
      final count = result.count ?? 0;

      await FirestoreLogger().log('getPlateCountForClockInPage success: $count');
      return count;
    } catch (e) {
      await FirestoreLogger().log('getPlateCountForClockInPage error: $e');
      return 0;
    }
  }

  /// 퇴근 페이지용 plate 개수 (완료 상태만 허용)
  Future<int> getPlateCountForClockOutPage(
      PlateType type, {
        DateTime? selectedDate,
        required String area,
      }) async {
    if (type != PlateType.parkingCompleted && type != PlateType.departureCompleted) {
      return 0;
    }

    await FirestoreLogger()
        .log('getPlateCountForClockOutPage called: type=${type.name}, area=$area, selectedDate=$selectedDate');

    try {
      Query<Map<String, dynamic>> query = _firestore
          .collection('plates')
          .where('type', isEqualTo: type.firestoreValue)
          .where('area', isEqualTo: area);

      // 날짜 필터링: departureCompleted인 경우만 날짜 사용
      if (selectedDate != null && type == PlateType.departureCompleted) {
        final start = DateTime(selectedDate.year, selectedDate.month, selectedDate.day);
        final end = start.add(const Duration(days: 1));

        query = query
            .where('request_time', isGreaterThanOrEqualTo: start)
            .where('request_time', isLessThan: end);
      }

      final result = await query.count().get();
      final count = result.count ?? 0;

      await FirestoreLogger().log('getPlateCountForClockOutPage success: $count');
      return count;
    } catch (e) {
      await FirestoreLogger().log('getPlateCountForClockOutPage error: $e');
      return 0;
    }
  }
}
