// lib/utils/gcs_uploader.dart
import 'dart:convert';
import 'dart:io';

import 'package:googleapis/storage/v1.dart' as gcs;
import 'google_auth_session.dart';

const String kBucketName = 'easydev-image';

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
  final dateStr = now.toIso8601String().split('T').first;
  final ts = now.millisecondsSinceEpoch;
  final safeUser = userName.replaceAll(RegExp(r'[^a-zA-Z0-9_\-\.]'), '_');
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
