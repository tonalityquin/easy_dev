import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:googleapis/storage/v1.dart' as gcs;

import '../../features/dev/debug/debug_api_logger.dart';
import 'google_auth_session.dart';

import '../../core/config/external_ids.dart';
class GcsJsonUploader {
  final String bucketName;

  GcsJsonUploader({String? bucketName})
      : bucketName = bucketName ?? kBucketName;

  Future<List<Map<String, dynamic>>> loadPlateLogs({
    required String plateNumber,
    required String division,
    required String area,
    required DateTime date,
  }) async {
    String dateStr = '';
    String prefix = '';
    String wantedSuffix = '';
    String needle = '';
    String needleTail4 = '';
    String monthKey = '';

    Future<List<Map<String, dynamic>>> runOnce({
      required bool allowRethrowInvalid,
    }) async {
      try {
        final trimmedPlate = plateNumber.trim();
        final trimmedDivision = division.trim();
        final trimmedArea = area.trim();

        if (trimmedPlate.isEmpty ||
            trimmedDivision.isEmpty ||
            trimmedArea.isEmpty) {
          final msg = 'loadPlateLogs 실패: 필수 인자가 비어 있습니다.\n'
              'plateNumber="$trimmedPlate", division="$trimmedDivision", area="$trimmedArea"';
          debugPrint('⚠️ [$bucketName] $msg');

          await DebugApiLogger().log(
            {
              'tag': 'GcsJsonUploader.loadPlateLogs',
              'message': 'plate 로그 조회 실패 - 필수 인자 누락',
              'reason': 'validation_failed',
              'bucketName': bucketName,
              'plateNumber': plateNumber,
              'division': division,
              'area': area,
              'date': date.toIso8601String(),
            },
            level: 'error',
            tags: const ['gcs', 'json', 'plate_logs', 'validation'],
          );

          return <Map<String, dynamic>>[];
        }

        final normalizedDate = DateTime(date.year, date.month, date.day);
        dateStr = _yyyymmdd(normalizedDate);
        monthKey = _yyyymm(normalizedDate);

        wantedSuffix = '_ToDoLogs_$dateStr.json';

        needle = _digitsOnly(trimmedPlate);
        needleTail4 =
            needle.length >= 4 ? needle.substring(needle.length - 4) : needle;

        final prefixesToTry = <String>[
          '$trimmedDivision/$trimmedArea/logs/$monthKey/',
          '$trimmedDivision/$trimmedArea/logs/',
        ];

        debugPrint(
          '🔍 [GcsJsonUploader] plate 로그 조회 시작: '
          'bucket=$bucketName, prefixes="${prefixesToTry.join(' | ')}", '
          'suffix="$wantedSuffix", plate="$needle"',
        );

        final client = await GoogleAuthSession.instance.safeClient();
        final storage = gcs.StorageApi(client);

        List<gcs.Object> candidates = <gcs.Object>[];
        final List<String> scannedPrefixes = <String>[];

        for (final pfx in prefixesToTry) {
          prefix = pfx;
          scannedPrefixes.add(prefix);

          final allObjects = await _listAllObjects(
            storage: storage,
            bucketName: bucketName,
            prefix: prefix,
          );

          candidates = allObjects
              .where((o) => (o.name ?? '').endsWith(wantedSuffix))
              .toList();

          if (candidates.isNotEmpty) {
            break;
          }
        }

        if (candidates.isEmpty) {
          final msg = '해당 날짜에 매칭되는 로그 파일이 없습니다: '
              'prefixTried="${scannedPrefixes.join(' | ')}", suffix="$wantedSuffix"';
          debugPrint('⚠️ [GcsJsonUploader] $msg');

          await DebugApiLogger().log(
            {
              'tag': 'GcsJsonUploader.loadPlateLogs',
              'message': '해당 날짜 로그 파일 없음',
              'reason': 'no_file_for_date',
              'bucketName': bucketName,
              'prefixTried': scannedPrefixes,
              'suffix': wantedSuffix,
              'plateNumber': plateNumber,
              'division': division,
              'area': area,
              'date': date.toIso8601String(),
              'monthKey': monthKey,
            },
            level: 'info',
            tags: const ['gcs', 'json', 'plate_logs', 'not_found'],
          );

          return <Map<String, dynamic>>[];
        }

        candidates.sort((a, b) {
          final au = a.updated ?? DateTime.fromMillisecondsSinceEpoch(0);
          final bu = b.updated ?? DateTime.fromMillisecondsSinceEpoch(0);
          return au.compareTo(bu);
        });
        final objectName = candidates.last.name!;

        debugPrint(
          '📄 [GcsJsonUploader] 대상 객체 선택: $objectName (updated=${candidates.last.updated})',
        );

        final dynamic res = await storage.objects.get(
          bucketName,
          objectName,
          downloadOptions: gcs.DownloadOptions.fullMedia,
        );
        if (res is! gcs.Media) {
          final msg = '예상치 못한 반환 타입: ${res.runtimeType}, Media가 아닙니다.';
          debugPrint('⚠️ [GcsJsonUploader] $msg');

          await DebugApiLogger().log(
            {
              'tag': 'GcsJsonUploader.loadPlateLogs',
              'message': 'GCS objects.get 반환 타입이 Media가 아님',
              'reason': 'invalid_response_type',
              'bucketName': bucketName,
              'objectName': objectName,
              'responseType': res.runtimeType.toString(),
            },
            level: 'error',
            tags: const ['gcs', 'json', 'plate_logs'],
          );

          return <Map<String, dynamic>>[];
        }

        final gcs.Media media = res;
        final bytes = await media.stream.expand((e) => e).toList();
        final decoded = jsonDecode(utf8.decode(bytes));

        final List rootItems = (decoded is Map && decoded['items'] is List)
            ? decoded['items'] as List
            : (decoded is Map && decoded['data'] is List)
                ? decoded['data'] as List
                : (decoded is List)
                    ? decoded
                    : const [];

        if (rootItems.isEmpty) {
          debugPrint(
            '⚠️ [GcsJsonUploader] JSON 내 items/data 배열이 비어 있습니다. objectName=$objectName',
          );
        }

        final aggregated = <Map<String, dynamic>>[];

        for (final it in rootItems) {
          if (it is! Map) continue;

          final map = Map<String, dynamic>.from(it);

          final Map<String, dynamic>? dataMap = (map['data'] is Map)
              ? Map<String, dynamic>.from(map['data'] as Map)
              : null;

          final plateRaw = _pickPlateCandidate(map: map, dataMap: dataMap);
          final pd = _digitsOnly(plateRaw);

          final matches = pd.isNotEmpty &&
              ((needle.length >= 4 && pd.endsWith(needleTail4)) ||
                  (needle.isNotEmpty && pd == needle));
          if (!matches) continue;

          final logsRaw = map['logs'] ?? dataMap?['logs'];

          final logs = (logsRaw is List)
              ? logsRaw
                  .whereType<Map>()
                  .map((e) => Map<String, dynamic>.from(e))
                  .toList()
              : const <Map<String, dynamic>>[];

          aggregated.addAll(logs);
        }

        aggregated.sort((a, b) {
          final at = _parseTs(a['timestamp']) ??
              DateTime.fromMillisecondsSinceEpoch(0);
          final bt = _parseTs(b['timestamp']) ??
              DateTime.fromMillisecondsSinceEpoch(0);
          return at.compareTo(bt);
        });

        debugPrint(
          '✅ [GcsJsonUploader] plate 로그 조회 완료: plate="$needle", count=${aggregated.length}',
        );

        return aggregated;
      } catch (e, st) {
        final msg = 'plate 로그 JSON 조회 중 오류가 발생했습니다. ($e)';
        debugPrint('⚠️ [GcsJsonUploader] $msg');

        await DebugApiLogger().log(
          {
            'tag': 'GcsJsonUploader.loadPlateLogs',
            'message': 'plate 로그 JSON 조회 중 예외 발생',
            'reason': 'exception',
            'error': e.toString(),
            'stack': st.toString(),
            'bucketName': bucketName,
            'prefix': prefix,
            'suffix': wantedSuffix,
            'plateNumber': plateNumber,
            'division': division,
            'area': area,
            'date': date.toIso8601String(),
            'monthKey': monthKey,
            'needle': needle,
            'needleTail4': needleTail4,
          },
          level: 'error',
          tags: const ['gcs', 'json', 'plate_logs', 'exception'],
        );

        if (allowRethrowInvalid && GoogleAuthSession.isInvalidTokenError(e)) {
          rethrow;
        }

        return <Map<String, dynamic>>[];
      }
    }

    try {
      return await runOnce(allowRethrowInvalid: true);
    } catch (e) {
      if (GoogleAuthSession.isInvalidTokenError(e)) {
        debugPrint(
          '⚠️ [GcsJsonUploader] invalid_token 감지 -> 토큰 강제 갱신 후 재시도 시도 중...',
        );

        try {
          await GoogleAuthSession.instance.refreshIfNeeded();
        } catch (refreshError, refreshSt) {
          await DebugApiLogger().log(
            {
              'tag': 'GcsJsonUploader.loadPlateLogs',
              'message': '토큰 강제 갱신(refreshIfNeeded) 실패',
              'reason': 'refresh_failed',
              'error': refreshError.toString(),
              'stack': refreshSt.toString(),
              'bucketName': bucketName,
              'plateNumber': plateNumber,
              'division': division,
              'area': area,
              'date': date.toIso8601String(),
            },
            level: 'error',
            tags: const ['gcs', 'json', 'plate_logs', 'auth'],
          );
          return <Map<String, dynamic>>[];
        }

        return await runOnce(allowRethrowInvalid: false);
      }

      debugPrint(
        '❌ [GcsJsonUploader] plate 로그 조회 중 알 수 없는 오류가 발생했습니다. ($e)',
      );
      return <Map<String, dynamic>>[];
    }
  }

  static Future<List<gcs.Object>> _listAllObjects({
    required gcs.StorageApi storage,
    required String bucketName,
    required String prefix,
  }) async {
    final List<gcs.Object> allObjects = <gcs.Object>[];
    String? pageToken;

    do {
      final res = await storage.objects.list(
        bucketName,
        prefix: prefix,
        pageToken: pageToken,
      );
      if (res.items != null) {
        allObjects.addAll(res.items!);
      }
      pageToken = res.nextPageToken;
    } while (pageToken != null && pageToken.isNotEmpty);

    return allObjects;
  }

  static String _yyyymmdd(DateTime d) => '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  static String _yyyymm(DateTime d) => '${d.year.toString().padLeft(4, '0')}'
      '${d.month.toString().padLeft(2, '0')}';

  static String _digitsOnly(String s) => s.replaceAll(RegExp(r'\D'), '');

  static String _pickPlateCandidate({
    required Map<String, dynamic> map,
    required Map<String, dynamic>? dataMap,
  }) {
    final candidates = <dynamic>[
      map['plateNumber'],
      dataMap?['plateNumber'],
      dataMap?['plate'],
      dataMap?['plateNo'],
      dataMap?['plate_no'],
      dataMap?['carNumber'],
      dataMap?['carNo'],
      map['docId'],
      dataMap?['docId'],
    ];

    for (final c in candidates) {
      final s = (c ?? '').toString().trim();
      if (s.isNotEmpty) return s;
    }
    return '';
  }

  static DateTime? _parseTs(dynamic ts) {
    if (ts == null) return null;

    if (ts is int) {
      if (ts > 100000000000) {
        return DateTime.fromMillisecondsSinceEpoch(ts).toLocal();
      }
      return DateTime.fromMillisecondsSinceEpoch(ts * 1000).toLocal();
    }

    if (ts is String) {
      return DateTime.tryParse(ts)?.toLocal();
    }

    return null;
  }
}
