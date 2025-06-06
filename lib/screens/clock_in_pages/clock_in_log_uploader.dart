import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:googleapis/storage/v1.dart' as storage;
import 'package:googleapis_auth/auth_io.dart';
import 'package:provider/provider.dart';
import 'package:flutter/material.dart';

import '../../states/area/area_state.dart';
import '../../states/user/user_state.dart';

class ClockInLogUploader {
  static const _bucketName = 'easydev-image';
  static const _serviceAccountPath = 'assets/keys/easydev-97fb6-e31d7e6b30f9.json';

  static Future<bool> uploadAttendanceJson({
    required BuildContext context,
    required String recordedTime, // ✅ 시간만 전달받고 JSON 구성은 이 안에서 함
  }) async {
    try {
      final areaState = context.read<AreaState>();
      final userState = context.read<UserState>();

      final area = areaState.currentArea;
      final division = areaState.currentDivision;
      final userName = userState.name;
      final userId = userState.user?.id ?? '';

      final now = DateTime.now();
      final dateStr = '${now.year.toString().padLeft(4, '0')}-'
          '${now.month.toString().padLeft(2, '0')}-'
          '${now.day.toString().padLeft(2, '0')}';

      final fileName = '${dateStr}_${userName}_clockIn.json';
      final gcsPath = '$division/$area/exports/$fileName';

      final alreadyExists = await checkIfAlreadyUploaded(
        context: context,
        gcsPath: gcsPath,
      );

      if (alreadyExists) {
        debugPrint('⚠️ 출근 기록 이미 존재함: $gcsPath');
        return false;
      }

      // ✅ JSON 데이터 구성
      final attendanceData = {
        'userId': userId,                // ✅ ID 포함
        'userName': userName,
        'area': area,
        'division': division,
        'recordedDate': dateStr,
        'recordedTime': recordedTime,
        'status': '출근',
      };

      final jsonContent = jsonEncode(attendanceData);
      final tempDir = Directory.systemTemp;
      final file = File('${tempDir.path}/$fileName');
      await file.writeAsString(jsonContent);

      final credentialsJson = await rootBundle.loadString(_serviceAccountPath);
      final credentials = ServiceAccountCredentials.fromJson(credentialsJson);
      final client = await clientViaServiceAccount(
        credentials,
        [storage.StorageApi.devstorageFullControlScope],
      );
      final storageApi = storage.StorageApi(client);

      final media = storage.Media(file.openRead(), file.lengthSync());
      final object = storage.Object()..name = gcsPath;

      // ✅ 업로드 시 공개 설정
      await storageApi.objects.insert(
        object,
        _bucketName,
        uploadMedia: media,
        predefinedAcl: 'publicRead',
      );

      client.close();
      debugPrint('✅ 출근 기록 업로드 성공 (공개됨): $gcsPath');
      return true;
    } catch (e) {
      debugPrint('❌ 출근 기록 업로드 실패: $e');
      return false;
    }
  }

  static Future<bool> checkIfAlreadyUploaded({
    required BuildContext context,
    required String gcsPath,
  }) async {
    try {
      final credentialsJson = await rootBundle.loadString(_serviceAccountPath);
      final credentials = ServiceAccountCredentials.fromJson(credentialsJson);
      final client = await clientViaServiceAccount(
        credentials,
        [storage.StorageApi.devstorageReadOnlyScope],
      );
      final storageApi = storage.StorageApi(client);

      await storageApi.objects.get(_bucketName, gcsPath);
      client.close();
      return true;
    } catch (e) {
      debugPrint('ℹ️ GCS 파일 존재하지 않거나 오류 발생: $e');
      return false;
    }
  }

  /// ✅ 다운로드 경로 생성용 함수
  static String getDownloadPath({
    required String division,
    required String area,
    required String userName,
    DateTime? dateTime,
  }) {
    final dt = dateTime ?? DateTime.now();
    final dateStr = '${dt.year.toString().padLeft(4, '0')}-'
        '${dt.month.toString().padLeft(2, '0')}-'
        '${dt.day.toString().padLeft(2, '0')}';
    final fileName = '${dateStr}_${userName}_clockIn.json';
    return 'https://storage.googleapis.com/$_bucketName/$division/$area/exports/$fileName';
  }
}
