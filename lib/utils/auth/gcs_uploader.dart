import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:googleapis/storage/v1.dart' as gcs;

import '../../features/dev/debug/debug_api_logger.dart';
import 'google_auth_session.dart';

import '../../core/config/external_ids.dart';
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

Future<gcs.Object> _uploadJsonToGcs({
  required Map<String, dynamic> json,
  required String destinationPath,
  required String purpose,
  bool makePublicRead = true,
}) async {
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
      final tempPath =
          '${Directory.systemTemp.path}/gcs_upload_${DateTime.now().microsecondsSinceEpoch}.json';
      temp = File(tempPath);
      await temp.writeAsString(jsonEncode(json), encoding: utf8);

      final length = await temp.length();

      debugPrint(
        '🚀 [$purpose] JSON 업로드 시작: '
        'bucket=$kBucketName, path=$destinationPath (${length}B)',
      );

      final client = await GoogleAuthSession.instance.safeClient();

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

        rethrow;
      }

      return await runOnce(allowRethrowInvalid: false);
    }

    rethrow;
  }
}

Future<String?> uploadEndLogJson({
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

  final fileName = '${safeUser}_${ts}_ToDoLogs_${dateStr}.json';

  final path = '$division/$area/logs/$monthKey/$ts/$fileName';

  final enriched = <String, dynamic>{
    ...report,
    'uploadedAt': now.toIso8601String(),
    'uploadedBy': userName,
    'monthKey': monthKey,
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
