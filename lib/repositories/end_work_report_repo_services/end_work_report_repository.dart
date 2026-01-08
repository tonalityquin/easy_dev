import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

/// Firestore write-only repository for end_work_reports.
/// - No reads (get/query/snapshots) are used.
/// - Upserts are done via set(merge:true) within a single batch commit.
///
/// Schema (as required):
/// end_work_reports/area_<area>
/// end_work_reports/area_<area>/months/<yyyyMM>
///   - reports: { "<yyyy-MM-dd>": { ...dayPayload... }, ... }
class EndWorkReportRepository {
  EndWorkReportRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  /// 1차 종료보고(서버 저장) write-only upsert.
  ///
  /// Writes (atomic batch):
  /// 1) end_work_reports/area_<area>                      (area meta)
  /// 2) end_work_reports/area_<area>/months/<yyyyMM>      (month meta + reports map accumulate)
  ///
  /// Note:
  /// - Firestore reads are forbidden by requirements, so snapshot/derived metrics are saved as 0.
  Future<EndWorkReportWriteResult> upsertFirstEndReport({
    required String area,
    required String division,
    required String uploadedBy,
    required int vehicleInputCount,
    DateTime? nowOverride,
  }) async {
    final now = nowOverride ?? DateTime.now();

    // yyyy-MM-dd (day key)
    final dateStr = DateFormat('yyyy-MM-dd').format(now);

    // yyyyMM (month shard key)
    final monthKey = DateFormat('yyyyMM').format(now);

    final createdAtIso = now.toIso8601String();

    // Requirements: no reads, so derived snapshot metrics must be 0
    const int vehicleOutputManual = 0;
    const int snapshotLockedVehicleCount = 0;
    const int snapshotTotalLockedFee = 0;

    // refs
    final areaRef = _firestore.collection('end_work_reports').doc('area_$area');
    final monthRef = areaRef.collection('months').doc(monthKey);

    // history entry (to be accumulated in history array)
    final historyEntry = <String, dynamic>{
      'date': dateStr,
      'monthKey': monthKey,
      'createdAt': createdAtIso,
      'uploadedBy': uploadedBy,
      'vehicleCount': <String, dynamic>{
        'vehicleInput': vehicleInputCount,
        'vehicleOutput': vehicleOutputManual,
      },
      'metrics': <String, dynamic>{
        'snapshot_lockedVehicleCount': snapshotLockedVehicleCount,
        'snapshot_totalLockedFee': snapshotTotalLockedFee,
      },
    };

    // 1) area meta upsert
    final areaMetaPayload = <String, dynamic>{
      'division': division,
      'area': area,
      'updatedAt': createdAtIso,
      'lastReportDate': dateStr,
      'lastMonthKey': monthKey,
    };

    // 2) day payload (stored inside reports[dateStr])
    final dayPayload = <String, dynamic>{
      'division': division,
      'area': area,
      'date': dateStr,
      'monthKey': monthKey,
      'vehicleCount': <String, dynamic>{
        'vehicleInput': vehicleInputCount,
        'vehicleOutput': vehicleOutputManual,
      },
      'metrics': <String, dynamic>{
        'snapshot_lockedVehicleCount': snapshotLockedVehicleCount,
        'snapshot_totalLockedFee': snapshotTotalLockedFee,
      },
      'createdAt': createdAtIso,
      'uploadedBy': uploadedBy,

      // Accumulate history without reads
      'history': FieldValue.arrayUnion(<Map<String, dynamic>>[historyEntry]),
    };

    // 3) month payload (meta + reports map accumulate)
    final monthPayload = <String, dynamic>{
      'division': division,
      'area': area,
      'monthKey': monthKey,
      'updatedAt': createdAtIso,
      'lastReportDate': dateStr,

      // 핵심: reports map 누적
      'reports': <String, dynamic>{
        dateStr: dayPayload,
      },
    };

    final batch = _firestore.batch();
    batch.set(areaRef, areaMetaPayload, SetOptions(merge: true));
    batch.set(monthRef, monthPayload, SetOptions(merge: true));
    await batch.commit();

    return EndWorkReportWriteResult(
      area: area,
      division: division,
      monthKey: monthKey,
      dateStr: dateStr,
      createdAtIso: createdAtIso,
      vehicleInputCount: vehicleInputCount,
      vehicleOutputCount: vehicleOutputManual,
      snapshotLockedVehicleCount: snapshotLockedVehicleCount,
      snapshotTotalLockedFee: snapshotTotalLockedFee,
      areaDocPath: areaRef.path,
      monthDocPath: monthRef.path,
      reportsFieldPath: 'reports.$dateStr',
    );
  }
}

/// Write result for UI/logging.
class EndWorkReportWriteResult {
  EndWorkReportWriteResult({
    required this.area,
    required this.division,
    required this.monthKey,
    required this.dateStr,
    required this.createdAtIso,
    required this.vehicleInputCount,
    required this.vehicleOutputCount,
    required this.snapshotLockedVehicleCount,
    required this.snapshotTotalLockedFee,
    required this.areaDocPath,
    required this.monthDocPath,
    required this.reportsFieldPath,
  });

  final String area;
  final String division;
  final String monthKey;
  final String dateStr;
  final String createdAtIso;

  final int vehicleInputCount;
  final int vehicleOutputCount;

  final int snapshotLockedVehicleCount;
  final int snapshotTotalLockedFee;

  final String areaDocPath;
  final String monthDocPath;

  /// e.g. "reports.2026-01-03"
  final String reportsFieldPath;
}
