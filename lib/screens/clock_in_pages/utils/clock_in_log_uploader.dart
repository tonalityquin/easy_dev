import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:googleapis/storage/v1.dart' as storage;
import 'package:googleapis_auth/auth_io.dart';
import 'package:provider/provider.dart';
import 'package:flutter/material.dart';

import '../../../states/area/area_state.dart';
import '../../../states/user/user_state.dart';
import '../debugs/clock_in_debug_firestore_logger.dart'; // ✅ 로컬 로거 추가

class ClockInLogUploader {
  static const _bucketName = 'easydev-image';
  static const _serviceAccountPath = 'assets/keys/easydev-97fb6-e31d7e6b30f9.json';

  static Future<bool> uploadAttendanceJson({
    required BuildContext context,
    required String recordedTime,
  }) async {
    final logger = ClockInDebugFirestoreLogger(); // ✅ 로컬 로거 인스턴스

    try {
      logger.log('uploadAttendanceJson() 시작', level: 'called');

      final areaState = context.read<AreaState>();
      final userState = context.read<UserState>();

      final areaForGcs = userState.user?.englishSelectedAreaName ?? '';
      final area = userState.user?.selectedArea ?? '';
      final division = areaState.currentDivision;
      final userName = userState.name;
      final userId = userState.user?.id ?? '';

      if (area.isEmpty || userId.isEmpty) {
        logger.log('❌ 유효하지 않은 area 또는 userId', level: 'error');
        return false;
      }

      final now = DateTime.now();
      final year = now.year.toString().padLeft(4, '0');
      final month = now.month.toString().padLeft(2, '0');
      final day = now.day.toString().padLeft(2, '0');
      final dateStr = '$year-$month-$day';

      final gcsPath = '$division/$areaForGcs/exports/clock_in/$year/$month/$userId.json';

      final newRecord = {
        'userId': userId,
        'userName': userName,
        'area': area,
        'division': division,
        'recordedDate': dateStr,
        'recordedTime': recordedTime,
        'status': '출근',
      };

      List<Map<String, dynamic>> logList = [];

      try {
        final credentialsJson = await rootBundle.loadString(_serviceAccountPath);
        final credentials = ServiceAccountCredentials.fromJson(credentialsJson);
        final client = await clientViaServiceAccount(
          credentials,
          [storage.StorageApi.devstorageReadOnlyScope],
        );
        final storageApi = storage.StorageApi(client);

        final media = await storageApi.objects.get(
          _bucketName,
          gcsPath,
          downloadOptions: storage.DownloadOptions.fullMedia,
        ) as storage.Media;

        final content = await utf8.decoder.bind(media.stream).join();
        final decoded = jsonDecode(content);

        if (decoded is List) {
          logList = List<Map<String, dynamic>>.from(decoded);
        } else if (decoded is Map) {
          logList = [Map<String, dynamic>.from(decoded)];
        }

        logger.log('✅ 기존 로그 불러오기 성공: ${logList.length}개', level: 'info');

        client.close();
      } catch (e) {
        logger.log('ℹ️ 기존 파일 없음 또는 파싱 실패: $e', level: 'warn');
        logList = [];
      }

      final alreadyExistsToday = logList.any((e) => e['recordedDate'] == dateStr);
      if (alreadyExistsToday) {
        logger.log('⚠️ 이미 오늘 출근 기록이 존재함: $dateStr', level: 'warn');
        return false;
      }

      logList.add(newRecord);
      logger.log('📝 출근 기록 추가됨: $newRecord', level: 'info');

      final jsonContent = jsonEncode(logList);
      final tempDir = Directory.systemTemp;
      final file = File('${tempDir.path}/clockin_$userId.json');
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

      await storageApi.objects.insert(
        object,
        _bucketName,
        uploadMedia: media,
        predefinedAcl: 'publicRead',
      );

      client.close();

      logger.log('✅ 출근 기록 업로드 완료: $gcsPath', level: 'success');
      return true;
    } catch (e) {
      logger.log('❌ 출근 기록 업로드 실패: $e', level: 'error');
      return false;
    }
  }

  static String getDownloadPath({
    required String division,
    required String area,
    required String userId,
    DateTime? dateTime,
  }) {
    final dt = dateTime ?? DateTime.now();
    final year = dt.year.toString().padLeft(4, '0');
    final month = dt.month.toString().padLeft(2, '0');

    final path = '$division/$area/exports/clock_in/$year/$month/$userId.json';
    return 'https://storage.googleapis.com/$_bucketName/$path';
  }
}
