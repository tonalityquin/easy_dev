// lib/utils/gcs_uploader.dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;
import 'package:googleapis/storage/v1.dart' as gcs;
import 'package:googleapis_auth/auth_io.dart';

/// 프로젝트에 맞게 조정
const String kBucketName = 'easydev-image';
const String kServiceAccountPath = 'assets/keys/easydev-97fb6-e31d7e6b30f9.json';

/// 내부 공통 업로드 헬퍼
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

  // 2) 서비스 계정으로 인증
  final credentialsJson = await rootBundle.loadString(kServiceAccountPath);
  final accountCredentials = ServiceAccountCredentials.fromJson(credentialsJson);

  final client = await clientViaServiceAccount(
    accountCredentials,
    [gcs.StorageApi.devstorageFullControlScope],
  );

  try {
    final storage = gcs.StorageApi(client);

    final media = gcs.Media(
      temp.openRead(),
      await temp.length(),
      contentType: 'application/json',
    );

    final object = gcs.Object()
      ..name = destinationPath
      ..contentDisposition = 'attachment';

    if (makePublicRead) {
      // 버킷이 Uniform bucket-level access(UBLA)를 사용하지 않을 때만 유효
      object.acl = [
        gcs.ObjectAccessControl()
          ..entity = 'allUsers'
          ..role = 'READER'
      ];
    }

    // 업로드
    final res = await storage.objects.insert(
      object,
      kBucketName,
      uploadMedia: media,
      // UBLA 사용하는 버킷이면 위 ACL 대신 아래 옵션 사용을 고려:
      // predefinedAcl: 'publicRead',
    );

    return res;
  } finally {
    client.close();
    try {
      await temp.delete();
    } catch (_) {}
  }
}

/// 업무 종료 보고 본문 업로드
Future<String?> uploadEndWorkReportJson({
  required Map<String, dynamic> report,
  required String division,
  required String area,
  required String userName,
}) async {
  final now = DateTime.now();
  final dateStr = now.toIso8601String().split('T').first;
  final ts = now.millisecondsSinceEpoch; // 중복 방지용 suffix
  final safeUser = userName.replaceAll(RegExp(r'[^a-zA-Z0-9_\-\.]'), '_');
  final fileName = 'report_${safeUser}_$dateStr\_$ts.json';
  final path = '$division/$area/reports/$fileName';

  final res = await _uploadJsonToGcs(
    json: {
      ...report,
      'uploadedAt': now.toIso8601String(),
      'uploadedBy': userName,
    },
    destinationPath: path,
  );

  // res는 googleapis의 gcs.Object
  if (res.name != null) {
    return 'https://storage.googleapis.com/$kBucketName/${res.name}';
  }
  return null;
}

/// 보고 로그 묶음 업로드
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
  final fileName = 'logs_${safeUser}_$dateStr\_$ts.json';
  final path = '$division/$area/logs/$fileName';

  final res = await _uploadJsonToGcs(
    json: {
      ...report,
      'uploadedAt': now.toIso8601String(),
      'uploadedBy': userName,
    },
    destinationPath: path,
  );

  if (res.name != null) {
    return 'https://storage.googleapis.com/$kBucketName/${res.name}';
  }
  return null;
}
