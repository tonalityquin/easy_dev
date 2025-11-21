// lib/services/end_work_report_service.dart
import 'dart:developer' as dev;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

import '../../../../../utils/gcs_uploader.dart';

/// Firestore 특수 타입까지 JSON-safe하게 변환
dynamic _jsonSafe(dynamic v) {
  if (v == null) return null;

  // Firestore Timestamp → ISO8601
  if (v is Timestamp) return v.toDate().toIso8601String();

  // DateTime → ISO8601
  if (v is DateTime) return v.toIso8601String();

  // GeoPoint → 명시적 구조
  if (v is GeoPoint) {
    return <String, dynamic>{
      '_type': 'GeoPoint',
      'lat': v.latitude,
      'lng': v.longitude,
    };
  }

  // DocumentReference → 경로만 보존
  if (v is DocumentReference) {
    return <String, dynamic>{
      '_type': 'DocumentReference',
      'path': v.path,
    };
  }

  // 기본 스칼라
  if (v is num || v is String || v is bool) return v;

  // 리스트/맵 재귀 처리
  if (v is List) return v.map(_jsonSafe).toList();
  if (v is Map) {
    return v.map((key, value) => MapEntry(key.toString(), _jsonSafe(value)));
  }

  // 그 외 알 수 없는 객체는 문자열화(최후의 안전장치)
  return v.toString();
}

class EndWorkReportResult {
  final String division;
  final String area;
  final int vehicleInputCount;
  final int vehicleOutputManual;
  final int snapshotLockedVehicleCount;
  final num snapshotTotalLockedFee;

  /// plates/plate_counters 정리 성공 여부
  final bool cleanupOk;

  /// Firestore(end_work_reports) 저장 성공 여부
  final bool firestoreSaveOk;

  /// GCS 보고 JSON 업로드 성공 여부
  final bool gcsReportUploadOk;

  /// GCS 로그 JSON 업로드 성공 여부
  final bool gcsLogsUploadOk;

  /// GCS 보고 JSON URL (실패 시 null)
  final String? reportUrl;

  /// GCS 로그 JSON URL (실패 시 null)
  final String? logsUrl;

  const EndWorkReportResult({
    required this.division,
    required this.area,
    required this.vehicleInputCount,
    required this.vehicleOutputManual,
    required this.snapshotLockedVehicleCount,
    required this.snapshotTotalLockedFee,
    required this.cleanupOk,
    required this.firestoreSaveOk,
    required this.gcsReportUploadOk,
    required this.gcsLogsUploadOk,
    required this.reportUrl,
    required this.logsUrl,
  });
}

///
/// 업무 종료 보고 제출 전담 서비스
/// - Firestore plates 스냅샷 조회
/// - 잠금요금 합계 계산
/// - GCS 보고/로그 JSON 업로드 (실패해도 계속 진행)
/// - Firestore(end_work_reports)에 "지역별 단일 문서"로 보고 레코드 저장
///   - 문서ID: area_$area
///   - reports.{yyyy-MM-dd} 에 보고 1건 저장
///   - 각 reports.<날짜> 엔트리에는 area/division, gcs*Ok 플래그를 저장하지 않음
/// - plates 스냅샷 정리 + plate_counters 리셋
///
class EndWorkReportService {
  final FirebaseFirestore _firestore;

  EndWorkReportService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  /// 보고 제출
  ///
  /// [division], [area], [userName] 은 현재 컨텍스트 정보를 의미하고
  /// [vehicleInputCount], [vehicleOutputManual] 은 사용자가 입력/확정한 값입니다.
  Future<EndWorkReportResult> submitEndReport({
    required String division,
    required String area,
    required String userName,
    required int vehicleInputCount,
    required int vehicleOutputManual,
  }) async {
    dev.log(
      '[END] submitEndReport start: division=$division, area=$area, user=$userName',
      name: 'EndWorkReportService',
    );

    // 1) plates 스냅샷(출차 완료 + 잠금요금 true)
    QuerySnapshot<Map<String, dynamic>> platesSnap;
    try {
      dev.log('[END] query plates...', name: 'EndWorkReportService');
      platesSnap = await _firestore
          .collection('plates')
          .where('type', isEqualTo: 'departure_completed')
          .where('area', isEqualTo: area)
          .where('isLockedFee', isEqualTo: true)
          .get();
    } catch (e, st) {
      dev.log(
        '[END] plates query failed',
        name: 'EndWorkReportService',
        error: e,
        stackTrace: st,
      );
      throw Exception('출차 스냅샷 조회 실패: $e');
    }

    final int snapshotLockedVehicleCount = platesSnap.docs.length;

    // 2) 잠금요금 합계 계산(스냅샷 기준)
    num snapshotTotalLockedFee = 0;
    try {
      for (final d in platesSnap.docs) {
        final data = d.data();
        num? fee =
        (data['lockedFeeAmount'] is num) ? data['lockedFeeAmount'] as num : null;

        if (fee == null) {
          final logs = data['logs'];
          if (logs is List) {
            for (final log in logs) {
              if (log is Map && log['lockedFee'] is num) {
                fee = log['lockedFee'] as num;
              }
            }
          }
        }

        snapshotTotalLockedFee += (fee ?? 0);
      }
    } catch (e, st) {
      dev.log(
        '[END] fee sum failed',
        name: 'EndWorkReportService',
        error: e,
        stackTrace: st,
      );
      throw Exception('요금 합계 계산 실패: $e');
    }

    // 3) 보고 JSON 생성 (요약 정보)
    final now = DateTime.now();
    final dateStr = DateFormat('yyyy-MM-dd').format(now);

    final reportLog = <String, dynamic>{
      'division': division,
      'area': area,
      'vehicleCount': <String, dynamic>{
        'vehicleInput': vehicleInputCount,
        'vehicleOutput': vehicleOutputManual,
      },
      'metrics': <String, dynamic>{
        'snapshot_lockedVehicleCount': snapshotLockedVehicleCount,
        'snapshot_totalLockedFee': snapshotTotalLockedFee,
      },
      'createdAt': now.toIso8601String(),
      'uploadedBy': userName,
    };

    // 4) 보고 JSON GCS 업로드 (실패해도 throw 하지 않고 플래그만 세팅)
    String? reportUrl;
    bool gcsReportUploadOk = true;
    try {
      dev.log('[END] upload report...', name: 'EndWorkReportService');
      reportUrl = await uploadEndWorkReportJson(
        report: reportLog,
        division: division,
        area: area,
        userName: userName,
      );
      if (reportUrl == null) {
        gcsReportUploadOk = false;
        dev.log(
          '[END] upload report returned null',
          name: 'EndWorkReportService',
        );
      }
    } catch (e, st) {
      gcsReportUploadOk = false;
      dev.log(
        '[END] upload report exception',
        name: 'EndWorkReportService',
        error: e,
        stackTrace: st,
      );
      // 예외를 던지지 않음 → Firestore 요약 저장은 계속 진행
    }

    // 5) 로그 JSON GCS 업로드 (실패해도 throw 하지 않음)
    String? logsUrl;
    bool gcsLogsUploadOk = true;
    try {
      dev.log('[END] upload logs...', name: 'EndWorkReportService');
      final items = <Map<String, dynamic>>[
        for (final d in platesSnap.docs)
          <String, dynamic>{
            'docId': d.id,
            'data': _jsonSafe(d.data()),
          },
      ];

      logsUrl = await uploadEndLogJson(
        report: <String, dynamic>{
          'division': division,
          'area': area,
          'items': items,
        },
        division: division,
        area: area,
        userName: userName,
      );
      if (logsUrl == null) {
        gcsLogsUploadOk = false;
        dev.log(
          '[END] upload logs returned null',
          name: 'EndWorkReportService',
        );
      }
    } catch (e, st) {
      gcsLogsUploadOk = false;
      dev.log(
        '[END] upload logs exception',
        name: 'EndWorkReportService',
        error: e,
        stackTrace: st,
      );
      // 마찬가지로 예외로 올리지 않음
    }

    // 6) Firestore(end_work_reports)에 "지역별 단일 문서"로 보고 레코드 저장
    //    - 문서 ID: area_$area
    //    - reports.{yyyy-MM-dd} 에 한 건씩 저장
    //    - 각 reports.<날짜> 엔트리에는 area/division, gcsReportUploadOk, gcsLogsUploadOk 를 저장하지 않음
    bool firestoreSaveOk = true;
    try {
      dev.log('[END] save report to Firestore (per-area doc)...',
          name: 'EndWorkReportService');

      final docRef =
      _firestore.collection('end_work_reports').doc('area_$area');

      final reportEntry = <String, dynamic>{
        'date': dateStr,
        'vehicleCount': reportLog['vehicleCount'],
        'metrics': reportLog['metrics'],
        'createdAt': reportLog['createdAt'],
        'uploadedBy': reportLog['uploadedBy'],
        if (reportUrl != null) 'reportUrl': reportUrl,
        if (logsUrl != null) 'logsUrl': logsUrl,
      };

      await docRef.set(
        {
          // 문서 메타(필요 없다면 이것도 나중에 제거 가능)
          'division': division,
          'area': area,
          // nested map: reports.2025-11-19 = reportEntry
          'reports.$dateStr': reportEntry,
        },
        SetOptions(merge: true),
      );
    } catch (e, st) {
      firestoreSaveOk = false;
      dev.log(
        '[END] Firestore save failed (end_work_reports area doc)',
        name: 'EndWorkReportService',
        error: e,
        stackTrace: st,
      );
      // 여기서도 예외는 밖으로 던지지 않고 플래그만 false 로
    }

    // 7) plates 스냅샷 정리 + plate_counters 리셋 — 실패해도 전체 플로우는 성공으로 간주
    bool cleanupOk = true;
    try {
      dev.log('[END] cleanup plates & plate_counters...',
          name: 'EndWorkReportService');

      final batch = _firestore.batch();

      // 7-1) plates 스냅샷 정리
      for (final d in platesSnap.docs) {
        batch.delete(d.reference);
      }

      // 7-2) plate_counters 해당 area 문서의 departureCompletedEvents를 0으로 리셋
      final countersRef =
      _firestore.collection('plate_counters').doc('area_$area');
      batch.set(
        countersRef,
        {
          'departureCompletedEvents': 0,
        },
        SetOptions(merge: true),
      );

      await batch.commit();
    } catch (e, st) {
      cleanupOk = false;
      dev.log(
        '[END] cleanup failed',
        name: 'EndWorkReportService',
        error: e,
        stackTrace: st,
      );
    }

    dev.log('[END] submitEndReport done', name: 'EndWorkReportService');

    return EndWorkReportResult(
      division: division,
      area: area,
      vehicleInputCount: vehicleInputCount,
      vehicleOutputManual: vehicleOutputManual,
      snapshotLockedVehicleCount: snapshotLockedVehicleCount,
      snapshotTotalLockedFee: snapshotTotalLockedFee,
      cleanupOk: cleanupOk,
      firestoreSaveOk: firestoreSaveOk,
      gcsReportUploadOk: gcsReportUploadOk,
      gcsLogsUploadOk: gcsLogsUploadOk,
      reportUrl: reportUrl,
      logsUrl: logsUrl,
    );
  }
}
