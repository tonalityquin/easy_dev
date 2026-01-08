import 'package:cloud_firestore/cloud_firestore.dart';

/// plates 조회 결과를 Firebase 타입 없이 서비스/UI 계층에 전달하기 위한 레코드
class LockedPlateRecord {
  final String docId;
  final Map<String, dynamic> data;

  const LockedPlateRecord({
    required this.docId,
    required this.data,
  });
}

/// End-Report(업무 종료 보고)에서 사용되는 Firestore 로직을 분리한 Repository.
///
/// 책임:
/// 1) plates 스냅샷 조회 (departure_completed, area, isLockedFee=true)
/// 2) end_work_reports 저장 (월 문서 1개 + reports 맵에 일자 엔트리)
/// 3) plates 삭제 및 plate_counters 리셋(cleanup)
/// 4) Firestore data를 JSON 안전 형식으로 변환(jsonSafe)
class EndWorkReportFirestoreRepository {
  final FirebaseFirestore _firestore;

  EndWorkReportFirestoreRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  /// 1) plates 스냅샷 조회
  Future<List<LockedPlateRecord>> fetchLockedDepartureCompletedPlates({
    required String area,
  }) async {
    final snap = await _firestore
        .collection('plates')
        .where('type', isEqualTo: 'departure_completed')
        .where('area', isEqualTo: area)
        .where('isLockedFee', isEqualTo: true)
        .get();

    return snap.docs
        .map((d) => LockedPlateRecord(docId: d.id, data: d.data()))
        .toList(growable: false);
  }

  /// 2) end_work_reports 저장 (월 문서 + reports 맵)
  ///
  /// 기존 로직 그대로:
  /// - end_work_reports/area_<area> 문서: 메타(lastMonthKey, lastReportDate 등) 갱신
  /// - end_work_reports/area_<area>/months/<yyyyMM> 문서: reports.<yyyy-MM-dd> 엔트리 추가/갱신
  Future<void> saveMonthlyEndWorkReport({
    required String division,
    required String area,
    required String monthKey,
    required String dateStr, // yyyy-MM-dd
    required Map<String, dynamic> vehicleCount,
    required Map<String, dynamic> metrics,
    required String createdAtIso,
    required String uploadedBy,
    String? logsUrl,
  }) async {
    final areaRef = _firestore.collection('end_work_reports').doc('area_$area');
    final monthRef = areaRef.collection('months').doc(monthKey);

    final historyEntry = <String, dynamic>{
      'date': dateStr,
      'monthKey': monthKey,
      'createdAt': createdAtIso,
      'uploadedBy': uploadedBy,
      'vehicleCount': vehicleCount,
      'metrics': metrics,
      if (logsUrl != null) 'logsUrl': logsUrl,
    };

    final dayPayload = <String, dynamic>{
      'division': division,
      'area': area,
      'monthKey': monthKey,
      'date': dateStr,
      'vehicleCount': vehicleCount,
      'metrics': metrics,
      'createdAt': createdAtIso,
      'uploadedBy': uploadedBy,
      if (logsUrl != null) 'logsUrl': logsUrl,
      'updatedAt': FieldValue.serverTimestamp(),
      'history': FieldValue.arrayUnion(<Map<String, dynamic>>[historyEntry]),
    };

    final batch = _firestore.batch();

    // 2-1) area 메타(유지)
    batch.set(
      areaRef,
      <String, dynamic>{
        'division': division,
        'area': area,
        'updatedAt': FieldValue.serverTimestamp(),
        'lastMonthKey': monthKey,
        'lastReportDate': dateStr,
      },
      SetOptions(merge: true),
    );

    // 2-2) month 문서(월 단위 1개) + reports 맵에 dateStr 엔트리 추가
    batch.set(
      monthRef,
      <String, dynamic>{
        'division': division,
        'area': area,
        'monthKey': monthKey,
        'updatedAt': FieldValue.serverTimestamp(),
        'lastReportDate': dateStr,
        'reports': <String, dynamic>{
          dateStr: dayPayload,
        },
      },
      SetOptions(merge: true),
    );

    await batch.commit();
  }

  /// 3) plates 삭제 + plate_counters 리셋
  ///
  /// 기존 로직 그대로:
  /// - plates: 조회된 docId들 batch delete
  /// - plate_counters/area_<area>: departureCompletedEvents = 0
  Future<void> cleanupLockedDepartureCompletedPlates({
    required String area,
    required List<String> plateDocIds,
  }) async {
    final batch = _firestore.batch();

    for (final id in plateDocIds) {
      batch.delete(_firestore.collection('plates').doc(id));
    }

    final countersRef = _firestore.collection('plate_counters').doc('area_$area');
    batch.set(
      countersRef,
      <String, dynamic>{
        'departureCompletedEvents': 0,
      },
      SetOptions(merge: true),
    );

    await batch.commit();
  }

  /// 4) Firestore data를 JSON 안전 형태로 변환
  /// (기존 _endReportJsonSafe 로직을 Repository로 이동)
  static dynamic jsonSafe(dynamic v) {
    if (v == null) return null;

    if (v is Timestamp) return v.toDate().toIso8601String();
    if (v is DateTime) return v.toIso8601String();

    if (v is GeoPoint) {
      return <String, dynamic>{
        '_type': 'GeoPoint',
        'lat': v.latitude,
        'lng': v.longitude,
      };
    }

    if (v is DocumentReference) {
      return <String, dynamic>{
        '_type': 'DocumentReference',
        'path': v.path,
      };
    }

    if (v is num || v is String || v is bool) return v;

    if (v is List) return v.map(jsonSafe).toList();
    if (v is Map) {
      return v.map(
            (key, value) => MapEntry(key.toString(), jsonSafe(value)),
      );
    }

    return v.toString();
  }
}
