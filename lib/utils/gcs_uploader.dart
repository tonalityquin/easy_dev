// lib/utils/gcs_uploader.dart
//
// 변경 사항 요약
// - 파일명에서 사용자 이름 한글 허용(정규식 완화) + 비정상 케이스 대비 fallback 적용
// - 로그 업로드 파일명을 불러오기 로직이 찾는 접미사("_ToDoLogs_YYYY-MM-DD.json")로 고정
//   예) belivus/가로수길(캔버스랩)/logs/1759837031216/user_1759837031216_ToDoLogs_2025-10-07.json
//   (logs/<timestamp>/ 하위에 저장하므로 충돌 방지)

import 'dart:convert';
import 'dart:io';

import 'package:googleapis/storage/v1.dart' as gcs;
import 'google_auth_session.dart';

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

Future<gcs.Object> _uploadJsonToGcs({
  required Map<String, dynamic> json,
  required String destinationPath,
  bool makePublicRead = true,
}) async {
  final temp = File(
    '${Directory.systemTemp.path}/gcs_upload_${DateTime.now().microsecondsSinceEpoch}.json',
  );
  await temp.writeAsString(jsonEncode(json), encoding: utf8);

  final client = await GoogleAuthSession.instance.client();

  try {
    final storage = gcs.StorageApi(client);
    final media = gcs.Media(
      temp.openRead(),
      await temp.length(),
      contentType: 'application/json',
    );

    final object = gcs.Object()..name = destinationPath;

    final res = await storage.objects.insert(
      object,
      kBucketName,
      uploadMedia: media,
      predefinedAcl: makePublicRead ? 'publicRead' : null,
    );
    return res;
  } finally {
    try {
      await temp.delete();
    } catch (_) {}
    // 세션 클라이언트는 닫지 않습니다.
  }
}

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

  final res = await _uploadJsonToGcs(
    json: {
      ...report,
      'uploadedAt': now.toIso8601String(),
      'uploadedBy': userName,
    },
    destinationPath: path,
  );
  return res.name != null
      ? 'https://storage.googleapis.com/$kBucketName/${res.name}'
      : null;
}

/// 출차 로그 묶음 업로드
/// - 파일명 끝을 "_ToDoLogs_YYYY-MM-DD.json"으로 고정하여 불러오기 로직과 100% 호환.
/// - 상위 경로: <division>/<area>/logs/<timestamp>/
///   (동명이인 혹은 재업로드 충돌 방지용)
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

  final res = await _uploadJsonToGcs(
    json: {
      ...report,
      'uploadedAt': now.toIso8601String(),
      'uploadedBy': userName,
    },
    destinationPath: path,
  );
  return res.name != null
      ? 'https://storage.googleapis.com/$kBucketName/${res.name}'
      : null;
}
