// File: lib/utils/gcs_image_uploader.dart

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:googleapis/storage/v1.dart' as gcs;

import '../google_auth_session.dart';
import '../../screens/hubs_mode/dev_package/debug_package/debug_api_logger.dart';

/// GCS(easydev-image 버킷)에 이미지를 업로드하는 유틸
///
/// - 중앙 OAuth 세션(GoogleAuthSession)을 사용해 인증
/// - 토큰 만료/invalid_token 시 ClockOutLogUploader와 동일하게
///   1회 refreshIfNeeded() 후 재시도
/// - 실패 시 null 반환 + DebugApiLogger 로깅
class GcsImageUploader {
  /// 기본 버킷명 (필요하면 생성자에서 override 가능)
  final String bucketName;

  GcsImageUploader({String? bucketName})
      : bucketName = bucketName ?? 'easydev-image';

  /// 내부 공통 업로드 함수
  ///
  /// - [file]: 업로드할 이미지 파일
  /// - [destinationPath]: GCS object name (예: "commute/2025/11/19/xxx.jpg")
  /// - [purpose]: 로그용 용도 설명(입력 이미지 / 수정 이미지 등)
  Future<String?> _uploadForImage(
      File file,
      String destinationPath, {
        String? purpose,
      }) async {
    final String uploadPurpose = purpose ?? '이미지';
    String? objectUrl;

    Future<String?> runOnce({required bool allowRethrowInvalid}) async {
      try {
        // 0) destinationPath 검증
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

        // 1) 파일 존재/크기 검증
        final exists = await file.exists();
        if (!exists) {
          final msg =
              '업로드 대상 파일이 존재하지 않습니다. path=${file.path}';
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
          final msg =
              '업로드 대상 파일 크기가 0B 입니다. path=${file.path}';
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

        // 2) 중앙 OAuth 세션에서 AuthClient 획득
        final client = await GoogleAuthSession.instance.safeClient();

        // 3) GCS Storage API 사용
        final storage = gcs.StorageApi(client);
        final media =
        gcs.Media(file.openRead(), fileSize, contentType: 'image/jpeg');

        final object = await storage.objects.insert(
          gcs.Object()..name = destinationPath,
          bucketName,
          uploadMedia: media,
          // UBLA 비활성 버킷: 공개 읽기
          predefinedAcl: 'publicRead',
        );

        objectUrl =
        'https://storage.googleapis.com/$bucketName/${object.name}';

        debugPrint('✅ [$uploadPurpose] 이미지 업로드 완료: $objectUrl');

        return objectUrl;
      } catch (e, st) {
        final msg =
            '이미지를 GCS에 업로드하는 중 오류가 발생했습니다. ($e)';
        debugPrint('🔥 [$uploadPurpose] $msg');

        // 🔴 예외 상세 로깅
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

        // invalid_token 계열이면 한 번은 rethrow해서 바깥에서 refreshIfNeeded()를 유도
        if (allowRethrowInvalid && GoogleAuthSession.isInvalidTokenError(e)) {
          rethrow;
        }

        return null;
      }
    }

    // 첫 번째 시도: invalid_token이면 예외를 바깥으로 던져 토큰 재발급/재시도를 유도
    try {
      return await runOnce(allowRethrowInvalid: true);
    } catch (e) {
      // invalid_token 계열이면 토큰 강제 갱신 후 한 번 더 시도
      if (GoogleAuthSession.isInvalidTokenError(e)) {
        debugPrint(
          '⚠️ [$uploadPurpose] invalid_token 감지 -> 토큰 강제 갱신 후 재시도 시도 중...',
        );

        try {
          await GoogleAuthSession.instance.refreshIfNeeded();
        } catch (refreshError, refreshSt) {
          // 토큰 갱신 단계에서 실패해도 추가로 로깅만 남기고 null 반환
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

        // 토큰 갱신 후 두 번째 시도 (이때는 invalid_token이어도 rethrow 안 함)
        return await runOnce(allowRethrowInvalid: false);
      }

      // invalid_token 이외의 예외는 여기까지 올라온 시점에서는 이미 로깅이 되어 있으므로
      // 별도 처리 없이 null만 반환
      debugPrint(
        '❌ [$uploadPurpose] 이미지 업로드 중 알 수 없는 오류가 발생했습니다. ($e)',
      );
      return null;
    }
  }

  /// 입력 이미지 업로드
  Future<String?> inputUploadImage(
      File imageFile,
      String destinationPath,
      ) =>
      _uploadForImage(
        imageFile,
        destinationPath,
        purpose: '입력 이미지',
      );

  /// 수정 이미지 업로드
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
