import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:googleapis_auth/auth_io.dart';
import 'package:googleapis/storage/v1.dart';

class GcsImageUploader {
  final String bucketName = 'easydev-image';
  final String projectId = 'easydev-97fb6';
  final String serviceAccountPath = 'assets/keys/easydev-97fb6-e31d7e6b30f9.json';

  Future<String?> _uploadForImage(File file, String destinationPath, {String? purpose}) async {
    if (destinationPath.trim().isEmpty) {
      debugPrint('⚠️ destinationPath가 비어있습니다.');
      return null;
    }

    final fileSize = file.lengthSync();
    debugPrint('🚀 [$purpose] 이미지 업로드 시작: $destinationPath (${fileSize}B)');

    final credentialsJson = await rootBundle.loadString(serviceAccountPath);
    final accountCredentials = ServiceAccountCredentials.fromJson(credentialsJson);
    final scopes = [StorageApi.devstorageFullControlScope];
    final client = await clientViaServiceAccount(accountCredentials, scopes);

    try {
      final storage = StorageApi(client);
      final media = Media(file.openRead(), fileSize);

      final object = await storage.objects.insert(
        Object()
          ..name = destinationPath
          ..acl = [
            ObjectAccessControl()
              ..entity = 'allUsers'
              ..role = 'READER'
          ],
        bucketName,
        uploadMedia: media,
      );

      final url = 'https://storage.googleapis.com/$bucketName/${object.name}';
      debugPrint('✅ [$purpose] 이미지 업로드 완료: $url');
      return url;
    } catch (e, stack) {
      debugPrint('🔥 [$purpose] 이미지 업로드 실패: $e');
      debugPrint('🔥 Stack Trace: $stack');
      rethrow;
    } finally {
      client.close();
    }
  }

  Future<String?> inputUploadImage(File imageFile, String destinationPath) async {
    return await _uploadForImage(imageFile, destinationPath, purpose: '입력 이미지');
  }

  Future<String?> modifyUploadImage(File imageFile, String destinationPath) async {
    return await _uploadForImage(imageFile, destinationPath, purpose: '수정 이미지');
  }
}
