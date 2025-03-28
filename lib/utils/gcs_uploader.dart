import 'dart:io';
import 'package:flutter/services.dart'; // ✅ asset 로드를 위한 import
import 'package:googleapis_auth/auth_io.dart';
import 'package:googleapis/storage/v1.dart';

class GCSUploader {
  final String bucketName = 'easydev-image'; // GCS 버킷 이름
  final String projectId = 'easydev-97fb6';  // GCP 프로젝트 ID
  final String serviceAccountPath = 'assets/keys/easydev-97fb6-967c8fd3f926.json'; // assets 내 JSON 키 경로

  Future<String?> uploadImage(File imageFile, String destinationPath) async {
    try {
      // ✅ Flutter asset에서 JSON 파일 로드
      final credentialsJson = await rootBundle.loadString(serviceAccountPath);

      final accountCredentials = ServiceAccountCredentials.fromJson(credentialsJson);
      final scopes = [StorageApi.devstorageFullControlScope];

      final client = await clientViaServiceAccount(accountCredentials, scopes);
      final storage = StorageApi(client);

      final media = Media(imageFile.openRead(), imageFile.lengthSync());

      final object = await storage.objects.insert(
        Object()
          ..name = destinationPath
          ..acl = [ObjectAccessControl()
            ..entity = 'allUsers'
            ..role = 'READER'], // 👈 여기가 자동 공개 설정!
        bucketName,
        uploadMedia: media,
      );

      client.close();

      // ✅ 업로드된 파일의 공개 URL 반환
      return 'https://storage.googleapis.com/$bucketName/${object.name}';
    } catch (e) {
      print('🔥 GCS 업로드 실패: $e');
      return null;
    }
  }
}
