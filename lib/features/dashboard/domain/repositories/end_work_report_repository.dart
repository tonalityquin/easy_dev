import 'dart:developer' as dev;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

import '../models/end_work_report_history_type.dart';
import '../models/end_work_sector_metrics.dart';

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
      'reportType': EndWorkReportHistoryTypes.firstEndReport,
      'gcsLogVerified': false,
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
      'reportType': EndWorkReportHistoryTypes.firstEndReport,
      'gcsLogVerified': false,
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
      _applyAggregatedHistoryIfAny(day);
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
        _applyAggregatedHistoryIfAny(day);
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
      _applyAggregatedHistoryIfAny(day);
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

  void _applyAggregatedHistoryIfAny(Map<String, dynamic> day) {
    final historyRaw = day['history'];
    if (historyRaw is! List || historyRaw.isEmpty) {
      _applyStandaloneDayMetadata(day);
      return;
    }

    final history = <Map<String, dynamic>>[];
    for (final item in historyRaw) {
      final map = _asMap(item);
      if (map != null) {
        history.add(Map<String, dynamic>.from(map));
      }
    }
    if (history.isEmpty) return;

    history.sort((a, b) {
      final aAt = _tryParseDateTimeAny(a['createdAt']) ??
          DateTime.fromMillisecondsSinceEpoch(0);
      final bAt = _tryParseDateTimeAny(b['createdAt']) ??
          DateTime.fromMillisecondsSinceEpoch(0);
      return aAt.compareTo(bAt);
    });

    final detailedHistory = history
        .where(_isDetailedGcsHistoryEntry)
        .toList(growable: false);
    final firstHistory = history
        .where(_isFirstHistoryEntry)
        .toList(growable: false);
    final unverifiedDetailedCount = history
        .where(_isUnverifiedDetailedHistoryEntry)
        .length;
    final legacyDetailedCount = detailedHistory
        .where((entry) => _historyReportType(entry).isEmpty)
        .length;

    if (detailedHistory.isEmpty) {
      final fallback = firstHistory.isNotEmpty ? firstHistory.last : history.last;
      _applyNonGcsFallback(
        day: day,
        fallback: fallback,
        totalHistoryCount: history.length,
        firstHistoryCount: firstHistory.length,
        unverifiedDetailedCount: unverifiedDetailedCount,
      );
      return;
    }

    final latest = detailedHistory.last;
    var vehicleOutput = 0;
    var snapshotLockedVehicleCount = 0;
    num snapshotTotalLockedFee = 0;
    var vehicleOutputFound = false;
    var lockedVehicleCountFound = false;
    var lockedFeeFound = false;
    final sectorMetrics = <EndWorkSectorMetrics>[];
    final logsUrls = <String>[];

    for (final entry in detailedHistory) {
      final vehicleCount = _asMap(entry['vehicleCount']);
      final vehicleOutputValue = _asInt(vehicleCount?['vehicleOutput']);
      if (vehicleOutputValue != null) {
        vehicleOutput += vehicleOutputValue;
        vehicleOutputFound = true;
      }

      final metrics = _asMap(entry['metrics']);
      final lockedVehicleValue =
          _asInt(metrics?['snapshot_lockedVehicleCount']);
      if (lockedVehicleValue != null) {
        snapshotLockedVehicleCount += lockedVehicleValue;
        lockedVehicleCountFound = true;
      }

      final lockedFeeValue = _asNum(metrics?['snapshot_totalLockedFee']);
      if (lockedFeeValue != null) {
        snapshotTotalLockedFee += lockedFeeValue;
        lockedFeeFound = true;
      }

      final sector = EndWorkSectorMetrics.fromDynamic(metrics?['sector']);
      if (sector != null && sector.enabled) {
        sectorMetrics.add(sector);
      }

      final logsUrl = _historyLogsUrl(entry);
      if (logsUrl.isNotEmpty && !logsUrls.contains(logsUrl)) {
        logsUrls.add(logsUrl);
      }
    }

    final mergedVehicleCount =
        Map<String, dynamic>.from(_asMap(latest['vehicleCount']) ?? const {});
    if (vehicleOutputFound) {
      mergedVehicleCount['vehicleOutput'] = vehicleOutput;
    }

    final mergedMetrics =
        Map<String, dynamic>.from(_asMap(latest['metrics']) ?? const {});
    if (lockedVehicleCountFound) {
      mergedMetrics['snapshot_lockedVehicleCount'] =
          snapshotLockedVehicleCount;
    }
    if (lockedFeeFound) {
      mergedMetrics['snapshot_totalLockedFee'] = snapshotTotalLockedFee;
    }
    if (sectorMetrics.isNotEmpty) {
      mergedMetrics['sector'] = EndWorkSectorMetrics.merge(sectorMetrics).toMap();
    } else {
      mergedMetrics.remove('sector');
    }

    day['vehicleCount'] = mergedVehicleCount;
    day['metrics'] = mergedMetrics;
    day['reportType'] = EndWorkReportHistoryTypes.detailedGcsEndReport;
    day['gcsLogVerified'] = true;
    day['_statisticsEligible'] = true;
    day['createdAt'] = latest['createdAt'] ?? day['createdAt'];
    day['uploadedBy'] = latest['uploadedBy'] ?? day['uploadedBy'];
    day['reportUrl'] = latest['reportUrl'] ?? day['reportUrl'];
    day['logsUrl'] = latest['logsUrl'] ?? day['logsUrl'];
    day['date'] = latest['date'] ?? day['date'];
    day['monthKey'] = latest['monthKey'] ?? day['monthKey'];
    day['division'] = latest['division'] ?? day['division'];
    day['area'] = latest['area'] ?? day['area'];
    day['_historyEntryCount'] = history.length;
    day['_historyDetailedEntryCount'] = detailedHistory.length;
    day['_historyExcludedEntryCount'] = history.length - detailedHistory.length;
    day['_historyFirstEntryCount'] = firstHistory.length;
    day['_historyUnverifiedDetailedEntryCount'] = unverifiedDetailedCount;
    day['_historyLegacyDetailedEntryCount'] = legacyDetailedCount;
    day['_historyAggregationMode'] = 'detailedGcsAggregate';
    day['_historyAggregated'] = detailedHistory.length > 1;
    day['_historyLogsUrls'] = logsUrls;
    day['_historyVehicleOutput'] = vehicleOutputFound ? vehicleOutput : null;
    day['_historyLockedVehicleCount'] =
        lockedVehicleCountFound ? snapshotLockedVehicleCount : null;
    day['_historyLockedFee'] =
        lockedFeeFound ? snapshotTotalLockedFee : null;
    day['_historySectorEntryCount'] = sectorMetrics.length;
  }

  void _applyStandaloneDayMetadata(Map<String, dynamic> day) {
    final entry = Map<String, dynamic>.from(day);
    final isDetailed = _isDetailedGcsHistoryEntry(entry);
    final isFirst = _isFirstHistoryEntry(entry);
    final unverifiedDetailed = _isUnverifiedDetailedHistoryEntry(entry);
    final logsUrl = isDetailed ? _historyLogsUrl(entry) : '';
    final metrics =
        Map<String, dynamic>.from(_asMap(day['metrics']) ?? const {});
    final sector = EndWorkSectorMetrics.fromDynamic(metrics['sector']);

    if (isDetailed) {
      day['reportType'] = EndWorkReportHistoryTypes.detailedGcsEndReport;
      day['gcsLogVerified'] = true;
      day['_statisticsEligible'] = true;
    } else {
      day['_statisticsEligible'] = false;
      metrics.remove('sector');
      day['metrics'] = metrics;
      if (_historyReportType(entry).isEmpty) {
        day['reportType'] = EndWorkReportHistoryTypes.firstEndReport;
      }
      day['gcsLogVerified'] = false;
      day.remove('logsUrl');
    }

    day['_historyEntryCount'] = 1;
    day['_historyDetailedEntryCount'] = isDetailed ? 1 : 0;
    day['_historyExcludedEntryCount'] = isDetailed ? 0 : 1;
    day['_historyFirstEntryCount'] = isFirst ? 1 : 0;
    day['_historyUnverifiedDetailedEntryCount'] = unverifiedDetailed ? 1 : 0;
    day['_historyLegacyDetailedEntryCount'] =
        isDetailed && _historyReportType(entry).isEmpty ? 1 : 0;
    day['_historyAggregationMode'] =
        isDetailed ? 'standaloneDetailedGcs' : 'nonGcsFallback';
    day['_historyAggregated'] = false;
    day['_historyLogsUrls'] =
        logsUrl.isEmpty ? const <String>[] : <String>[logsUrl];
    day['_historyVehicleOutput'] =
        _asInt(_asMap(day['vehicleCount'])?['vehicleOutput']);
    day['_historyLockedVehicleCount'] =
        _asInt(metrics['snapshot_lockedVehicleCount']);
    day['_historyLockedFee'] = _asNum(metrics['snapshot_totalLockedFee']);
    day['_historySectorEntryCount'] =
        isDetailed && sector != null && sector.enabled ? 1 : 0;
  }

  void _applyNonGcsFallback({
    required Map<String, dynamic> day,
    required Map<String, dynamic> fallback,
    required int totalHistoryCount,
    required int firstHistoryCount,
    required int unverifiedDetailedCount,
  }) {
    final vehicleCount =
        Map<String, dynamic>.from(_asMap(fallback['vehicleCount']) ?? const {});
    final metrics =
        Map<String, dynamic>.from(_asMap(fallback['metrics']) ?? const {});
    metrics.remove('sector');

    day['vehicleCount'] = vehicleCount;
    day['metrics'] = metrics;
    day['reportType'] = _historyReportType(fallback).isEmpty
        ? EndWorkReportHistoryTypes.firstEndReport
        : _historyReportType(fallback);
    day['gcsLogVerified'] = false;
    day['_statisticsEligible'] = false;
    day['createdAt'] = fallback['createdAt'] ?? day['createdAt'];
    day['uploadedBy'] = fallback['uploadedBy'] ?? day['uploadedBy'];
    day['reportUrl'] = fallback['reportUrl'] ?? day['reportUrl'];
    day.remove('logsUrl');
    day['date'] = fallback['date'] ?? day['date'];
    day['monthKey'] = fallback['monthKey'] ?? day['monthKey'];
    day['division'] = fallback['division'] ?? day['division'];
    day['area'] = fallback['area'] ?? day['area'];
    day['_historyEntryCount'] = totalHistoryCount;
    day['_historyDetailedEntryCount'] = 0;
    day['_historyExcludedEntryCount'] = totalHistoryCount;
    day['_historyFirstEntryCount'] = firstHistoryCount;
    day['_historyUnverifiedDetailedEntryCount'] = unverifiedDetailedCount;
    day['_historyLegacyDetailedEntryCount'] = 0;
    day['_historyAggregationMode'] = 'nonGcsFallback';
    day['_historyAggregated'] = false;
    day['_historyLogsUrls'] = const <String>[];
    day['_historyVehicleOutput'] = _asInt(vehicleCount['vehicleOutput']);
    day['_historyLockedVehicleCount'] =
        _asInt(metrics['snapshot_lockedVehicleCount']);
    day['_historyLockedFee'] = _asNum(metrics['snapshot_totalLockedFee']);
    day['_historySectorEntryCount'] = 0;
  }

  bool _isDetailedGcsHistoryEntry(Map<String, dynamic> entry) {
    final type = _historyReportType(entry);
    final logsUrl = _historyLogsUrl(entry);
    if (type == EndWorkReportHistoryTypes.firstEndReport) return false;
    if (type == EndWorkReportHistoryTypes.detailedGcsEndReport) {
      if (logsUrl.isEmpty) return false;
      return entry['gcsLogVerified'] == true;
    }
    if (type.isNotEmpty) return false;
    return logsUrl.isNotEmpty;
  }

  bool _isFirstHistoryEntry(Map<String, dynamic> entry) {
    return _historyReportType(entry) ==
        EndWorkReportHistoryTypes.firstEndReport;
  }

  bool _isUnverifiedDetailedHistoryEntry(Map<String, dynamic> entry) {
    if (_historyReportType(entry) !=
        EndWorkReportHistoryTypes.detailedGcsEndReport) {
      return false;
    }
    final logsUrl = _historyLogsUrl(entry);
    return logsUrl.isEmpty || entry['gcsLogVerified'] != true;
  }

  String _historyReportType(Map<String, dynamic> entry) {
    return entry['reportType']?.toString().trim() ?? '';
  }

  String _historyLogsUrl(Map<String, dynamic> entry) {
    return entry['logsUrl']?.toString().trim() ?? '';
  }

  num? _asNum(dynamic value) {
    if (value is num) return value;
    if (value is String) {
      return num.tryParse(value.replaceAll(',', '').trim());
    }
    return null;
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
