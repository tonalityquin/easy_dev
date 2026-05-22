import 'dart:developer' as dev;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

class EndWorkReportRepository {
  EndWorkReportRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  Future<EndWorkReportWriteResult> upsertFirstEndReport({
    required String area,
    required String division,
    required String uploadedBy,
    required int vehicleOutputCount,
    DateTime? nowOverride,
  }) async {
    final now = nowOverride ?? DateTime.now();
    final dateStr = DateFormat('yyyy-MM-dd').format(now);
    final monthKey = DateFormat('yyyyMM').format(now);
    final createdAtIso = now.toIso8601String();

    const int snapshotLockedVehicleCount = 0;
    const int snapshotTotalLockedFee = 0;

    final areaRef = _firestore.collection('end_work_reports').doc('area_$area');
    final monthRef = areaRef.collection('months').doc(monthKey);

    final historyEntry = <String, dynamic>{
      'date': dateStr,
      'monthKey': monthKey,
      'createdAt': createdAtIso,
      'uploadedBy': uploadedBy,
      'vehicleCount': <String, dynamic>{
        'vehicleOutput': vehicleOutputCount,
      },
      'metrics': <String, dynamic>{
        'snapshot_lockedVehicleCount': snapshotLockedVehicleCount,
        'snapshot_totalLockedFee': snapshotTotalLockedFee,
      },
    };

    final areaMetaPayload = <String, dynamic>{
      'division': division,
      'area': area,
      'updatedAt': createdAtIso,
      'lastReportDate': dateStr,
      'lastMonthKey': monthKey,
    };

    final dayPayload = <String, dynamic>{
      'division': division,
      'area': area,
      'date': dateStr,
      'monthKey': monthKey,
      'vehicleCount': <String, dynamic>{
        'vehicleOutput': vehicleOutputCount,
      },
      'metrics': <String, dynamic>{
        'snapshot_lockedVehicleCount': snapshotLockedVehicleCount,
        'snapshot_totalLockedFee': snapshotTotalLockedFee,
      },
      'createdAt': createdAtIso,
      'uploadedBy': uploadedBy,
      'history': FieldValue.arrayUnion(<Map<String, dynamic>>[historyEntry]),
    };

    final monthPayload = <String, dynamic>{
      'division': division,
      'area': area,
      'monthKey': monthKey,
      'updatedAt': createdAtIso,
      'lastReportDate': dateStr,
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
      vehicleOutputCount: vehicleOutputCount,
      snapshotLockedVehicleCount: snapshotLockedVehicleCount,
      snapshotTotalLockedFee: snapshotTotalLockedFee,
      areaDocPath: areaRef.path,
      monthDocPath: monthRef.path,
      reportsFieldPath: 'reports.$dateStr',
    );
  }

  Future<Map<String, Map<String, Map<String, dynamic>>>> buildAreaDateCache({
    required String division,
  }) async {
    final rebuilt = <String, Map<String, Map<String, dynamic>>>{};
    final bestAt = <String, Map<String, DateTime>>{};

    try {
      Query<Map<String, dynamic>> q = _firestore.collectionGroup('months');
      if (division.isNotEmpty) {
        q = q.where('division', isEqualTo: division);
      }

      final snap = await q.get();
      for (final monthDoc in snap.docs) {
        _mergeOneMonthDocIntoCache(
          rebuilt: rebuilt,
          bestAt: bestAt,
          division: division,
          monthDoc: monthDoc,
        );
      }

      dev.log('[STAT] new schema: collectionGroup(months) docs=${snap.size}',
          name: 'EndWorkReportRepository');
    } catch (e, st) {
      dev.log(
        '[STAT] collectionGroup(months) failed -> fallback hierarchical scan. error=$e',
        name: 'EndWorkReportRepository',
        error: e,
        stackTrace: st,
      );

      await _appendMonthsByHierarchicalScan(
        division: division,
        rebuilt: rebuilt,
        bestAt: bestAt,
      );
    }

    await _appendLegacyEmbeddedReports(
      division: division,
      rebuilt: rebuilt,
      bestAt: bestAt,
    );

    return rebuilt;
  }

  Map<String, dynamic>? _asMap(Object? value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) {
      return value.map((k, v) => MapEntry(k.toString(), v));
    }
    return null;
  }

  int? _asInt(dynamic v) {
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v);
    return null;
  }

  DateTime? _tryParseDateTimeAny(dynamic v) {
    if (v == null) return null;
    if (v is Timestamp) return v.toDate().toLocal();
    if (v is int) return DateTime.fromMillisecondsSinceEpoch(v).toLocal();
    if (v is String) {
      final s = v.trim();
      if (s.isEmpty) return null;
      return DateTime.tryParse(s)?.toLocal();
    }
    final m = _asMap(v);
    if (m != null && m.containsKey('seconds')) {
      final sec = _asInt(m['seconds']) ?? 0;
      final nano = _asInt(m['nanoseconds']) ?? 0;
      final ms = (sec * 1000) + (nano ~/ 1000000);
      return DateTime.fromMillisecondsSinceEpoch(ms).toLocal();
    }
    return null;
  }

  DateTime? _tryParseCreatedAt(Map<String, dynamic> day) {
    return _tryParseDateTimeAny(day['createdAt']);
  }

  void _mergeOneMonthDocIntoCache({
    required Map<String, Map<String, Map<String, dynamic>>> rebuilt,
    required Map<String, Map<String, DateTime>> bestAt,
    required String division,
    required QueryDocumentSnapshot<Map<String, dynamic>> monthDoc,
  }) {
    final data = monthDoc.data();

    final area = (data['area']?.toString().trim().isNotEmpty == true)
        ? data['area']!.toString().trim()
        : _inferAreaFromMonthDocRef(monthDoc).trim();
    if (area.isEmpty) return;

    final monthKey = (data['monthKey']?.toString().trim().isNotEmpty == true)
        ? data['monthKey']!.toString().trim()
        : monthDoc.id.trim();

    final reportsMap = _asMap(data['reports']);
    if (reportsMap == null || reportsMap.isEmpty) return;

    final monthPath = monthDoc.reference.path;

    for (final entry in reportsMap.entries) {
      final dateStr = entry.key.toString().trim();
      if (dateStr.isEmpty) continue;

      final dayMap = _asMap(entry.value);
      if (dayMap == null) continue;

      final day = Map<String, dynamic>.from(dayMap);
      _applyLatestHistoryIfAny(day);
      day['date'] = day['date'] ?? dateStr;
      day['area'] = day['area'] ?? area;
      day['division'] = day['division'] ?? (division.isNotEmpty ? division : null);
      day['monthKey'] = day['monthKey'] ?? (monthKey.isNotEmpty ? monthKey : null);
      day['_monthDocPath'] = monthPath;
      day['_docPath'] = '$monthPath::reports.$dateStr';

      final at = _tryParseCreatedAt(day) ?? DateTime.fromMillisecondsSinceEpoch(0);

      bestAt.putIfAbsent(area, () => <String, DateTime>{});
      rebuilt.putIfAbsent(area, () => <String, Map<String, dynamic>>{});

      final prevAt = bestAt[area]![dateStr];
      if (prevAt == null || at.isAfter(prevAt)) {
        bestAt[area]![dateStr] = at;
        rebuilt[area]![dateStr] = day;
      }
    }
  }

  String _inferAreaFromMonthDocRef(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    try {
      final areaDoc = doc.reference.parent.parent;
      final areaDocId = areaDoc?.id ?? '';
      return _areaFromAreaDocId(areaDocId);
    } catch (_) {
      return '';
    }
  }

  String _areaFromAreaDocId(String id) {
    final s = id.trim();
    if (s.startsWith('area_') && s.length > 5) return s.substring(5).trim();
    return s;
  }

  Future<void> _appendMonthsByHierarchicalScan({
    required String division,
    required Map<String, Map<String, Map<String, dynamic>>> rebuilt,
    required Map<String, Map<String, DateTime>> bestAt,
  }) async {
    Query<Map<String, dynamic>> qAreas = _firestore.collection('end_work_reports');
    if (division.isNotEmpty) {
      qAreas = qAreas.where('division', isEqualTo: division);
    }

    final areaSnap = await qAreas.get();
    dev.log('[STAT] fallback scan: areaDocs=${areaSnap.size}', name: 'EndWorkReportRepository');

    for (final areaDoc in areaSnap.docs) {
      final monthsSnap = await areaDoc.reference.collection('months').get();
      for (final monthDoc in monthsSnap.docs) {
        _mergeOneMonthDocIntoCache(
          rebuilt: rebuilt,
          bestAt: bestAt,
          division: division,
          monthDoc: monthDoc,
        );
      }
    }
  }

  Future<void> _appendLegacyEmbeddedReports({
    required String division,
    required Map<String, Map<String, Map<String, dynamic>>> rebuilt,
    required Map<String, Map<String, DateTime>> bestAt,
  }) async {
    Query<Map<String, dynamic>> q = _firestore.collection('end_work_reports');
    if (division.isNotEmpty) {
      q = q.where('division', isEqualTo: division);
    }

    final snap = await q.get();
    dev.log('[STAT] legacy scan: areaDocs=${snap.size}', name: 'EndWorkReportRepository');

    for (final doc in snap.docs) {
      final data = doc.data();
      final area = (data['area']?.toString().trim().isNotEmpty == true)
          ? data['area']!.toString().trim()
          : _tryParseAreaFromDocId(doc.id).trim();
      if (area.isEmpty) continue;

      final extracted = _extractAllDaysFromLegacyAreaDoc(docId: doc.id, data: data);
      if (extracted.isEmpty) continue;

      for (final e in extracted.entries) {
        final dateStr = e.key;
        final day = e.value;
        final at = _tryParseCreatedAt(day) ?? DateTime.fromMillisecondsSinceEpoch(0);

        bestAt.putIfAbsent(area, () => <String, DateTime>{});
        rebuilt.putIfAbsent(area, () => <String, Map<String, dynamic>>{});

        final prevAt = bestAt[area]![dateStr];
        if (prevAt == null || at.isAfter(prevAt)) {
          bestAt[area]![dateStr] = at;
          rebuilt[area]![dateStr] = day;
        }
      }
    }
  }

  Map<String, Map<String, dynamic>> _extractAllDaysFromLegacyAreaDoc({
    required String docId,
    required Map<String, dynamic> data,
  }) {
    final reportsMap = _asMap(data['reports']);
    if (reportsMap != null) {
      final out = <String, Map<String, dynamic>>{};
      for (final entry in reportsMap.entries) {
        final dateStr = entry.key.toString();
        final dayMap = _asMap(entry.value);
        if (dayMap == null) continue;

        final day = Map<String, dynamic>.from(dayMap);
        _applyLatestHistoryIfAny(day);
        day['date'] = day['date'] ?? dateStr;
        day['company'] = day['company'] ?? data['company'] ?? data['division'];
        day['division'] = day['division'] ?? data['division'] ?? data['company'];
        day['area'] = day['area'] ?? data['area'] ?? _tryParseAreaFromDocId(docId);
        day['_docId'] = docId;
        out[dateStr] = day;
      }
      if (out.isNotEmpty) return out;
    }

    final out = <String, Map<String, dynamic>>{};

    void ensure(String dateStr) {
      out.putIfAbsent(dateStr, () => <String, dynamic>{});
    }

    for (final entry in data.entries) {
      final k = entry.key.toString();
      if (!k.startsWith('reports.')) continue;

      final rest = k.substring('reports.'.length);
      final firstDot = rest.indexOf('.');

      if (firstDot <= 0) {
        final dateStr = rest.trim();
        if (dateStr.isEmpty) continue;
        ensure(dateStr);
        final m = _asMap(entry.value);
        if (m != null) {
          out[dateStr]!.addAll(m);
        } else {
          out[dateStr]!['_value'] = entry.value;
        }
        continue;
      }

      final dateStr = rest.substring(0, firstDot).trim();
      final path = rest.substring(firstDot + 1).trim();
      if (dateStr.isEmpty || path.isEmpty) continue;
      ensure(dateStr);
      _putByDotPath(out[dateStr]!, path, entry.value);
    }

    for (final dateEntry in out.entries) {
      final dateStr = dateEntry.key;
      final day = dateEntry.value;
      _applyLatestHistoryIfAny(day);
      day['date'] = day['date'] ?? dateStr;
      day['company'] = day['company'] ?? data['company'] ?? data['division'];
      day['division'] = day['division'] ?? data['division'] ?? data['company'];
      day['area'] = day['area'] ?? data['area'] ?? _tryParseAreaFromDocId(docId);
      day['_docId'] = docId;
    }

    if (out.isEmpty) {
      final sampleKeys = data.keys.take(40).toList();
      dev.log('[STAT] legacy doc=$docId no reports. keys(sample)=$sampleKeys', name: 'EndWorkReportRepository');
    }

    return out;
  }

  void _putByDotPath(Map<String, dynamic> root, String path, dynamic value) {
    final parts = path.split('.');
    Map<String, dynamic> cur = root;
    for (int i = 0; i < parts.length; i++) {
      final key = parts[i];
      final isLast = i == parts.length - 1;
      if (isLast) {
        cur[key] = value;
        return;
      }
      final next = cur[key];
      final nextMap = _asMap(next);
      if (nextMap != null) {
        cur[key] = nextMap;
        cur = nextMap;
      } else {
        final created = <String, dynamic>{};
        cur[key] = created;
        cur = created;
      }
    }
  }

  void _applyLatestHistoryIfAny(Map<String, dynamic> day) {
    final historyRaw = day['history'];
    if (historyRaw is List && historyRaw.isNotEmpty) {
      Map<String, dynamic>? latest;
      var latestAt = DateTime.fromMillisecondsSinceEpoch(0);
      for (final item in historyRaw) {
        final m = _asMap(item);
        if (m == null) continue;
        final dt = _tryParseDateTimeAny(m['createdAt']) ?? DateTime.fromMillisecondsSinceEpoch(0);
        if (dt.isAfter(latestAt)) {
          latestAt = dt;
          latest = m;
        }
      }
      if (latest != null) {
        day['vehicleCount'] = latest['vehicleCount'] ?? day['vehicleCount'];
        day['metrics'] = latest['metrics'] ?? day['metrics'];
        day['createdAt'] = latest['createdAt'] ?? day['createdAt'];
        day['uploadedBy'] = latest['uploadedBy'] ?? day['uploadedBy'];
        day['reportUrl'] = latest['reportUrl'] ?? day['reportUrl'];
        day['logsUrl'] = latest['logsUrl'] ?? day['logsUrl'];
        day['date'] = latest['date'] ?? day['date'];
        day['monthKey'] = latest['monthKey'] ?? day['monthKey'];
        day['division'] = latest['division'] ?? day['division'];
        day['area'] = latest['area'] ?? day['area'];
      }
    }
  }

  String _tryParseAreaFromDocId(String docId) {
    final idx = docId.indexOf('_area_');
    if (idx >= 0 && idx + 6 < docId.length) {
      return docId.substring(idx + 6).trim();
    }
    if (docId.startsWith('area_') && docId.length > 5) {
      return docId.substring(5).trim();
    }
    return '';
  }
}

class EndWorkReportWriteResult {
  EndWorkReportWriteResult({
    required this.area,
    required this.division,
    required this.monthKey,
    required this.dateStr,
    required this.createdAtIso,
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
  final int vehicleOutputCount;
  final int snapshotLockedVehicleCount;
  final int snapshotTotalLockedFee;
  final String areaDocPath;
  final String monthDocPath;
  final String reportsFieldPath;
}
