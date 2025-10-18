// lib/utils/gcs_uploader.dart
import 'dart:convert';
import 'dart:io';

import 'package:googleapis/storage/v1.dart' as gcs;
import 'google_auth_v7.dart';

const String kBucketName = 'easydev-image';

Future<gcs.Object> _uploadJsonToGcs({
  required Map<String, dynamic> json,
  required String destinationPath,
  bool makePublicRead = true,
}) async {
  // 1) 임시 파일 생성
  final temp = File(
    '${Directory.systemTemp.path}/gcs_upload_${DateTime.now().microsecondsSinceEpoch}.json',
  );
  await temp.writeAsString(jsonEncode(json), encoding: utf8);

  // 2) OAuth 클라이언트
  final client = await GoogleAuthV7.authedClient(
    [gcs.StorageApi.devstorageFullControlScope],
  );

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
    client.close();
    try {
      await temp.delete();
    } catch (_) {}
  }
}

Future<String?> uploadEndWorkReportJson({
  required Map<String, dynamic> report,
  required String division,
  required String area,
  required String userName,
}) async {
  final now = DateTime.now();
  final dateStr = now.toIso8601String().split('T').first;
  final ts = now.millisecondsSinceEpoch;
  final safeUser = userName.replaceAll(RegExp(r'[^a-zA-Z0-9_\-\.]'), '_');

  // ✅ 보간 변수 뒤에 문자를 붙일 땐 중괄호 사용
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

Future<String?> uploadEndLogJson({
  required Map<String, dynamic> report,
  required String division,
  required String area,
  required String userName,
}) async {
  final now = DateTime.now();
  final dateStr = now.toIso8601String().split('T').first;
  final ts = now.millisecondsSinceEpoch;
  final safeUser = userName.replaceAll(RegExp(r'[^a-zA-Z0-9_\-\.]'), '_');

  // ✅ 동일 수정
  final fileName = 'logs_${safeUser}_${dateStr}_$ts.json';
  final path = '$division/$area/logs/$fileName';

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
