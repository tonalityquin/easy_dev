import 'dart:io';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:googleapis_auth/auth_io.dart';
import 'package:googleapis/storage/v1.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
    String area, {
    int? basicStandard,
    int? basicAmount,
    int? addStandard,
    int? addAmount,
    String? adjustmentType,
  }) async {
    final now = DateTime.now();
    final year = now.year;
    final month = _two(now.month);
    final day = _two(now.day);
    final time = '${_two(now.hour)}${_two(now.minute)}${_two(now.second)}';

    final safePlate = plateNumber.replaceAll(RegExp(r'\\s'), '');
    final fileName = '$division/$area/$year/$month/$day/logs/${safePlate}_$time.json';

    // ✅ 정산 관련 필드 포함
    logData['basicStandard'] = basicStandard;
    logData['basicAmount'] = basicAmount;
    logData['addStandard'] = addStandard;
    logData['addAmount'] = addAmount;
    logData['adjustmentType'] = adjustmentType;

    return await uploadJsonData(logData, fileName);
  }

  Future<void> mergeAndReplaceLogs(String plateNumber, String division, String area) async {
    final now = DateTime.now();
    final year = now.year;
    final month = _two(now.month);
    final day = _two(now.day);
    final time = '${_two(now.hour)}${_two(now.minute)}${_two(now.second)}';

    final safePlate = plateNumber.replaceAll(RegExp(r'\\s'), ''); // ✅ 추가된 부분
    final prefix = '$division/$area/$year/$month/$day/logs/';

    final credentialsJson = await rootBundle.loadString(serviceAccountPath);
    final accountCredentials = ServiceAccountCredentials.fromJson(credentialsJson);
    final scopes = [StorageApi.devstorageFullControlScope];
    final client = await clientViaServiceAccount(accountCredentials, scopes);
    final storage = StorageApi(client);

    final allObjects = await storage.objects.list(bucketName, prefix: prefix);
    final matchingObjects = allObjects.items
            ?.where((o) =>
                o.name != null &&
                o.name!.contains(plateNumber) &&
                o.name!.endsWith('.json') &&
                !o.name!.contains('merged_'))
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
      'mergedAt': now.toIso8601String(),
      'logs': mergedLogs,
    };

    final mergedFileName = '$division/$area/$year/$month/$day/logs/merged_${safePlate}_$time.json';
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

    try {
      final firestore = FirebaseFirestore.instance;
      final snapshot = await firestore
          .collection('plates')
          .where('plate_number', isEqualTo: plateNumber)
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
    final now = DateTime.now();
    final year = now.year;
    final month = _two(now.month);
    final day = _two(now.day);
    final prefix = '$division/$area/$year/$month/$day/logs/';

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

  Future<Map<String, dynamic>> downloadMergedLogByPath(String fullFilePath) async {
    final credentialsJson = await rootBundle.loadString(serviceAccountPath);
    final accountCredentials = ServiceAccountCredentials.fromJson(credentialsJson);
    final scopes = [StorageApi.devstorageFullControlScope];
    final client = await clientViaServiceAccount(accountCredentials, scopes);
    final storage = StorageApi(client);

    try {
      final media = await storage.objects.get(
        bucketName,
        fullFilePath,
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

  Future<List<Map<String, dynamic>>> fetchMergedLogsForArea(
    String division,
    String area, {
    DateTime? filterDate,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final now = filterDate ?? DateTime.now();

    final year = now.year;
    final month = now.month;
    final day = now.day;
    final monthStr = month.toString().padLeft(2, '0');
    final dayStr = day.toString().padLeft(2, '0');
    final prefix = '$division/$area/$year/$monthStr/$dayStr/logs/merged_';

    final cacheKey = 'mergedLogCache-$division-$area-$year-$month-$day';
    final raw = prefs.getString(cacheKey);

    // ✅ 캐시가 존재하고 15일 이내면 반환
    if (raw != null) {
      try {
        final decoded = jsonDecode(raw);
        final createdAt = DateTime.tryParse(decoded['createdAt'] ?? '');

        if (createdAt != null && DateTime.now().difference(createdAt).inDays <= 15 && decoded['logs'] is List) {
          final cachedLogs = List<Map<String, dynamic>>.from(decoded['logs']);
          debugPrint('✅ 캐시된 병합 로그 사용됨: $cacheKey');
          return cachedLogs;
        } else {
          await prefs.remove(cacheKey);
          debugPrint('🗑️ 만료된 병합 로그 캐시 제거됨: $cacheKey');
        }
      } catch (e) {
        debugPrint('⚠️ 병합 로그 캐시 파싱 실패: $e');
      }
    }

    // 🔄 캐시가 없거나 만료되었으면 GCS에서 가져옴
    final credentialsJson = await rootBundle.loadString(serviceAccountPath);
    final accountCredentials = ServiceAccountCredentials.fromJson(credentialsJson);
    final client = await clientViaServiceAccount(accountCredentials, [StorageApi.devstorageFullControlScope]);
    final storage = StorageApi(client);

    final result = await storage.objects.list(bucketName, prefix: prefix);
    final logs = <Map<String, dynamic>>[];

    for (final obj in result.items ?? []) {
      if (obj.name != null && obj.name!.endsWith('.json')) {
        try {
          final media = await storage.objects.get(
            bucketName,
            obj.name!,
            downloadOptions: DownloadOptions.fullMedia,
          ) as Media;

          final bytes = await media.stream.expand((e) => e).toList();
          final content = utf8.decode(bytes);
          final decoded = jsonDecode(content);

          if (filterDate != null && decoded['mergedAt'] != null && DateTime.tryParse(decoded['mergedAt']) != null) {
            final mergedAt = DateTime.parse(decoded['mergedAt']);
            if (!(mergedAt.year == filterDate.year &&
                mergedAt.month == filterDate.month &&
                mergedAt.day == filterDate.day)) {
              continue;
            }
          }

          logs.add(decoded);
        } catch (e) {
          debugPrint('⚠️ 병합 로그 파일 처리 실패 (${obj.name}): $e');
        }
      }
    }

    client.close();

    // ✅ 캐시 저장
    await prefs.setString(
      cacheKey,
      jsonEncode({
        'logs': logs,
        'createdAt': DateTime.now().toIso8601String(),
      }),
    );

    debugPrint('📥 병합 로그 GCS에서 로드됨 + 캐시 저장됨: $cacheKey');
    return logs;
  }

  String _two(int value) => value.toString().padLeft(2, '0');
}
