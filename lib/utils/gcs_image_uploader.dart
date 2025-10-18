// lib/utils/gcs_image_uploader.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:googleapis/storage/v1.dart' as gcs;

import 'google_auth_v7.dart';

class GcsImageUploader {
  final String bucketName = 'easydev-image';

  Future<String?> _uploadForImage(
      File file,
      String destinationPath, {
        String? purpose,
      }) async {
    if (destinationPath.trim().isEmpty) {
      debugPrint('⚠️ destinationPath가 비어있습니다.');
      return null;
    }

    final fileSize = await file.length();
    debugPrint('🚀 [$purpose] 이미지 업로드 시작: $destinationPath (${fileSize}B)');

    final client = await GoogleAuthV7.authedClient(
      [gcs.StorageApi.devstorageFullControlScope],
    );

    try {
      final storage = gcs.StorageApi(client);
      final media = gcs.Media(
        file.openRead(),
        fileSize,
        contentType: 'image/jpeg', // ✅ 명시적 콘텐츠 타입
      );

      final object = await storage.objects.insert(
        gcs.Object()..name = destinationPath,
        bucketName,
        uploadMedia: media,
        // UBLA 비활성 버킷: 공개 읽기
        predefinedAcl: 'publicRead',
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

  Future<String?> inputUploadImage(File imageFile, String destinationPath) =>
      _uploadForImage(imageFile, destinationPath, purpose: '입력 이미지');

  Future<String?> modifyUploadImage(File imageFile, String destinationPath) =>
      _uploadForImage(imageFile, destinationPath, purpose: '수정 이미지');
}
