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

      final area = areaState.currentArea;
      final division = areaState.currentDivision;
      final name = userState.name;

      final now = DateTime.now();
      final dateStr = '${now.year.toString().padLeft(4, '0')}-'
          '${now.month.toString().padLeft(2, '0')}-'
          '${now.day.toString().padLeft(2, '0')}';

      final fileName = '${dateStr}_${name}_휴게기록.json';
      final gcsPath = '$division/$area/exports/$fileName';

      final alreadyExists = await _checkIfFileExists(gcsPath);
      if (alreadyExists) {
        debugPrint('⚠️ 휴게 기록 이미 존재함: $gcsPath');
        return false;
      }

      final jsonContent = jsonEncode(data);
      final tempDir = Directory.systemTemp;
      final file = File('${tempDir.path}/$fileName');
      await file.writeAsString(jsonContent);

      final credentialsJson = await rootBundle.loadString(_serviceAccountPath);
      final credentials = ServiceAccountCredentials.fromJson(credentialsJson);
      final client = await clientViaServiceAccount(credentials, [StorageApi.devstorageFullControlScope]);
      final storage = StorageApi(client);

      final media = Media(file.openRead(), file.lengthSync());
      final object = Object()..name = gcsPath;

      await storage.objects.insert(object, _bucketName, uploadMedia: media);
      client.close();

      debugPrint('✅ 휴게 기록 업로드 성공: $gcsPath');
      return true;
    } catch (e) {
      debugPrint('❌ 휴게 기록 업로드 실패: $e');
      return false;
    }
  }

  static Future<bool> _checkIfFileExists(String gcsPath) async {
    try {
      final credentialsJson = await rootBundle.loadString(_serviceAccountPath);
      final credentials = ServiceAccountCredentials.fromJson(credentialsJson);
      final client = await clientViaServiceAccount(credentials, [StorageApi.devstorageReadOnlyScope]);
      final storage = StorageApi(client);

      await storage.objects.get(_bucketName, gcsPath);
      client.close();
      return true;
    } catch (_) {
      return false;
    }
  }
}
