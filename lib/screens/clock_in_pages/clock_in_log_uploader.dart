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
    required String recordedTime,
  }) async {
    try {
      final areaState = context.read<AreaState>();
      final userState = context.read<UserState>();

      final area = areaState.currentArea;
      final division = areaState.currentDivision;
      final userName = userState.name;
      final userId = userState.user?.id ?? '';

      final now = DateTime.now();
      final year = now.year.toString().padLeft(4, '0');
      final month = now.month.toString().padLeft(2, '0');
      final day = now.day.toString().padLeft(2, '0');
      final dateStr = '$year-$month-$day';

      final gcsPath = '$division/$area/exports/clock_in/$year/$month/$userId.json';

      // 새 출근 기록
      final newRecord = {
        'userId': userId,
        'userName': userName,
        'area': area,
        'division': division,
        'recordedDate': dateStr,
        'recordedTime': recordedTime,
        'status': '출근',
      };

      // 기존 기록 불러오기
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

        client.close();
      } catch (e) {
        debugPrint('ℹ️ 기존 파일 없거나 JSON 파싱 실패: $e');
        logList = [];
      }

      // 기존 날짜 기록 제거 후 새 기록 append
      logList.removeWhere((e) => e['recordedDate'] == dateStr);
      logList.add(newRecord);

      // 저장용 파일 생성
      final jsonContent = jsonEncode(logList);
      final tempDir = Directory.systemTemp;
      final file = File('${tempDir.path}/clockin_$userId.json');
      await file.writeAsString(jsonContent);

      // GCS에 업로드
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
      debugPrint('✅ 출근 기록 append & 업로드 성공: $gcsPath');
      return true;
    } catch (e) {
      debugPrint('❌ 출근 기록 업로드 실패: $e');
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
    return 'https://storage.googleapis.com/$_bucketName/$division/$area/exports/clock_in/$year/$month/$userId.json';
  }
}
