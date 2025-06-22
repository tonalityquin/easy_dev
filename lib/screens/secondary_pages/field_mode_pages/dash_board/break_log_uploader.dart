import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:googleapis/storage/v1.dart';
import 'package:googleapis_auth/auth_io.dart';
import 'package:provider/provider.dart';
import 'package:flutter/material.dart';

import '../../../../states/area/area_state.dart';
import '../../../../states/user/user_state.dart';

class BreakLogUploader {
  static const _bucketName = 'easydev-image';
  static const _serviceAccountPath = 'assets/keys/easydev-97fb6-e31d7e6b30f9.json';

  static Future<bool> uploadBreakJson({
    required BuildContext context,
    required Map<String, dynamic> data,
  }) async {
    try {
      final areaState = context.read<AreaState>();
      final userState = context.read<UserState>();

      final area = userState.user?.selectedArea ?? '';
      final division = areaState.currentDivision;
      final userId = userState.user?.id ?? '';
      final userName = userState.name;

      final now = DateTime.now();
      final year = now.year.toString().padLeft(4, '0');
      final month = now.month.toString().padLeft(2, '0');
      final day = now.day.toString().padLeft(2, '0');
      final dateStr = '$year-$month-$day';

      final gcsPath = '$division/$area/exports/break/$year/$month/$userId.json';

      final newRecord = {
        'userId': userId,
        'userName': userName,
        'area': area,
        'division': division,
        'recordedDate': dateStr,
        'recordedTime': data['recordedTime'] ?? '',
        'status': '휴게',
      };

      List<Map<String, dynamic>> logList = [];

      try {
        final credentialsJson = await rootBundle.loadString(_serviceAccountPath);
        final credentials = ServiceAccountCredentials.fromJson(credentialsJson);
        final client = await clientViaServiceAccount(
          credentials,
          [StorageApi.devstorageReadOnlyScope],
        );
        final storageApi = StorageApi(client);

        final media = await storageApi.objects.get(
          _bucketName,
          gcsPath,
          downloadOptions: DownloadOptions.fullMedia,
        ) as Media;

        final content = await utf8.decoder.bind(media.stream).join();
        final decoded = jsonDecode(content);

        if (decoded is List) {
          logList = List<Map<String, dynamic>>.from(decoded);
        } else if (decoded is Map) {
          logList = [Map<String, dynamic>.from(decoded)];
        }

        client.close();
      } catch (e) {
        debugPrint('ℹ️ 기존 휴게 기록 없음 또는 파싱 실패: $e');
        logList = [];
      }

      final alreadyExistsToday = logList.any((e) => e['recordedDate'] == dateStr);
      if (alreadyExistsToday) {
        debugPrint('⚠️ 오늘자 휴게 기록 이미 존재함 → 업로드 생략');
        return false;
      }

      logList.add(newRecord);

      final jsonContent = jsonEncode(logList);
      final tempDir = Directory.systemTemp;
      final file = File('${tempDir.path}/break_${userId}_$year$month.json');
      await file.writeAsString(jsonContent);

      final credentialsJson = await rootBundle.loadString(_serviceAccountPath);
      final credentials = ServiceAccountCredentials.fromJson(credentialsJson);
      final client = await clientViaServiceAccount(
        credentials,
        [StorageApi.devstorageFullControlScope],
      );
      final storageApi = StorageApi(client);

      final media = Media(file.openRead(), file.lengthSync());
      final object = Object()..name = gcsPath;

      await storageApi.objects.insert(
        object,
        _bucketName,
        uploadMedia: media,
        predefinedAcl: 'publicRead',
      );

      client.close();
      debugPrint('✅ 휴게 기록 업로드 완료: $gcsPath');
      return true;
    } catch (e) {
      debugPrint('❌ 휴게 기록 업로드 실패: $e');
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

    final baseUrl =
        'https://storage.googleapis.com/$_bucketName/$division/$area/exports/break/$year/$month/$userId.json';

    final version = DateTime.now().millisecondsSinceEpoch; // 캐시 우회용 버전값

    return '$baseUrl?v=$version'; // 🔥 캐시 우회용 쿼리스트링 추가
  }
}
