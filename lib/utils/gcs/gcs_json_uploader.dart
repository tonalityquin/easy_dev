// File: lib/utils/gcs_json_uploader.dart

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:googleapis/storage/v1.dart' as gcs;

import '../google_auth_session.dart';
import '../../screens/hubs_mode/dev_package/debug_package/debug_api_logger.dart';

/// GCS(easydev-image 버킷)에서 번호판 로그 JSON을 조회하는 유틸.
///
/// - 중앙 OAuth 세션(GoogleAuthSession)을 사용해 인증
/// - 토큰 만료/invalid_token 시 1회 refreshIfNeeded() 후 재시도
/// - 실패 시 빈 리스트 반환 + DebugApiLogger 로깅
///
/// [조회 경로 정책]
/// - 신규 업로드 경로(월 샤딩):
///   <division>/<area>/logs/<yyyyMM>/<ts>/<fileName>
/// - 레거시 경로(월 디렉터리 없음):
///   <division>/<area>/logs/<ts>/<fileName> 또는 <division>/<area>/logs/<fileName>
///
/// 조회는 `date`를 받으므로 기본적으로 logs/<yyyyMM>/ prefix로 탐색하고,
/// 해당 월 prefix에서 파일이 없으면 레거시 logs/ prefix로 fallback 탐색합니다.
class GcsJsonUploader {
  /// 기본 버킷명 (필요하면 생성자에서 override 가능)
  final String bucketName;

  GcsJsonUploader({String? bucketName})
      : bucketName = bucketName ?? 'easydev-image';

  /// plates 로그 JSON을 GCS에서 읽어온 뒤,
  /// 해당 번호판(plateNumber)에 해당하는 로그들을 시간순으로 정렬하여 반환.
  ///
  /// - 객체 이름 패턴:
  ///   - prefix(신규 우선): `{division}/{area}/logs/{yyyyMM}/`
  ///   - prefix(레거시): `{division}/{area}/logs/`
  ///   - suffix: `_ToDoLogs_{yyyy-MM-dd}.json`
  ///
  /// - JSON 구조 지원(호환 강화):
  ///   1) { "items": [ { "plateNumber": "...", "logs": [ ... ] }, ... ] }
  ///   2) { "data":  [ ... ] }
  ///   3) { "items": [ { "docId": "...", "data": { ... , "logs":[...] } }, ... ] }  // ✅ 추가 지원
  ///
  /// - plateNumber 비교:
  ///   - 숫자만 추출 후, 마지막 4자리 일치 또는 전체 일치 조건으로 매칭
  ///
  /// 실패 시 항상 `[]` 반환.
  Future<List<Map<String, dynamic>>> loadPlateLogs({
    required String plateNumber,
    required String division,
    required String area,
    required DateTime date,
  }) async {
    // 로깅용 필드들 (catch 블록에서도 참조할 수 있도록 바깥에서 선언)
    String dateStr = '';
    String prefix = '';
    String wantedSuffix = '';
    String needle = '';
    String needleTail4 = '';
    String monthKey = '';

    // 내부 1회 실행 함수: invalid_token일 경우 rethrow 가능
    Future<List<Map<String, dynamic>>> runOnce({
      required bool allowRethrowInvalid,
    }) async {
      try {
        // 0) 입력값 검증
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

        // 1) 날짜/경로/검색 키워드 구성
        final normalizedDate = DateTime(date.year, date.month, date.day);
        dateStr = _yyyymmdd(normalizedDate);
        monthKey = _yyyymm(normalizedDate);

        wantedSuffix = '_ToDoLogs_$dateStr.json';

        needle = _digitsOnly(trimmedPlate);
        needleTail4 = needle.length >= 4
            ? needle.substring(needle.length - 4)
            : needle;

        // ✅ prefix: 월 샤딩 우선, 없으면 레거시 fallback
        final prefixesToTry = <String>[
          '$trimmedDivision/$trimmedArea/logs/$monthKey/',
          '$trimmedDivision/$trimmedArea/logs/',
        ];

        debugPrint(
          '🔍 [GcsJsonUploader] plate 로그 조회 시작: '
              'bucket=$bucketName, prefixes="${prefixesToTry.join(' | ')}", '
              'suffix="$wantedSuffix", plate="$needle"',
        );

        // 2) 중앙 OAuth 세션에서 AuthClient 획득
        final client = await GoogleAuthSession.instance.safeClient();
        final storage = gcs.StorageApi(client);

        // 3) 객체 리스트 조회 (prefix 후보 순서대로, 페이지네이션 대응)
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
          final msg =
              '해당 날짜에 매칭되는 로그 파일이 없습니다: '
              'prefixTried="${scannedPrefixes.join(' | ')}", suffix="$wantedSuffix"';
          debugPrint('⚠️ [GcsJsonUploader] $msg');

          // 이 케이스는 "정상적인 없음" 상황일 수 있으므로 error가 아닌 info 수준으로 로깅
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

        // 4) 날짜 suffix 매칭 → 최신(updated) 선택
        candidates.sort((a, b) {
          final au = a.updated ?? DateTime.fromMillisecondsSinceEpoch(0);
          final bu = b.updated ?? DateTime.fromMillisecondsSinceEpoch(0);
          return au.compareTo(bu);
        });
        final objectName = candidates.last.name!;

        debugPrint(
          '📄 [GcsJsonUploader] 대상 객체 선택: $objectName (updated=${candidates.last.updated})',
        );

        // 5) 객체 다운로드 → JSON 디코드
        final dynamic res = await storage.objects.get(
          bucketName,
          objectName,
          downloadOptions: gcs.DownloadOptions.fullMedia,
        );
        if (res is! gcs.Media) {
          final msg =
              '예상치 못한 반환 타입: ${res.runtimeType}, Media가 아닙니다.';
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

        // 6) items 또는 data 배열 지원 (+ decoded가 List인 예외 케이스까지 방어)
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

          // ✅ { docId, data: {...} } 구조 지원
          final Map<String, dynamic>? dataMap =
          (map['data'] is Map) ? Map<String, dynamic>.from(map['data'] as Map) : null;

          // plate 후보(루트/래핑 모두 고려)
          final plateRaw = _pickPlateCandidate(map: map, dataMap: dataMap);
          final pd = _digitsOnly(plateRaw);

          final matches = pd.isNotEmpty &&
              ((needle.length >= 4 && pd.endsWith(needleTail4)) ||
                  (needle.isNotEmpty && pd == needle));
          if (!matches) continue;

          // ✅ logs 추출: map['logs'] 우선, 없으면 data.logs
          final logsRaw = map['logs'] ?? dataMap?['logs'];

          final logs = (logsRaw is List)
              ? logsRaw
              .whereType<Map>()
              .map((e) => Map<String, dynamic>.from(e))
              .toList()
              : const <Map<String, dynamic>>[];

          aggregated.addAll(logs);
        }

        // 7) timestamp 기준 정렬
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

        // invalid_token 계열이면 한 번은 rethrow해서 바깥에서 refreshIfNeeded()를 유도
        if (allowRethrowInvalid && GoogleAuthSession.isInvalidTokenError(e)) {
          rethrow;
        }

        return <Map<String, dynamic>>[];
      }
    }

    // 첫 번째 시도: invalid_token이면 예외를 바깥으로 던져 토큰 재발급/재시도를 유도
    try {
      return await runOnce(allowRethrowInvalid: true);
    } catch (e) {
      // invalid_token 계열이면 토큰 강제 갱신 후 한 번 더 시도
      if (GoogleAuthSession.isInvalidTokenError(e)) {
        debugPrint(
          '⚠️ [GcsJsonUploader] invalid_token 감지 -> 토큰 강제 갱신 후 재시도 시도 중...',
        );

        try {
          await GoogleAuthSession.instance.refreshIfNeeded();
        } catch (refreshError, refreshSt) {
          // 토큰 갱신 단계에서 실패해도 추가로 로깅만 남기고 빈 리스트 반환
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

        // 토큰 갱신 후 두 번째 시도 (이때는 invalid_token이어도 rethrow 안 함)
        return await runOnce(allowRethrowInvalid: false);
      }

      // invalid_token 이외의 예외는 여기까지 올라온 시점에서는 이미 로깅이 되어 있으므로
      // 별도 처리 없이 빈 리스트만 반환
      debugPrint(
        '❌ [GcsJsonUploader] plate 로그 조회 중 알 수 없는 오류가 발생했습니다. ($e)',
      );
      return <Map<String, dynamic>>[];
    }
  }

  // ─────────────────────────────────────────
  // 내부 헬퍼
  // ─────────────────────────────────────────

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

  static String _yyyymmdd(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
          '${d.month.toString().padLeft(2, '0')}-'
          '${d.day.toString().padLeft(2, '0')}';

  static String _yyyymm(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}'
          '${d.month.toString().padLeft(2, '0')}';

  static String _digitsOnly(String s) => s.replaceAll(RegExp(r'\D'), '');

  /// ✅ JSON 구조 호환성: 루트/래핑(data) 모두에서 plate 후보를 뽑아냅니다.
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

  /// Firestore Timestamp 타입을 흉내낸 다양한 timestamp 표현을 DateTime으로 변환
  static DateTime? _parseTs(dynamic ts) {
    if (ts == null) return null;

    // 정수: epoch ms 또는 epoch sec 추정
    if (ts is int) {
      if (ts > 100000000000) {
        // 대충 2001년 이후 ms 기준 정도로 판단
        return DateTime.fromMillisecondsSinceEpoch(ts).toLocal();
      }
      return DateTime.fromMillisecondsSinceEpoch(ts * 1000).toLocal();
    }

    // 문자열: ISO8601 시도
    if (ts is String) {
      return DateTime.tryParse(ts)?.toLocal();
    }

    return null;
  }
}
