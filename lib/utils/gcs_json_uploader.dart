import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:googleapis_auth/auth_io.dart';
import 'package:googleapis/storage/v1.dart';
import 'package:shared_preferences/shared_preferences.dart';

class GcsJsonUploader {
  final String bucketName = 'easydev-image';
  final String projectId = 'easydev-97fb6';
  final String serviceAccountPath = 'assets/keys/easydev-97fb6-e31d7e6b30f9.json';

  Future<String?> uploadForJsonData(Map<String, dynamic> jsonData, String destinationPath) async {
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

  Future<String?> uploadForPlateLogTypeJson(
    Map<String, dynamic> logData,
    String plateNumber,
    String division,
    String area, {
    String? billType,
  }) async {
    final now = DateTime.now();
    final year = now.year;
    final month = _two(now.month);
    final day = _two(now.day);
    final time = '${_two(now.hour)}${_two(now.minute)}${_two(now.second)}';

    final safePlate = plateNumber.replaceAll(RegExp(r'\\s'), '');
    final fileName = '$division/$area/$year/$month/$day/logs/${safePlate}_$time.json';

    final cleanBillType = billType?.trim();
    if (cleanBillType != null && cleanBillType.isNotEmpty) {
      logData['billType'] = cleanBillType;
    }

    if (logData['action'] == '사전 정산') {
      logData.putIfAbsent('from', () => '정산 시작');
      logData.putIfAbsent('to', () => '정산 완료');
    } else if (logData['action'] == '사전 정산 취소') {
      logData.putIfAbsent('from', () => '정산 완료');
      logData.putIfAbsent('to', () => '정산 취소');
    }

    logData.putIfAbsent('performedBy', () => '시스템');

    return await uploadForJsonData(logData, fileName);
  }

  Future<void> mergeAndSummarizeLogs(String plateNumber, String division, String area) async {
    await Future.delayed(Duration(seconds: 3));

    final now = DateTime.now();
    final year = now.year;
    final month = _two(now.month);
    final day = _two(now.day);
    final time = '${_two(now.hour)}${_two(now.minute)}${_two(now.second)}';

    final safePlate = plateNumber.replaceAll(RegExp(r'\\s'), '');
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
    await uploadForJsonData(mergedJson, mergedFileName);

    for (final obj in matchingObjects) {
      try {
        if (obj.name != null) {
          await storage.objects.delete(bucketName, obj.name!);
          debugPrint("🗑️ 삭제 완료: ${obj.name}");
        }
      } catch (e) {
        debugPrint("❌ 삭제 실패: ${obj.name}, $e");
      }
    }

    final timestamps = mergedLogs
        .whereType<Map<String, dynamic>>()
        .map((e) => DateTime.tryParse(e['timestamp'] ?? ''))
        .whereType<DateTime>()
        .toList()
      ..sort();

    final inputTime = timestamps.isNotEmpty ? timestamps.first.toIso8601String() : null;
    final outputTime = timestamps.isNotEmpty ? timestamps.last.toIso8601String() : null;

    final latestBillingLog = mergedLogs
        .whereType<Map<String, dynamic>>()
        .where((log) => log['action'] == '사전 정산')
        .fold<Map<String, dynamic>?>(null, (prev, curr) {
      final currTime = DateTime.tryParse(curr['timestamp'] ?? '');
      final prevTime = prev != null ? DateTime.tryParse(prev['timestamp'] ?? '') : null;
      if (prevTime == null || (currTime != null && currTime.isAfter(prevTime))) {
        return curr;
      }
      return prev;
    });

    final summaryJson = {
      'plateNumber': plateNumber,
      'inputTime': inputTime,
      'outputTime': outputTime,
      'lockedFee': latestBillingLog?['lockedFee'],
      'paymentMethod': latestBillingLog?['paymentMethod'],
      'billType': latestBillingLog?['billType'],
    };

    final summaryFileName = '$division/$area/sources/${safePlate}_$time.json';
    await uploadForJsonData(summaryJson, summaryFileName);

    client.close();
  }

  Future<List<Map<String, dynamic>>> showMergedLogsToDepartureCompletedMergeLog(
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
