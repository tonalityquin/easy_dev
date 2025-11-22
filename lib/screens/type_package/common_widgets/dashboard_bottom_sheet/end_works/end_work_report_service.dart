import 'dart:developer' as dev;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

import '../../../../../utils/gcs/gcs_uploader.dart';

dynamic _jsonSafe(dynamic v) {
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

  if (v is List) return v.map(_jsonSafe).toList();
  if (v is Map) {
    return v.map((key, value) => MapEntry(key.toString(), _jsonSafe(value)));
  }

  return v.toString();
}

class EndWorkReportResult {
  final String division;
  final String area;
  final int vehicleInputCount;
  final int vehicleOutputManual;
  final int snapshotLockedVehicleCount;
  final num snapshotTotalLockedFee;

  final bool cleanupOk;
  final bool firestoreSaveOk;
  final bool gcsReportUploadOk;
  final bool gcsLogsUploadOk;

  final String? reportUrl;
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

class EndWorkReportService {
  final FirebaseFirestore _firestore;

  EndWorkReportService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

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
    }

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
    }

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
          'division': division,
          'area': area,
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
    }

    bool cleanupOk = true;
    try {
      dev.log('[END] cleanup plates & plate_counters...',
          name: 'EndWorkReportService');

      final batch = _firestore.batch();

      for (final d in platesSnap.docs) {
        batch.delete(d.reference);
      }

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
