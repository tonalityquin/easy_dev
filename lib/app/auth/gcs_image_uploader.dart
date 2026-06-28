import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:googleapis/storage/v1.dart' as gcs;

import '../../app/config/auth_config.dart';
import '../../features/dev/debug/debug_api_logger.dart';
import 'google_auth_session.dart';

class GcsImageUploader {
  final String bucketName;

  GcsImageUploader({String? bucketName})
      : bucketName = bucketName ?? AuthConfig.gcsBucketName;

  Future<String?> _uploadForImage(  
    File file,
    String destinationPath, {
    String? purpose,
  }) async {
    final String uploadPurpose = purpose ?? '이미지';
    String? objectUrl;

    Future<String?> runOnce({required bool allowRethrowInvalid}) async {
      try {
        if (destinationPath.trim().isEmpty) {
          const msg = 'destinationPath가 비어있어 이미지를 업로드할 수 없습니다.';
          debugPrint('⚠️ [$uploadPurpose] $msg');

          await DebugApiLogger().log(
            {
              'tag': 'GcsImageUploader._uploadForImage',
              'message': '이미지 업로드 실패 - destinationPath 미설정',
              'reason': 'validation_failed',
              'bucketName': bucketName,
              'destinationPath': destinationPath,
              'purpose': uploadPurpose,
              'filePath': file.path,
            },
            level: 'error',
            tags: const ['gcs', 'image_upload', 'validation'],
          );

          return null;
        }

        final exists = await file.exists();
        if (!exists) {
          final msg = '업로드 대상 파일이 존재하지 않습니다. path=${file.path}';
          debugPrint('⚠️ [$uploadPurpose] $msg');

          await DebugApiLogger().log(
            {
              'tag': 'GcsImageUploader._uploadForImage',
              'message': '이미지 업로드 실패 - 파일 미존재',
              'reason': 'file_not_found',
              'bucketName': bucketName,
              'destinationPath': destinationPath,
              'purpose': uploadPurpose,
              'filePath': file.path,
            },
            level: 'error',
            tags: const ['gcs', 'image_upload', 'file'],
          );

          return null;
        }

        final fileSize = await file.length();
        if (fileSize <= 0) {
          final msg = '업로드 대상 파일 크기가 0B 입니다. path=${file.path}';
          debugPrint('⚠️ [$uploadPurpose] $msg');

          await DebugApiLogger().log(
            {
              'tag': 'GcsImageUploader._uploadForImage',
              'message': '이미지 업로드 실패 - 파일 크기 0',
              'reason': 'file_empty',
              'bucketName': bucketName,
              'destinationPath': destinationPath,
              'purpose': uploadPurpose,
              'filePath': file.path,
              'fileSize': fileSize,
            },
            level: 'error',
            tags: const ['gcs', 'image_upload', 'file'],
          );

          return null;
        }

        debugPrint(
          '🚀 [$uploadPurpose] 이미지 업로드 시작: '
          'bucket=$bucketName, path=$destinationPath (${fileSize}B)',
        );

        final client = await GoogleAuthSession.instance.safeClient();

        final storage = gcs.StorageApi(client);
        final media =
            gcs.Media(file.openRead(), fileSize, contentType: 'image/jpeg');

        final object = await storage.objects.insert(
          gcs.Object()..name = destinationPath,
          bucketName,
          uploadMedia: media,
          predefinedAcl: 'publicRead',
        );

        objectUrl = 'https://storage.googleapis.com/$bucketName/${object.name}';

        debugPrint('✅ [$uploadPurpose] 이미지 업로드 완료: $objectUrl');

        return objectUrl;
      } catch (e, st) {
        final msg = '이미지를 GCS에 업로드하는 중 오류가 발생했습니다. ($e)';
        debugPrint('🔥 [$uploadPurpose] $msg');

        await DebugApiLogger().log(
          {
            'tag': 'GcsImageUploader._uploadForImage',
            'message': '이미지 업로드 중 예외 발생',
            'reason': 'exception',
            'error': e.toString(),
            'stack': st.toString(),
            'bucketName': bucketName,
            'destinationPath': destinationPath,
            'purpose': uploadPurpose,
            'filePath': file.path,
            'objectUrl': objectUrl,
          },
          level: 'error',
          tags: const ['gcs', 'image_upload', 'exception'],
        );

        if (allowRethrowInvalid && GoogleAuthSession.isInvalidTokenError(e)) {
          rethrow;
        }

        return null;
      }
    }

    try {
      return await runOnce(allowRethrowInvalid: true);
    } catch (e) {
      if (GoogleAuthSession.isInvalidTokenError(e)) {
        debugPrint(
          '⚠️ [$uploadPurpose] invalid_token 감지 -> 토큰 강제 갱신 후 재시도 시도 중...',
        );

        try {
          await GoogleAuthSession.instance.refreshIfNeeded();
        } catch (refreshError, refreshSt) {
          await DebugApiLogger().log(
            {
              'tag': 'GcsImageUploader._uploadForImage',
              'message': '토큰 강제 갱신(refreshIfNeeded) 실패',
              'reason': 'refresh_failed',
              'error': refreshError.toString(),
              'stack': refreshSt.toString(),
              'bucketName': bucketName,
              'destinationPath': destinationPath,
              'purpose': uploadPurpose,
              'filePath': file.path,
            },
            level: 'error',
            tags: const ['gcs', 'image_upload', 'auth'],
          );
          return null;
        }

        return await runOnce(allowRethrowInvalid: false);
      }

      debugPrint(
        '❌ [$uploadPurpose] 이미지 업로드 중 알 수 없는 오류가 발생했습니다. ($e)',
      );
      return null;
    }
  }

  Future<String?> inputUploadImage(
    File imageFile,
    String destinationPath,
  ) =>
      _uploadForImage(
        imageFile,
        destinationPath,
        purpose: '입력 이미지',
      );

  Future<String?> modifyUploadImage(
    File imageFile,
    String destinationPath,
  ) =>
      _uploadForImage(
        imageFile,
        destinationPath,
        purpose: '수정 이미지',
      );
}
