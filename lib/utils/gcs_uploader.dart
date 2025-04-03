import 'dart:io';
import 'package:flutter/services.dart'; // ✅ asset 로드를 위한 import
import 'package:googleapis_auth/auth_io.dart';
import 'package:googleapis/storage/v1.dart';

class GCSUploader {
  final String bucketName = 'easydev-image'; // GCS 버킷 이름
  final String projectId = 'easydev-97fb6';  // GCP 프로젝트 ID
  final String serviceAccountPath = 'assets/keys/easydev-97fb6-e31d7e6b30f9.json'; // assets 내 JSON 키 경로

  /// ✅ input_3_digit.dart 전용 업로드
  Future<String?> uploadImageFromInput(File imageFile, String destinationPath) async {
    return await _upload(imageFile, destinationPath);
  }

  /// ✅ modify_plate_info.dart 전용 업로드
  Future<String?> uploadImageFromModify(File imageFile, String destinationPath) async {
    return await _upload(imageFile, destinationPath);
  }

  /// 🔁 내부 공통 업로드 처리 로직
  Future<String?> _upload(File imageFile, String destinationPath) async {
    try {
      // ✅ Flutter asset에서 JSON 키 파일 로드
      final credentialsJson = await rootBundle.loadString(serviceAccountPath);

      final accountCredentials = ServiceAccountCredentials.fromJson(credentialsJson);
      final scopes = [StorageApi.devstorageFullControlScope];

      final client = await clientViaServiceAccount(accountCredentials, scopes);
      final storage = StorageApi(client);

      final media = Media(imageFile.openRead(), imageFile.lengthSync());

      final object = await storage.objects.insert(
        Object()
          ..name = destinationPath
          ..acl = [
            ObjectAccessControl()
              ..entity = 'allUsers'
              ..role = 'READER' // ✅ 공개 권한 부여
          ],
        bucketName,
        uploadMedia: media,
      );

      client.close();

      // ✅ 업로드된 파일의 공개 URL 반환
      return 'https://storage.googleapis.com/$bucketName/${object.name}';
    } catch (e, stack) {
      print('🔥 GCS 업로드 실패: $e');
      print('🔥 Stack Trace: $stack');
      rethrow; // ⛔ 또는 showFailedSnackbar()로 스낵바 출력도 가능
    }
  }
}
