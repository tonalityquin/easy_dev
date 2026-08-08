import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:googleapis/storage/v1.dart' as gcs;

import '../../../../app/auth/google_auth_v7.dart';
import '../../../../app/config/auth_config.dart';
import 'statistics_deep_model.dart';

class StatisticsDeepLogService {
  final String bucketName;

  StatisticsDeepLogService({String? bucketName})
      : bucketName = bucketName ?? AuthConfig.gcsBucketName;

  Future<StatisticsDeepReport> loadByDate({
    required String division,
    required String area,
    required DateTime date,
    bool sectorEnabled = false,
  }) {
    return loadByDates(
      division: division,
      area: area,
      dates: <DateTime>[date],
      scopeLabel: _yyyymmdd(DateTime(date.year, date.month, date.day)),
      sectorEnabled: sectorEnabled,
    );
  }

  Future<StatisticsDeepReport> loadByDateRange({
    required String division,
    required String area,
    required DateTime start,
    required DateTime end,
    bool sectorEnabled = false,
  }) {
    final normalizedStart = _normalizeDate(start);
    final normalizedEnd = _normalizeDate(end);
    final a = normalizedStart.isAfter(normalizedEnd) ? normalizedEnd : normalizedStart;
    final b = normalizedStart.isAfter(normalizedEnd) ? normalizedStart : normalizedEnd;
    final dates = <DateTime>[];
    var cursor = a;
    while (!cursor.isAfter(b)) {
      dates.add(cursor);
      cursor = cursor.add(const Duration(days: 1));
    }

    return loadByDates(
      division: division,
      area: area,
      dates: dates,
      scopeLabel: '${_yyyymmdd(a)} ~ ${_yyyymmdd(b)}',
      sectorEnabled: sectorEnabled,
    );
  }

  Future<StatisticsDeepReport> loadByDates({
    required String division,
    required String area,
    required List<DateTime> dates,
    String? scopeLabel,
    bool sectorEnabled = false,
  }) async {
    final trimmedDivision = division.trim();
    final trimmedArea = area.trim();
    debugPrint('[STAT_DEEP] load start division=$trimmedDivision area=$trimmedArea dates=${dates.length} sectorEnabled=$sectorEnabled');

    if (trimmedDivision.isEmpty || trimmedArea.isEmpty) {
      throw StateError('사업부와 지역 정보가 필요합니다.');
    }

    final normalizedDates = dates
        .map(_normalizeDate)
        .toSet()
        .toList()
      ..sort((a, b) => a.compareTo(b));

    if (normalizedDates.isEmpty) {
      throw StateError('심화 통계를 불러올 날짜가 없습니다.');
    }

    final dateStrs = normalizedDates.map(_yyyymmdd).toSet();
    final monthKeys = normalizedDates.map(_yyyymm).toSet().toList()..sort();
    final label = scopeLabel?.trim().isNotEmpty == true
        ? scopeLabel!.trim()
        : normalizedDates.length == 1
            ? _yyyymmdd(normalizedDates.first)
            : '${_yyyymmdd(normalizedDates.first)} ~ ${_yyyymmdd(normalizedDates.last)}';

    final client = await GoogleAuthV7.authedClient(
      [gcs.StorageApi.devstorageReadOnlyScope],
    );

    try {
      final storage = gcs.StorageApi(client);
      final allNames = <String>{};

      for (final monthKey in monthKeys) {
        final monthPrefix = '$trimmedDivision/$trimmedArea/logs/$monthKey/';
        allNames.addAll(
          await _listAllObjects(
            storage: storage,
            prefix: monthPrefix,
          ),
        );
      }

      var targetNames = _filterTargetObjectNames(allNames, dateStrs);

      if (targetNames.isEmpty) {
        final legacyPrefix = '$trimmedDivision/$trimmedArea/logs/';
        allNames.addAll(
          await _listAllObjects(
            storage: storage,
            prefix: legacyPrefix,
          ),
        );
        targetNames = _filterTargetObjectNames(allNames, dateStrs);
      }

      final docsByKey = <String, _DeepDocBundle>{};
      var sourceCsvRowCount = 0;
      var duplicateMergedCount = 0;

      for (final objectName in targetNames) {
        final objectDateStr = _extractDateStrFromObjectName(objectName);
        if (objectDateStr == null || !dateStrs.contains(objectDateStr)) continue;

        final rows = await _loadCsvRowsByObjectName(
          storage: storage,
          objectName: objectName,
        );
        sourceCsvRowCount += rows.length;
        debugPrint('[STAT_DEEP] csv object=$objectName rows=${rows.length}');

        for (int i = 0; i < rows.length; i++) {
          final row = rows[i];
          final docIdBase = _pickString(<dynamic>[
                row['docId'],
                row['meta.docId'],
              ]) ??
              '';
          final docId = docIdBase.isEmpty ? '$objectName#$i' : docIdBase;
          final mergeKey = '$objectDateStr|$docId';
          final sectorFieldsPresent = _hasSectorColumns(row);
          final meta = _extractCsvMeta(row);
          final log = _extractCsvLog(row);
          final logs = log.isEmpty
              ? <Map<String, dynamic>>[]
              : <Map<String, dynamic>>[log];
          final plate = _extractPlate(meta, docId);
          final doc = _makeDocBundle(
            docId: docId,
            dateStr: objectDateStr,
            plateNumber: plate,
            meta: meta,
            logs: logs,
            sectorFieldsPresent: sectorFieldsPresent,
          );

          final existing = docsByKey[mergeKey];
          if (existing != null) duplicateMergedCount++;
          docsByKey[mergeKey] = existing == null ? doc : _mergeDocBundles(existing, doc);
        }
      }

      final docs = docsByKey.values.toList();
      docs.sort((a, b) {
        final dateCmp = a.dateStr.compareTo(b.dateStr);
        if (dateCmp != 0) return dateCmp;
        final at = a.departureCompletedAt ??
            a.lastLogTime ??
            a.requestTime ??
            DateTime.fromMillisecondsSinceEpoch(0);
        final bt = b.departureCompletedAt ??
            b.lastLogTime ??
            b.requestTime ??
            DateTime.fromMillisecondsSinceEpoch(0);
        final cmp = at.compareTo(bt);
        if (cmp != 0) return cmp;
        return a.plateNumber.compareTo(b.plateNumber);
      });

      final rows = <StatisticsDeepVehicleRow>[];

      for (int i = 0; i < docs.length; i++) {
        final doc = docs[i];
        final createdAt = doc.requestTime;
        final departureAt = doc.departureCompletedAt ?? doc.lastLogTime;

        rows.add(
          StatisticsDeepVehicleRow(
            no: i + 1,
            dateStr: doc.dateStr,
            plateNumber: doc.plateNumber.isEmpty ? doc.docId : doc.plateNumber,
            createdAt: createdAt,
            departureAt: departureAt,
            departureTimeSource: departureAt == null
                ? StatisticsDepartureTimeSource.missing
                : doc.departureTimeSource,
            fee: doc.lockedFeeAmount?.round(),
            paymentMethod: doc.paymentMethod,
            docId: doc.docId,
            sectorId: doc.sectorId,
            sectorName: doc.sectorName,
            sectorConflict: doc.sectorConflict,
            sectorIdentityConflict: false,
            sectorFieldsPresent: doc.sectorFieldsPresent,
          ),
        );
      }

      final diagnostics = StatisticsDeepDiagnostics(
        sourceObjectCount: targetNames.length,
        sourceCsvRowCount: sourceCsvRowCount,
        mergedVehicleCount: rows.length,
        duplicateMergedCount: duplicateMergedCount,
        sectorConflictCount: rows.where((row) => row.sectorConflict).length,
        sectorIdentityConflictCount: 0,
        sectorFieldPresentCount:
            rows.where((row) => row.sectorFieldsPresent).length,
        sectorFieldMissingCount:
            rows.where((row) => !row.sectorFieldsPresent).length,
      );
      debugPrint('[STAT_DEEP] load complete objects=${targetNames.length} csvRows=$sourceCsvRowCount vehicles=${rows.length} merged=$duplicateMergedCount sectorConflicts=${diagnostics.sectorConflictCount} sectorFields=${diagnostics.sectorFieldPresentCount}/${rows.length}');

      return StatisticsDeepReport.fromRows(
        division: trimmedDivision,
        area: trimmedArea,
        scopeLabel: label,
        rows: rows,
        objectNames: targetNames,
        dateStrs: dateStrs.toList()..sort(),
        sectorEnabled: sectorEnabled,
        diagnostics: diagnostics,
      );
    } finally {
      client.close();
    }
  }

  List<String> _filterTargetObjectNames(Set<String> names, Set<String> dateStrs) {
    final result = names.where((name) {
      final dateStr = _extractDateStrFromObjectName(name);
      return dateStr != null && dateStrs.contains(dateStr);
    }).toList()
      ..sort();
    return result;
  }

  String? _extractDateStrFromObjectName(String objectName) {
    final match = RegExp(r'_ToDoLogs_(\d{4}-\d{2}-\d{2})\.csv$').firstMatch(objectName);
    return match?.group(1);
  }

  Future<List<String>> _listAllObjects({
    required gcs.StorageApi storage,
    required String prefix,
  }) async {
    final acc = <String>[];
    String? pageToken;

    do {
      final res = await storage.objects.list(
        bucketName,
        prefix: prefix,
        pageToken: pageToken,
      );
      final items = res.items ?? const <gcs.Object>[];
      for (final object in items) {
        final name = object.name;
        if (name != null && name.isNotEmpty) acc.add(name);
      }
      pageToken = res.nextPageToken;
    } while (pageToken != null && pageToken.isNotEmpty);

    return acc;
  }

  Future<List<Map<String, String>>> _loadCsvRowsByObjectName({
    required gcs.StorageApi storage,
    required String objectName,
  }) async {
    final dynamic res = await storage.objects.get(
      bucketName,
      objectName,
      downloadOptions: gcs.DownloadOptions.fullMedia,
    );

    if (res is! gcs.Media) {
      throw StateError('통계 데이터 응답 형식이 올바르지 않습니다.');
    }

    final bytes = await res.stream.expand((chunk) => chunk).toList();
    return _decodeCsv(utf8.decode(bytes));
  }

  List<Map<String, String>> _decodeCsv(String text) {
    final table = _parseCsvTable(text);
    if (table.isEmpty) return <Map<String, String>>[];

    final headers = table.first
        .map((header) => header.replaceFirst('\ufeff', '').trim())
        .toList();
    final rows = <Map<String, String>>[];

    for (int i = 1; i < table.length; i++) {
      final cells = table[i];
      if (cells.every((cell) => cell.trim().isEmpty)) continue;
      final row = <String, String>{};
      for (int j = 0; j < headers.length; j++) {
        if (headers[j].isEmpty) continue;
        row[headers[j]] = j < cells.length ? cells[j] : '';
      }
      rows.add(row);
    }

    return rows;
  }

  List<List<String>> _parseCsvTable(String text) {
    final rows = <List<String>>[];
    var row = <String>[];
    final cell = StringBuffer();
    var inQuotes = false;
    var i = 0;

    while (i < text.length) {
      final char = text[i];
      if (inQuotes) {
        if (char == '"') {
          if (i + 1 < text.length && text[i + 1] == '"') {
            cell.write('"');
            i += 2;
            continue;
          }
          inQuotes = false;
          i++;
          continue;
        }
        cell.write(char);
        i++;
        continue;
      }

      if (char == '"') {
        inQuotes = true;
        i++;
        continue;
      }

      if (char == ',') {
        row.add(cell.toString());
        cell.clear();
        i++;
        continue;
      }

      if (char == '\n' || char == '\r') {
        row.add(cell.toString());
        cell.clear();
        rows.add(row);
        row = <String>[];
        if (char == '\r' && i + 1 < text.length && text[i + 1] == '\n') {
          i += 2;
        } else {
          i++;
        }
        continue;
      }

      cell.write(char);
      i++;
    }

    if (inQuotes || cell.isNotEmpty || row.isNotEmpty) {
      row.add(cell.toString());
      rows.add(row);
    }

    return rows;
  }

  bool _hasSectorColumns(Map<String, String> row) {
    const keys = <String>{
      'meta.sectorId',
      'meta.sector_id',
      'meta.sectorName',
      'meta.sector_name',
      'log.sectorId',
      'log.sector_id',
      'log.sectorName',
      'log.sector_name',
    };
    return row.keys.any(keys.contains);
  }

  Map<String, dynamic> _extractCsvMeta(Map<String, String> row) {
    final meta = <String, dynamic>{};

    row.forEach((key, value) {
      if (!key.startsWith('meta.')) return;
      final outKey = key.substring(5).trim();
      if (outKey.isEmpty) return;
      if (value.trim().isEmpty) return;
      meta[outKey] = value;
    });

    for (final key in <String>[
      'division',
      'area',
      'uploadedAt',
      'uploadedBy',
      'monthKey',
    ]) {
      final value = row[key];
      if (value != null && value.trim().isNotEmpty) meta[key] = value;
    }

    final docId = _pickString(<dynamic>[row['docId'], row['meta.docId']]);
    if (docId != null) meta['docId'] = docId;

    return meta;
  }

  Map<String, dynamic> _extractCsvLog(Map<String, String> row) {
    final log = <String, dynamic>{};
    row.forEach((key, value) {
      if (!key.startsWith('log.')) return;
      final outKey = key.substring(4).trim();
      if (outKey.isEmpty) return;
      if (value.trim().isEmpty) return;
      log[outKey] = value;
    });
    return log;
  }

  String _extractPlate(Map<String, dynamic> meta, String docId) {
    final candidates = <dynamic>[
      meta['plateNumber'],
      meta['plate_number'],
      meta['plate'],
      meta['plateNo'],
      meta['plate_no'],
      meta['carNumber'],
      meta['carNo'],
    ];

    for (final candidate in candidates) {
      final value = (candidate ?? '').toString().trim();
      if (value.isNotEmpty) return value;
    }

    if (docId.contains('_')) return docId.split('_').first;
    return docId;
  }

  _DeepDocBundle _makeDocBundle({
    required String docId,
    required String dateStr,
    required String plateNumber,
    required Map<String, dynamic> meta,
    required List<Map<String, dynamic>> logs,
    required bool sectorFieldsPresent,
  }) {
    final requestTime = _parseDateTime(
          meta['request_time'] ?? meta['requestTime'] ?? meta['createdAt'],
        ) ??
        _pickLogTime(logs, <String>['생성', '입차']);

    final departureCompletedDirect = _parseDateTime(meta['departureCompletedAt']);
    final departureLogTime = _pickLogTime(logs, <String>['출차']);
    final departureCompletedAt = departureCompletedDirect ?? departureLogTime;
    final departureTimeSource = departureCompletedDirect != null
        ? StatisticsDepartureTimeSource.completedAt
        : departureLogTime != null
            ? StatisticsDepartureTimeSource.departureLog
            : StatisticsDepartureTimeSource.lastLogFallback;

    final updatedAt = _parseDateTime(meta['updatedAt']);
    final lastLogTime = logs.isEmpty ? null : _parseDateTime(logs.last['timestamp']);

    final lockedFeeAmount = _toNum(meta['lockedFeeAmount']) ??
        _toNum(meta['lockedFee']) ??
        _pickNumFromLogs(logs, <String>['lockedFee', 'lockedFeeAmount']);

    final metaSectorId = _pickString(<dynamic>[
      meta['sectorId'],
      meta['sector_id'],
    ]);
    final metaSectorName = _pickString(<dynamic>[
      meta['sectorName'],
      meta['sector_name'],
    ]);
    final logSectorId = _pickStringFromLogs(
      logs,
      <String>['sectorId', 'sector_id'],
    );
    final logSectorName = _pickStringFromLogs(
      logs,
      <String>['sectorName', 'sector_name'],
    );
    final sectorId = metaSectorId ?? logSectorId;
    final sectorName = metaSectorName ?? logSectorName;
    final sectorConflict = _hasSectorConflict(
      metaSectorId: metaSectorId,
      metaSectorName: metaSectorName,
      logSectorId: logSectorId,
      logSectorName: logSectorName,
    );

    final paymentMethod = _normalizePaymentMethod(
          _pickString(<dynamic>[
            meta['paymentMethod'],
            meta['payMethod'],
            meta['paymentType'],
            meta['payment_method'],
            meta['settlementMethod'],
            meta['feePaymentMethod'],
          ]),
        ) ??
        _normalizePaymentMethod(
          _pickStringFromLogs(
            logs,
            <String>[
              'paymentMethod',
              'payMethod',
              'paymentType',
              'payment_method',
              'settlementMethod',
              'feePaymentMethod',
            ],
          ),
        ) ??
        '';

    return _DeepDocBundle(
      docId: docId,
      dateStr: dateStr,
      plateNumber: plateNumber,
      requestTime: requestTime,
      departureCompletedAt: departureCompletedAt,
      departureTimeSource: departureTimeSource,
      updatedAt: updatedAt,
      lastLogTime: lastLogTime,
      lockedFeeAmount: lockedFeeAmount,
      paymentMethod: paymentMethod,
      sectorId: sectorId,
      sectorName: sectorName,
      sectorConflict: sectorConflict,
      sectorFieldsPresent: sectorFieldsPresent,
      meta: meta,
      logs: logs,
    );
  }

  _DeepDocBundle _mergeDocBundles(_DeepDocBundle a, _DeepDocBundle b) {
    final aTime = a.updatedAt ?? a.departureCompletedAt ?? a.lastLogTime ?? DateTime.fromMillisecondsSinceEpoch(0);
    final bTime = b.updatedAt ?? b.departureCompletedAt ?? b.lastLogTime ?? DateTime.fromMillisecondsSinceEpoch(0);
    final preferB = bTime.isAfter(aTime);
    final primary = preferB ? b : a;
    final secondary = preferB ? a : b;

    final mergedMeta = <String, dynamic>{};
    mergedMeta.addAll(secondary.meta);
    mergedMeta.addAll(primary.meta);

    final mergedLogs = _mergeLogs(a.logs, b.logs);
    final mergedPlate = primary.plateNumber.trim().isNotEmpty
        ? primary.plateNumber
        : secondary.plateNumber;

    return _makeDocBundle(
      docId: primary.docId,
      dateStr: primary.dateStr,
      plateNumber: mergedPlate,
      meta: mergedMeta,
      logs: mergedLogs,
      sectorFieldsPresent: a.sectorFieldsPresent || b.sectorFieldsPresent,
    );
  }

  List<Map<String, dynamic>> _mergeLogs(
    List<Map<String, dynamic>> a,
    List<Map<String, dynamic>> b,
  ) {
    final combined = <Map<String, dynamic>>[];
    combined.addAll(a);
    combined.addAll(b);

    final seen = <String>{};
    final unique = <Map<String, dynamic>>[];
    for (final entry in combined) {
      final sig = _logSignature(entry);
      if (seen.add(sig)) unique.add(entry);
    }

    unique.sort((x, y) {
      final xt = _parseDateTime(x['timestamp']) ?? DateTime.fromMillisecondsSinceEpoch(0);
      final yt = _parseDateTime(y['timestamp']) ?? DateTime.fromMillisecondsSinceEpoch(0);
      return xt.compareTo(yt);
    });

    return unique;
  }

  String _logSignature(Map<String, dynamic> entry) {
    final ts = (entry['timestamp'] ?? '').toString();
    final action = (entry['action'] ?? '').toString();
    final by = (entry['performedBy'] ?? '').toString();
    final from = (entry['from'] ?? '').toString();
    final to = (entry['to'] ?? '').toString();
    final fee = (entry['lockedFee'] ?? entry['lockedFeeAmount'] ?? '').toString();
    final pay = (entry['paymentMethod'] ?? entry['payMethod'] ?? entry['paymentType'] ?? entry['payment_method'] ?? '').toString();
    return '$ts|$action|$by|$from|$to|$fee|$pay';
  }

  DateTime? _pickLogTime(List<Map<String, dynamic>> logs, List<String> keywords) {
    for (int i = logs.length - 1; i >= 0; i--) {
      final action = (logs[i]['action'] ?? '').toString();
      final matched = keywords.any(action.contains);
      if (!matched) continue;
      final dt = _parseDateTime(logs[i]['timestamp']);
      if (dt != null) return dt;
    }
    return null;
  }

  num? _pickNumFromLogs(List<Map<String, dynamic>> logs, List<String> keys) {
    for (int i = logs.length - 1; i >= 0; i--) {
      final entry = logs[i];
      for (final key in keys) {
        final n = _toNum(entry[key]);
        if (n != null) return n;
      }
    }
    return null;
  }

  String? _pickString(List<dynamic> values) {
    for (final value in values) {
      final text = (value ?? '').toString().trim();
      if (text.isNotEmpty) return text;
    }
    return null;
  }

  String? _pickStringFromLogs(List<Map<String, dynamic>> logs, List<String> keys) {
    for (int i = logs.length - 1; i >= 0; i--) {
      final entry = logs[i];
      for (final key in keys) {
        final text = (entry[key] ?? '').toString().trim();
        if (text.isNotEmpty) return text;
      }
    }
    return null;
  }

  bool _hasSectorConflict({
    required String? metaSectorId,
    required String? metaSectorName,
    required String? logSectorId,
    required String? logSectorName,
  }) {
    final metaId = (metaSectorId ?? '').trim();
    final metaName = (metaSectorName ?? '').trim();
    final logId = (logSectorId ?? '').trim();
    final logName = (logSectorName ?? '').trim();
    final idConflict = metaId.isNotEmpty && logId.isNotEmpty && metaId != logId;
    final nameConflict =
        metaName.isNotEmpty && logName.isNotEmpty && metaName != logName;
    return idConflict || nameConflict;
  }

  String? _normalizePaymentMethod(String? raw) {
    final value = raw?.trim();
    if (value == null || value.isEmpty) return null;
    final lower = value.toLowerCase();
    if (lower == 'cash' || lower == 'money' || value.contains('현금')) return '현금';
    if (lower == 'card' || lower == 'credit' || lower == 'creditcard' || value.contains('카드')) return '카드';
    if (lower == 'transfer' || lower == 'bank' || lower == 'wire' || lower == 'remit' || value.contains('송금') || value.contains('계좌') || value.contains('이체')) return '송금';
    return value;
  }

  num? _toNum(dynamic value) {
    if (value is num) return value;
    if (value is String) return num.tryParse(value.replaceAll(',', '').trim());
    return null;
  }

  DateTime? _parseDateTime(dynamic value) {
    if (value == null) return null;

    if (value is DateTime) return value.toLocal();

    if (value is int) {
      if (value > 100000000000) {
        return DateTime.fromMillisecondsSinceEpoch(value).toLocal();
      }
      return DateTime.fromMillisecondsSinceEpoch(value * 1000).toLocal();
    }

    if (value is num) {
      final asInt = value.toInt();
      if (asInt > 100000000000) {
        return DateTime.fromMillisecondsSinceEpoch(asInt).toLocal();
      }
      return DateTime.fromMillisecondsSinceEpoch(asInt * 1000).toLocal();
    }

    if (value is String) {
      return DateTime.tryParse(value)?.toLocal();
    }

    return null;
  }

  static DateTime _normalizeDate(DateTime date) => DateTime(date.year, date.month, date.day);

  static String _yyyymmdd(DateTime date) => '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  static String _yyyymm(DateTime date) => '${date.year.toString().padLeft(4, '0')}'
      '${date.month.toString().padLeft(2, '0')}';
}

class _DeepDocBundle {
  final String docId;
  final String dateStr;
  final String plateNumber;
  final DateTime? requestTime;
  final DateTime? departureCompletedAt;
  final StatisticsDepartureTimeSource departureTimeSource;
  final DateTime? updatedAt;
  final DateTime? lastLogTime;
  final num? lockedFeeAmount;
  final String paymentMethod;
  final String? sectorId;
  final String? sectorName;
  final bool sectorConflict;
  final bool sectorFieldsPresent;
  final Map<String, dynamic> meta;
  final List<Map<String, dynamic>> logs;

  const _DeepDocBundle({
    required this.docId,
    required this.dateStr,
    required this.plateNumber,
    required this.requestTime,
    required this.departureCompletedAt,
    required this.departureTimeSource,
    required this.updatedAt,
    required this.lastLogTime,
    required this.lockedFeeAmount,
    required this.paymentMethod,
    required this.sectorId,
    required this.sectorName,
    required this.sectorConflict,
    required this.sectorFieldsPresent,
    required this.meta,
    required this.logs,
  });
}
