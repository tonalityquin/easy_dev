import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:googleapis/storage/v1.dart' as gcs;

import '../../app/config/auth_config.dart';
import '../../features/dev/debug/debug_api_logger.dart';
import 'google_auth_session.dart';

const String kBucketName = AuthConfig.gcsBucketName;

String _sanitizeFileComponent(String input) {
  final s = input
      .replaceAll(RegExp(r'[^0-9A-Za-z가-힣_.-]'), '_')
      .replaceAll(RegExp(r'_+'), '_')
      .trim();

  if (s.isEmpty || RegExp(r'^_+$').hasMatch(s)) return 'user';
  return s;
}

String _yyyyMM(DateTime dt) {
  final y = dt.year.toString().padLeft(4, '0');
  final m = dt.month.toString().padLeft(2, '0');
  return '$y$m';
}

Map<String, dynamic>? _asMap(dynamic value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return Map<String, dynamic>.from(value);
  return null;
}

String _csvScalar(dynamic value) {
  if (value == null) return '';
  if (value is DateTime) return value.toIso8601String();
  if (value is num || value is bool || value is String) return value.toString();
  return value.toString();
}

void _flattenCsvValue(
  String prefix,
  dynamic value,
  Map<String, dynamic> output,
) {
  if (prefix.trim().isEmpty) return;

  if (value == null) {
    output[prefix] = '';
    return;
  }

  if (value is DateTime || value is num || value is bool || value is String) {
    output[prefix] = _csvScalar(value);
    return;
  }

  if (value is Map) {
    if (value.isEmpty) {
      output[prefix] = '';
      return;
    }

    for (final entry in value.entries) {
      final key = entry.key.toString().trim();
      if (key.isEmpty) continue;
      _flattenCsvValue('$prefix.$key', entry.value, output);
    }
    return;
  }

  if (value is List) {
    if (value.isEmpty) {
      output[prefix] = '';
      return;
    }

    for (int i = 0; i < value.length; i++) {
      _flattenCsvValue('$prefix.$i', value[i], output);
    }
    return;
  }

  output[prefix] = _csvScalar(value);
}

String _csvEscape(dynamic value) {
  final text = _csvScalar(value);
  final escaped = text.replaceAll('"', '""');
  final needsQuote = escaped.contains(',') ||
      escaped.contains('"') ||
      escaped.contains('\n') ||
      escaped.contains('\r');
  return needsQuote ? '"$escaped"' : escaped;
}

String _csvHeaderRank(String header) {
  if (header.startsWith('report.')) return '0_$header';
  if (header.startsWith('meta.')) return '1_$header';
  if (header.startsWith('log.')) return '2_$header';
  return '3_$header';
}

String _toCsv(List<Map<String, dynamic>> rows) {
  const fixedHeaders = <String>[
    'division',
    'area',
    'uploadedAt',
    'uploadedBy',
    'monthKey',
    'docId',
    'rowKind',
    'logIndex',
  ];

  final headerSet = <String>{...fixedHeaders};
  for (final row in rows) {
    headerSet.addAll(row.keys);
  }

  final dynamicHeaders = headerSet
      .where((header) => !fixedHeaders.contains(header))
      .toList()
    ..sort((a, b) => _csvHeaderRank(a).compareTo(_csvHeaderRank(b)));

  final headers = <String>[...fixedHeaders, ...dynamicHeaders];
  final buffer = StringBuffer();
  buffer.writeln(headers.map(_csvEscape).join(','));

  for (final row in rows) {
    buffer.writeln(headers.map((header) => _csvEscape(row[header])).join(','));
  }

  return buffer.toString();
}

List<Map<String, dynamic>> _buildEndLogCsvRows({
  required Map<String, dynamic> report,
  required String division,
  required String area,
  required String userName,
  required DateTime uploadedAt,
  required String monthKey,
}) {
  final reportFlat = <String, dynamic>{};
  report.forEach((key, value) {
    if (key == 'items' || key == 'data' || key == 'division' || key == 'area') {
      return;
    }
    _flattenCsvValue('report.$key', value, reportFlat);
  });

  final itemsRaw = report['items'] ?? report['data'];
  final items = itemsRaw is List ? itemsRaw : const <dynamic>[];
  final rows = <Map<String, dynamic>>[];
  final base = <String, dynamic>{
    'division': division,
    'area': area,
    'uploadedAt': uploadedAt.toIso8601String(),
    'uploadedBy': userName,
    'monthKey': monthKey,
    ...reportFlat,
  };

  for (int itemIndex = 0; itemIndex < items.length; itemIndex++) {
    final itemMap = _asMap(items[itemIndex]);
    if (itemMap == null) continue;

    final dataMap = _asMap(itemMap['data']) ?? <String, dynamic>{};
    final docId = (itemMap['docId'] ?? dataMap['docId'] ?? '').toString();

    final metaSource = <String, dynamic>{};
    itemMap.forEach((key, value) {
      if (key == 'data' || key == 'logs' || key == 'docId') return;
      metaSource[key] = value;
    });
    dataMap.forEach((key, value) {
      if (key == 'logs') return;
      metaSource[key] = value;
    });
    metaSource['docId'] = docId;

    final metaFlat = <String, dynamic>{};
    metaSource.forEach((key, value) {
      final normalizedKey = key.toString().trim();
      if (normalizedKey.isEmpty) return;
      _flattenCsvValue('meta.$normalizedKey', value, metaFlat);
    });

    final logsRaw = itemMap['logs'] ?? dataMap['logs'];
    final logs = logsRaw is List ? logsRaw : const <dynamic>[];

    if (logs.isEmpty) {
      rows.add(<String, dynamic>{
        ...base,
        'docId': docId,
        'rowKind': 'meta',
        'logIndex': '',
        ...metaFlat,
      });
      continue;
    }

    for (int logIndex = 0; logIndex < logs.length; logIndex++) {
      final logMap = _asMap(logs[logIndex]);
      final logFlat = <String, dynamic>{};
      if (logMap != null) {
        logMap.forEach((key, value) {
          final normalizedKey = key.toString().trim();
          if (normalizedKey.isEmpty) return;
          _flattenCsvValue('log.$normalizedKey', value, logFlat);
        });
      }

      rows.add(<String, dynamic>{
        ...base,
        'docId': docId,
        'rowKind': 'log',
        'logIndex': logIndex,
        ...metaFlat,
        ...logFlat,
      });
    }
  }

  return rows;
}

Future<gcs.Object> _uploadCsvToGcs({
  required String csv,
  required String destinationPath,
  required String purpose,
  bool makePublicRead = true,
}) async {
  if (destinationPath.trim().isEmpty) {
    const msg = 'destinationPath가 비어 있어 CSV를 업로드할 수 없습니다.';
    debugPrint('⚠️ [$purpose] $msg');

    await DebugApiLogger().log(
      {
        'tag': 'gcs_uploader._uploadCsvToGcs',
        'message': 'CSV 업로드 실패 - destinationPath 미설정',
        'reason': 'validation_failed',
        'bucketName': kBucketName,
        'destinationPath': destinationPath,
        'purpose': purpose,
      },
      level: 'error',
      tags: const ['gcs', 'csv_upload', 'validation'],
    );

    throw ArgumentError('destinationPath must not be empty');
  }

  Future<gcs.Object> runOnce({required bool allowRethrowInvalid}) async {
    File? temp;
    try {
      final tempPath =
          '${Directory.systemTemp.path}/gcs_upload_${DateTime.now().microsecondsSinceEpoch}.csv';
      temp = File(tempPath);
      await temp.writeAsString(csv, encoding: utf8);

      final length = await temp.length();

      debugPrint(
        '🚀 [$purpose] CSV 업로드 시작: '
        'bucket=$kBucketName, path=$destinationPath (${length}B)',
      );

      final client = await GoogleAuthSession.instance.safeClient();

      final storage = gcs.StorageApi(client);
      final media = gcs.Media(
        temp.openRead(),
        length,
        contentType: 'text/csv; charset=utf-8',
      );

      final object = gcs.Object()..name = destinationPath;

      final res = await storage.objects.insert(
        object,
        kBucketName,
        uploadMedia: media,
        predefinedAcl: makePublicRead ? 'publicRead' : null,
      );

      debugPrint(
        '✅ [$purpose] CSV 업로드 성공: '
        'bucket=$kBucketName, objectName=${res.name}',
      );

      return res;
    } catch (e, st) {
      final msg = 'CSV를 GCS에 업로드하는 중 오류가 발생했습니다. ($e)';
      debugPrint('🔥 [$purpose] $msg');

      await DebugApiLogger().log(
        {
          'tag': 'gcs_uploader._uploadCsvToGcs',
          'message': 'CSV 업로드 중 예외 발생',
          'reason': 'exception',
          'error': e.toString(),
          'stack': st.toString(),
          'bucketName': kBucketName,
          'destinationPath': destinationPath,
          'purpose': purpose,
        },
        level: 'error',
        tags: const ['gcs', 'csv_upload', 'exception'],
      );

      if (allowRethrowInvalid && GoogleAuthSession.isInvalidTokenError(e)) {
        rethrow;
      }

      rethrow;
    } finally {
      if (temp != null) {
        try {
          await temp.delete();
        } catch (_) {}
      }
    }
  }

  try {
    return await runOnce(allowRethrowInvalid: true);
  } catch (e) {
    if (GoogleAuthSession.isInvalidTokenError(e)) {
      debugPrint('⚠️ [$purpose] invalid_token 감지 -> 토큰 강제 갱신 후 재시도 시도 중...');

      try {
        await GoogleAuthSession.instance.refreshIfNeeded();
      } catch (refreshError, refreshSt) {
        final msg = '토큰 강제 갱신(refreshIfNeeded) 중 오류가 발생했습니다. ($refreshError)';
        debugPrint('🔥 [$purpose] $msg');

        await DebugApiLogger().log(
          {
            'tag': 'gcs_uploader._uploadCsvToGcs',
            'message': '토큰 강제 갱신(refreshIfNeeded) 실패',
            'reason': 'refresh_failed',
            'error': refreshError.toString(),
            'stack': refreshSt.toString(),
            'bucketName': kBucketName,
            'destinationPath': destinationPath,
            'purpose': purpose,
          },
          level: 'error',
          tags: const ['gcs', 'csv_upload', 'auth'],
        );

        rethrow;
      }

      return await runOnce(allowRethrowInvalid: false);
    }

    rethrow;
  }
}

Future<String?> uploadEndLogCsv({
  required Map<String, dynamic> report,
  required String division,
  required String area,
  required String userName,
}) async {
  final now = DateTime.now();
  final dateStr = now.toIso8601String().split('T').first;
  final ts = now.millisecondsSinceEpoch;
  final safeUser = _sanitizeFileComponent(userName);
  final monthKey = _yyyyMM(now);
  final fileName = '${safeUser}_${ts}_ToDoLogs_${dateStr}.csv';
  final path = '$division/$area/logs/$monthKey/$ts/$fileName';
  final rows = _buildEndLogCsvRows(
    report: report,
    division: division,
    area: area,
    userName: userName,
    uploadedAt: now,
    monthKey: monthKey,
  );
  final csv = _toCsv(rows);

  final res = await _uploadCsvToGcs(
    csv: csv,
    destinationPath: path,
    purpose: '업무 종료 로그(logs) CSV',
  );

  return res.name != null
      ? 'https://storage.googleapis.com/$kBucketName/${res.name}'
      : null;
}
