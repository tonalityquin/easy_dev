import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:googleapis/storage/v1.dart' as storage;
import 'package:googleapis_auth/auth_io.dart';
import 'package:provider/provider.dart';
import 'package:flutter/material.dart';

import '../../states/area/area_state.dart';
import '../../states/user/user_state.dart';

class AttendanceUploader {
  static const _bucketName = 'easydev-image';
  static const _serviceAccountPath = 'assets/keys/easydev-97fb6-e31d7e6b30f9.json';

  /// 출근 JSON 업로드 함수 (중복 방지 포함)
  static Future<bool> uploadAttendanceJson({
    required BuildContext context,
    required Map<String, dynamic> attendanceData,
  }) async {
    try {
      final areaState = context.read<AreaState>();
      final userState = context.read<UserState>();

      final area = areaState.currentArea;
      final division = areaState.currentDivision;
      final userName = userState.name;

      final now = DateTime.now();
      final dateStr = '${now.year.toString().padLeft(4, '0')}-'
          '${now.month.toString().padLeft(2, '0')}-'
          '${now.day.toString().padLeft(2, '0')}';

      final fileName = '${dateStr}_${userName}_출근기록.json';
      final gcsPath = '$division/$area/exports/$fileName';

      // ✅ 중복 여부 확인
      final alreadyExists = await checkIfAlreadyUploaded(
        context: context,
        gcsPath: gcsPath,
      );

      if (alreadyExists) {
        debugPrint('⚠️ 출근 기록 이미 존재함: $gcsPath');
        return false;
      }

      // ✅ JSON 파일 생성 및 업로드
      final jsonContent = jsonEncode(attendanceData);
      final tempDir = Directory.systemTemp;
      final file = File('${tempDir.path}/$fileName');
      await file.writeAsString(jsonContent);

      final credentialsJson = await rootBundle.loadString(_serviceAccountPath);
      final credentials = ServiceAccountCredentials.fromJson(credentialsJson);
      final client = await clientViaServiceAccount(credentials, [storage.StorageApi.devstorageFullControlScope]);
      final storageApi = storage.StorageApi(client);

      final media = storage.Media(file.openRead(), file.lengthSync());
      final object = storage.Object()..name = gcsPath;

      await storageApi.objects.insert(object, _bucketName, uploadMedia: media);

      client.close();
      debugPrint('✅ 출근 기록 업로드 성공: $gcsPath');
      return true;
    } catch (e) {
      debugPrint('❌ 출근 기록 업로드 실패: $e');
      return false;
    }
  }

  /// GCS에 동일 경로의 파일이 이미 존재하는지 확인
  static Future<bool> checkIfAlreadyUploaded({
    required BuildContext context,
    required String gcsPath,
  }) async {
    try {
      final credentialsJson = await rootBundle.loadString(_serviceAccountPath);
      final credentials = ServiceAccountCredentials.fromJson(credentialsJson);
      final client = await clientViaServiceAccount(credentials, [storage.StorageApi.devstorageReadOnlyScope]);
      final storageApi = storage.StorageApi(client);

      await storageApi.objects.get(_bucketName, gcsPath);

      client.close();
      // 객체 조회 성공 = 파일 존재
      return true;
    } catch (e) {
      // 예외 발생 시 (예: 404) → 파일 존재하지 않음
      debugPrint('ℹ️ GCS 파일 존재하지 않거나 오류 발생: $e');
      return false;
    }
  }
}
