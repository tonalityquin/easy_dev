import 'package:cloud_firestore/cloud_firestore.dart';
import '../../screens/hubs_mode/dev_package/debug_package/debug_database_logger.dart';
// import '../../utils/usage_reporter.dart';

class LocationCountService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// 표시 문자열(displayName)에서 실제 질의용 locationName(leaf)을 추출합니다.
  /// - 포맷: "parent - child - ... - leaf"
  /// - leaf만 반환해야 Firestore의 `location` 필드와 매칭됩니다.
  String _extractLocationName(String name) {
    const sep = ' - ';
    final trimmed = name.trim();
    if (trimmed.contains(sep)) {
      final parts = trimmed.split(sep);
      // 이름 안에 '-'가 더 있을 수 있으므로 첫 파트(parent)만 떼고 나머지를 다시 합칩니다.
      return parts.sublist(1).join(sep).trim();
    }
    return trimmed;
  }

  /// 특정 (location / area / type) 조합의 plates 집계 수를 aggregation count()로 조회
  /// - aggregation read 1회 발생
  Future<int> getPlateCount({
    required String locationName,
    required String area,
    String type = 'parking_completed',
  }) async {
    final _area = area.trim();
    final _loc = locationName.trim();
    final _type = type.trim();

    try {
      final snapshot = await _firestore
          .collection('plates')
          .where('location', isEqualTo: _loc)
          .where('area', isEqualTo: _area)
          .where('type', isEqualTo: _type)
          .count()
          .get();

      // 일부 SDK 버전에서 count가 int? 이므로 안전하게 널 병합
      final int safeCount = snapshot.count ?? 0;

      // 진단 로그(필요시 주석 해제)
      // debugPrint('🔎 count query → area=$_area, location=$_loc, type=$_type, result=$safeCount');

      try {
        /*UsageReporter.instance.report(
          area: _area,
          action: 'read',
          n: 1,
          source: 'LocationCountService.getPlateCount(plates.count)',
        );*/
      } catch (_) {}

      return safeCount;
    } on FirebaseException catch (e, st) {
      // Firestore 에러 로깅
      try {
        await DebugDatabaseLogger().log({
          'action': 'getPlateCount',
          'query': {
            'collection': 'plates',
            'area': _area,
            'location': _loc,
            'type': _type,
          },
          'error': {
            'type': e.runtimeType.toString(),
            'code': e.code,
            'message': e.toString(),
          },
          'stack': st.toString(),
          'tags': ['plates', 'count', 'error'],
        }, level: 'error');
      } catch (_) {}
      rethrow;
    } catch (e, st) {
      try {
        await DebugDatabaseLogger().log({
          'action': 'getPlateCount',
          'query': {
            'collection': 'plates',
            'area': _area,
            'location': _loc,
            'type': _type,
          },
          'error': {
            'type': e.runtimeType.toString(),
            'message': e.toString(),
          },
          'stack': st.toString(),
          'tags': ['plates', 'count', 'error'],
        }, level: 'error');
      } catch (_) {}
      rethrow;
    }
  }

  /// 여러 location(displayName)들에 대해 병렬로 카운트
  /// - displayName → leaf(location) 정규화 후 getPlateCount 호출
  /// - 결과 Map의 key는 displayName 유지(상태 갱신 로직과 일치)
  /// - 내부에서 getPlateCount를 호출하므로 read 보고는 각 호출에서 수행됩니다.
  Future<Map<String, int>> getPlateCountsForLocations({
    required List<String> locationNames, // displayName 목록
    required String area,
    String type = 'parking_completed',
  }) async {
    if (locationNames.isEmpty) return <String, int>{};

    final _area = area.trim();
    final _type = type.trim();

    try {
      final uniq = locationNames.map((e) => e.trim()).toSet().toList(); // ✅ 중복 제거
      const window = 10; // ✅ 동시성 제한(버스트 완화)

      final result = <String, int>{};
      for (int i = 0; i < uniq.length; i += window) {
        final end = (i + window < uniq.length) ? i + window : uniq.length;
        final slice = uniq.sublist(i, end);

        // displayName을 leaf로 정규화하여 실제 질의, 결과는 원래 displayName 키로 저장
        final entries = await Future.wait(slice.map((displayName) async {
          final locName = _extractLocationName(displayName);
          final count = await getPlateCount(
            locationName: locName,
            area: _area,
            type: _type,
          );
          return MapEntry(displayName, count);
        }));

        for (final e in entries) {
          result[e.key] = e.value;
        }
      }

      return result;
    } on FirebaseException catch (e, st) {
      try {
        await DebugDatabaseLogger().log({
          'action': 'getPlateCountsForLocations',
          'payload': {
            'names': locationNames.take(20).toList(),
            'area': _area,
            'type': _type,
          },
          'error': {
            'type': e.runtimeType.toString(),
            'code': e.code,
            'message': e.toString(),
          },
          'stack': st.toString(),
          'tags': ['plates', 'count', 'batch', 'error'],
        }, level: 'error');
      } catch (_) {}
      rethrow;
    } catch (e, st) {
      try {
        await DebugDatabaseLogger().log({
          'action': 'getPlateCountsForLocations',
          'payload': {
            'names': locationNames.take(20).toList(),
            'area': _area,
            'type': _type,
          },
          'error': {
            'type': e.runtimeType.toString(),
            'message': e.toString(),
          },
          'stack': st.toString(),
          'tags': ['plates', 'count', 'batch', 'error'],
        }, level: 'error');
      } catch (_) {}
      rethrow;
    }
  }
}
