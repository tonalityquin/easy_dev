import 'dart:io';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:googleapis_auth/auth_io.dart';
import 'package:googleapis/storage/v1.dart';

class GCSUploader {
  final String bucketName = 'easydev-image';
  final String projectId = 'easydev-97fb6';
  final String serviceAccountPath = 'assets/keys/easydev-97fb6-e31d7e6b30f9.json';

  Future<String?> uploadImageFromInput(File imageFile, String destinationPath) async {
    return await _upload(imageFile, destinationPath);
  }

  Future<String?> uploadImageFromModify(File imageFile, String destinationPath) async {
    return await _upload(imageFile, destinationPath);
  }

  Future<String?> _upload(File file, String destinationPath) async {
    try {
      final credentialsJson = await rootBundle.loadString(serviceAccountPath);
      final accountCredentials = ServiceAccountCredentials.fromJson(credentialsJson);
      final scopes = [StorageApi.devstorageFullControlScope];
      final client = await clientViaServiceAccount(accountCredentials, scopes);
      final storage = StorageApi(client);

      final media = Media(file.openRead(), file.lengthSync());

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

      client.close();
      return 'https://storage.googleapis.com/$bucketName/${object.name}';
    } catch (e, stack) {
      debugPrint('🔥 GCS 업로드 실패: $e');
      debugPrint('🔥 Stack Trace: $stack');
      rethrow;
    }
  }

  Future<String?> uploadJsonData(Map<String, dynamic> jsonData, String destinationPath) async {
    try {
      final credentialsJson = await rootBundle.loadString(serviceAccountPath);
      final accountCredentials = ServiceAccountCredentials.fromJson(credentialsJson);
      final scopes = [StorageApi.devstorageFullControlScope];
      final client = await clientViaServiceAccount(accountCredentials, scopes);
      final storage = StorageApi(client);

      final jsonString = jsonEncode(jsonData);
      final tempFile = File('${Directory.systemTemp.path}/temp_upload.json');
      await tempFile.writeAsString(jsonString);

      final media = Media(tempFile.openRead(), tempFile.lengthSync());

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

      client.close();
      return 'https://storage.googleapis.com/$bucketName/${object.name}';
    } catch (e, stack) {
      debugPrint('🔥 JSON 업로드 실패: $e');
      debugPrint('🔥 Stack Trace: $stack');
      rethrow;
    }
  }

  Future<String?> uploadLogJson(
    Map<String, dynamic> logData,
    String plateNumber,
    String division,
    String area,
  ) async {
    final now = DateTime.now();
    final timestamp =
        '${now.year}${_two(now.month)}${_two(now.day)}_${_two(now.hour)}${_two(now.minute)}${_two(now.second)}';
    final safePlate = plateNumber.replaceAll(RegExp(r'\\s'), '');

    final fileName = '$division/$area/logs/${timestamp}_$safePlate.json';

    return await uploadJsonData(logData, fileName);
  }

  Future<void> mergeAndReplaceLogs(String plateNumber, String division, String area) async {
    final prefix = '$division/$area/logs/';
    final credentialsJson = await rootBundle.loadString(serviceAccountPath);
    final accountCredentials = ServiceAccountCredentials.fromJson(credentialsJson);
    final scopes = [StorageApi.devstorageFullControlScope];
    final client = await clientViaServiceAccount(accountCredentials, scopes);
    final storage = StorageApi(client);

    final allObjects = await storage.objects.list(bucketName, prefix: prefix);
    final matchingObjects = allObjects.items
            ?.where((o) => o.name != null && o.name!.contains(plateNumber) && o.name!.endsWith('.json'))
            .toList() ??
        [];

    List<Map<String, dynamic>> mergedLogs = [];

    for (final obj in matchingObjects) {
      try {
        if (obj.name != null) {
          final media = await storage.objects.get(
            bucketName,
            obj.name!,
            downloadOptions: DownloadOptions.fullMedia,
          ) as Media;

          final bytes = await media.stream.expand((e) => e).toList();
          final content = utf8.decode(bytes);
          final parsed = jsonDecode(content);
          mergedLogs.add(parsed);
        }
      } catch (e) {
        debugPrint('⚠️ 로그 파일 파싱 실패: ${obj.name}, $e');
      }
    }

    final mergedJson = {
      'plateNumber': plateNumber,
      'mergedAt': DateTime.now().toIso8601String(),
      'logs': mergedLogs,
    };

    final mergedFileName = '$division/$area/logs/merged_$plateNumber.json';
    await uploadJsonData(mergedJson, mergedFileName);

    for (final obj in matchingObjects) {
      try {
        if (obj.name != null) {
          await storage.objects.delete(bucketName, obj.name!);
        }
        debugPrint("🗑️ 삭제 완료: ${obj.name}");
      } catch (e) {
        debugPrint("❌ 삭제 실패: ${obj.name}, $e");
      }
    }

    // ✅ Firestore 문서 삭제 추가
    try {
      final firestore = FirebaseFirestore.instance;
      final snapshot = await firestore
          .collection('plates')
          .where('plate_number', isEqualTo: plateNumber) // 수정됨
          .where('type', isEqualTo: 'departure_completed')
          .where('area', isEqualTo: area)
          .where('isLockedFee', isEqualTo: true)
          .get();

      for (final doc in snapshot.docs) {
        await doc.reference.delete();
        debugPrint("🔥 Firestore 삭제 완료: ${doc.id}");
      }
    } catch (e) {
      debugPrint("❌ Firestore 삭제 실패: $e");
    }

    client.close();
  }

  Future<List<String>> listMergedPlateLogs(String division, String area) async {
    final prefix = '$division/$area/logs/';
    final credentialsJson = await rootBundle.loadString(serviceAccountPath);
    final accountCredentials = ServiceAccountCredentials.fromJson(credentialsJson);
    final scopes = [StorageApi.devstorageFullControlScope];
    final client = await clientViaServiceAccount(accountCredentials, scopes);
    final storage = StorageApi(client);

    final allObjects = await storage.objects.list(bucketName, prefix: prefix);
    final mergedFiles = allObjects.items
            ?.where((o) => o.name != null && o.name!.contains('merged_') && o.name!.endsWith('.json'))
            .map((o) => o.name!)
            .toList() ??
        [];

    client.close();
    return mergedFiles;
  }

  Future<Map<String, dynamic>> downloadMergedLog(String plateNumber, String division, String area) async {
    final fileName = '$division/$area/logs/merged_$plateNumber.json';

    final credentialsJson = await rootBundle.loadString(serviceAccountPath);
    final accountCredentials = ServiceAccountCredentials.fromJson(credentialsJson);
    final scopes = [StorageApi.devstorageFullControlScope];
    final client = await clientViaServiceAccount(accountCredentials, scopes);
    final storage = StorageApi(client);

    try {
      final media = await storage.objects.get(
        bucketName,
        fileName,
        downloadOptions: DownloadOptions.fullMedia,
      ) as Media;

      final bytes = await media.stream.expand((e) => e).toList();
      final content = utf8.decode(bytes);
      final parsed = jsonDecode(content);

      return parsed;
    } catch (e) {
      debugPrint('❌ 병합 로그 다운로드 실패: $e');
      rethrow;
    } finally {
      client.close();
    }
  }

  Future<List<Map<String, dynamic>>> fetchMergedLogsForArea(String division, String area) async {
    final prefix = '$division/$area/logs/merged_';
    final credentialsJson = await rootBundle.loadString(serviceAccountPath);
    final accountCredentials = ServiceAccountCredentials.fromJson(credentialsJson);
    final client = await clientViaServiceAccount(accountCredentials, [StorageApi.devstorageFullControlScope]);
    final storage = StorageApi(client);

    final result = await storage.objects.list(bucketName, prefix: prefix);
    final logs = <Map<String, dynamic>>[];

    for (final obj in result.items ?? []) {
      if (obj.name != null && obj.name!.endsWith('.json')) {
        final media =
            await storage.objects.get(bucketName, obj.name!, downloadOptions: DownloadOptions.fullMedia) as Media;
        final bytes = await media.stream.expand((e) => e).toList();
        final content = utf8.decode(bytes);
        final decoded = jsonDecode(content);
        logs.add(decoded);
      }
    }

    client.close();
    return logs;
  }

  String _two(int value) => value.toString().padLeft(2, '0');
}
