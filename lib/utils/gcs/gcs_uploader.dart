// File: lib/utils/gcs_uploader.dart
//
// 변경 사항 요약
// - 파일명에서 사용자 이름 한글 허용(정규식 완화) + 비정상 케이스 대비 fallback 적용
// - 로그 업로드 파일명을 불러오기 로직이 찾는 접미사("_ToDoLogs_YYYY-MM-DD.json")로 고정
//   예) belivus/가로수길(캔버스랩)/logs/1759837031216/user_1759837031216_ToDoLogs_2025-10-07.json
//   (logs/<timestamp>/ 하위에 저장하므로 충돌 방지)
// - GCS 업로드 시 GoogleAuthSession 기반 invalid_token 방어:
//   * 1차 시도 실패 시 invalid_token 이면 refreshIfNeeded() 호출 후 1회 재시도
//   * 실패/예외 상황은 DebugApiLogger에 상세 로깅
//   * 기존처럼 예외를 상위(EndWorkReportService 등)로 그대로 던지는 동작 유지

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:googleapis/storage/v1.dart' as gcs;

import '../google_auth_session.dart';
import '../../screens/dev_package/debug_package/debug_api_logger.dart';

const String kBucketName = 'easydev-image';

String _sanitizeFileComponent(String input) {
  // 한글, 영문, 숫자, '_', '-', '.'만 허용. 기타 문자는 '_'
  final s = input
      .replaceAll(RegExp(r'[^0-9A-Za-z가-힣_.-]'), '_')
      .replaceAll(RegExp(r'_+'), '_')
      .trim();
  // 전부 '_' 이거나 빈 문자열이면 fallback
  if (s.isEmpty || RegExp(r'^_+$').hasMatch(s)) return 'user';
  return s;
}

/// 공통 JSON 업로드 유틸 (GCS)
///
/// - [json]: 업로드할 JSON Map
/// - [destinationPath]: GCS object name (예: "division/area/reports/xxx.json")
/// - [purpose]: 로깅용 설명 문자열 (예: "업무 종료 보고", "업무 종료 로그")
/// - [makePublicRead]: publicRead ACL 적용 여부
///
/// invalid_token 방어 로직:
/// - 1차 시도에서 invalid_token 감지 시 예외 rethrow → 바깥에서 refreshIfNeeded 호출
/// - refreshIfNeeded 성공 후 2차 시도 (allowRethrowInvalid=false)
/// - 2차 시도 실패 포함 모든 예외는 그대로 상위로 던짐 (기존 호출부의 try/catch와 호환)
Future<gcs.Object> _uploadJsonToGcs({
  required Map<String, dynamic> json,
  required String destinationPath,
  required String purpose,
  bool makePublicRead = true,
}) async {
  // destinationPath 기본 검증
  if (destinationPath.trim().isEmpty) {
    const msg = 'destinationPath가 비어 있어 JSON을 업로드할 수 없습니다.';
    debugPrint('⚠️ [$purpose] $msg');

    await DebugApiLogger().log(
      {
        'tag': 'gcs_uploader._uploadJsonToGcs',
        'message': 'JSON 업로드 실패 - destinationPath 미설정',
        'reason': 'validation_failed',
        'bucketName': kBucketName,
        'destinationPath': destinationPath,
        'purpose': purpose,
        'payloadKeys': json.keys.toList(),
      },
      level: 'error',
      tags: const ['gcs', 'json_upload', 'validation'],
    );

    throw ArgumentError('destinationPath must not be empty');
  }

  Future<gcs.Object> runOnce({required bool allowRethrowInvalid}) async {
    File? temp;
    try {
      // 1) 임시 파일 생성 및 JSON 기록
      final tempPath =
          '${Directory.systemTemp.path}/gcs_upload_${DateTime.now().microsecondsSinceEpoch}.json';
      temp = File(tempPath);
      await temp.writeAsString(jsonEncode(json), encoding: utf8);

      final length = await temp.length();

      debugPrint(
        '🚀 [$purpose] JSON 업로드 시작: '
            'bucket=$kBucketName, path=$destinationPath (${length}B)',
      );

      // 2) 중앙 OAuth 세션에서 AuthClient 획득
      final client = await GoogleAuthSession.instance.safeClient();

      // 3) GCS Storage API 사용
      final storage = gcs.StorageApi(client);
      final media = gcs.Media(
        temp.openRead(),
        length,
        contentType: 'application/json',
      );

      final object = gcs.Object()..name = destinationPath;

      final res = await storage.objects.insert(
        object,
        kBucketName,
        uploadMedia: media,
        predefinedAcl: makePublicRead ? 'publicRead' : null,
      );

      debugPrint(
        '✅ [$purpose] JSON 업로드 성공: '
            'bucket=$kBucketName, objectName=${res.name}',
      );

      return res;
    } catch (e, st) {
      final msg = 'JSON을 GCS에 업로드하는 중 오류가 발생했습니다. ($e)';
      debugPrint('🔥 [$purpose] $msg');

      await DebugApiLogger().log(
        {
          'tag': 'gcs_uploader._uploadJsonToGcs',
          'message': 'JSON 업로드 중 예외 발생',
          'reason': 'exception',
          'error': e.toString(),
          'stack': st.toString(),
          'bucketName': kBucketName,
          'destinationPath': destinationPath,
          'purpose': purpose,
          'payloadKeys': json.keys.toList(),
        },
        level: 'error',
        tags: const ['gcs', 'json_upload', 'exception'],
      );

      // invalid_token 계열이면 한 번은 rethrow해서 바깥에서 refreshIfNeeded()를 유도
      if (allowRethrowInvalid && GoogleAuthSession.isInvalidTokenError(e)) {
        rethrow;
      }

      // 그 외 예외는 그대로 상위로 던져서 기존 호출부(EndWorkReportService)의 try/catch에서 처리하도록 유지
      rethrow;
    } finally {
      if (temp != null) {
        try {
          await temp.delete();
        } catch (_) {
          // temp 삭제 실패는 치명적이지 않으므로 무시
        }
      }
    }
  }

  // 1차 시도: invalid_token이면 예외를 바깥으로 던져 토큰 재발급/재시도를 유도
  try {
    return await runOnce(allowRethrowInvalid: true);
  } catch (e) {
    // invalid_token 계열이면 토큰 강제 갱신 후 한 번 더 시도
    if (GoogleAuthSession.isInvalidTokenError(e)) {
      debugPrint(
        '⚠️ [$purpose] invalid_token 감지 -> 토큰 강제 갱신 후 재시도 시도 중...',
      );

      try {
        await GoogleAuthSession.instance.refreshIfNeeded();
      } catch (refreshError, refreshSt) {
        final msg =
            '토큰 강제 갱신(refreshIfNeeded) 중 오류가 발생했습니다. ($refreshError)';
        debugPrint('🔥 [$purpose] $msg');

        await DebugApiLogger().log(
          {
            'tag': 'gcs_uploader._uploadJsonToGcs',
            'message': '토큰 강제 갱신(refreshIfNeeded) 실패',
            'reason': 'refresh_failed',
            'error': refreshError.toString(),
            'stack': refreshSt.toString(),
            'bucketName': kBucketName,
            'destinationPath': destinationPath,
            'purpose': purpose,
          },
          level: 'error',
          tags: const ['gcs', 'json_upload', 'auth'],
        );

        // 리프레시 단계에서 실패하면 더 이상 시도할 수 없으므로 그대로 상위로 던짐
        rethrow;
      }

      // 토큰 갱신 후 두 번째 시도 (이때는 invalid_token이어도 rethrow 안 함)
      return await runOnce(allowRethrowInvalid: false);
    }

    // invalid_token 이외의 예외는 그대로 상위로 전달
    rethrow;
  }
}

/// 업무 종료 보고 JSON 업로드
///
/// - 저장 경로:
///   <division>/<area>/reports/report_{safeUser}_{YYYY-MM-DD}_{timestamp}.json
///
/// - 반환:
///   성공 시 public URL (https://storage.googleapis.com/...)
///   실패 시 null (예외는 상위에서 catch 가능)
Future<String?> uploadEndWorkReportJson({
  required Map<String, dynamic> report,
  required String division,
  required String area,
  required String userName,
}) async {
  final now = DateTime.now();
  final dateStr = now.toIso8601String().split('T').first; // YYYY-MM-DD
  final ts = now.millisecondsSinceEpoch;
  final safeUser = _sanitizeFileComponent(userName);

  final fileName = 'report_${safeUser}_${dateStr}_$ts.json';
  final path = '$division/$area/reports/$fileName';

  final enriched = <String, dynamic>{
    ...report,
    'uploadedAt': now.toIso8601String(),
    'uploadedBy': userName,
  };

  final res = await _uploadJsonToGcs(
    json: enriched,
    destinationPath: path,
    purpose: '업무 종료 보고(report) JSON',
  );

  return res.name != null
      ? 'https://storage.googleapis.com/$kBucketName/${res.name}'
      : null;
}

/// 출차 로그 묶음 업로드
///
/// - 파일명 끝을 "_ToDoLogs_YYYY-MM-DD.json"으로 고정하여
///   GcsJsonUploader.loadPlateLogs 의 불러오기 로직과 100% 호환.
/// - 상위 경로: <division>/<area>/logs/<timestamp>/
///   (동명이인 혹은 재업로드 충돌 방지용)
///
/// - 예: belivus/가로수길(캔버스랩)/logs/1759837031216/user_1759837031216_ToDoLogs_2025-10-07.json
///
/// - 반환:
///   성공 시 public URL
///   실패 시 null (예외는 상위에서 catch 가능)
Future<String?> uploadEndLogJson({
  required Map<String, dynamic> report,
  required String division,
  required String area,
  required String userName,
}) async {
  final now = DateTime.now();
  final dateStr = now.toIso8601String().split('T').first; // YYYY-MM-DD
  final ts = now.millisecondsSinceEpoch;
  final safeUser = _sanitizeFileComponent(userName);

  // ✅ 문자열 보간 수정: '${ts}_ToDoLogs_' 형태로
  final fileName = '${safeUser}_${ts}_ToDoLogs_${dateStr}.json';
  final path = '$division/$area/logs/$ts/$fileName';

  final enriched = <String, dynamic>{
    ...report,
    'uploadedAt': now.toIso8601String(),
    'uploadedBy': userName,
  };

  final res = await _uploadJsonToGcs(
    json: enriched,
    destinationPath: path,
    purpose: '업무 종료 로그(logs) JSON',
  );

  return res.name != null
      ? 'https://storage.googleapis.com/$kBucketName/${res.name}'
      : null;
}
