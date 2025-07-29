import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:googleapis_auth/auth_io.dart';
import 'package:googleapis/storage/v1.dart';

class GcsJsonUploader {
  final String bucketName = 'easydev-image';
  final String projectId = 'easydev-97fb6';
  final String serviceAccountPath = 'assets/keys/easydev-97fb6-e31d7e6b30f9.json';

  String _two(int value) => value.toString().padLeft(2, '0');

  String _timeString(DateTime time) => '${_two(time.hour)}${_two(time.minute)}${_two(time.second)}';

  Future<void> appendAndUploadPlateLog({
    required Map<String, dynamic> newLog,
    required String plateNumber,
    required String division,
    required String area,
    String? billType,
  }) async {
    final now = DateTime.now();
    final safePlate = plateNumber.replaceAll(RegExp(r'\s'), '');
    final prefix = '$division/$area/${now.year}/${_two(now.month)}/${_two(now.day)}/logs';
    final fileName = '$prefix/${safePlate}_log.json';

    final credentialsJson = await rootBundle.loadString(serviceAccountPath);
    final accountCredentials = ServiceAccountCredentials.fromJson(credentialsJson);
    final client = await clientViaServiceAccount(accountCredentials, [StorageApi.devstorageFullControlScope]);

    try {
      final storage = StorageApi(client);
      List<dynamic> existingLogs = [];

      // 기존 로그 불러오기
      try {
        final obj = await storage.objects.get(
          bucketName,
          fileName,
          downloadOptions: DownloadOptions.fullMedia,
        ) as Media;
        final bytes = await obj.stream.expand((e) => e).toList();
        final content = utf8.decode(bytes);
        final decoded = jsonDecode(content);
        if (decoded is List) {
          existingLogs = decoded;
        }

        debugPrint('📌 DEBUG: 기존 로그 ${existingLogs.length}개 로드됨');
      } catch (e) {
        debugPrint('📄 기존 로그 없음. 새로 생성됩니다.');
      }

      // 로그 데이터 보정
      final enrichedLog = {
        ...newLog,
        'performedBy': newLog['performedBy'] ?? '시스템',
        'timestamp': newLog['timestamp'] ?? now.toIso8601String(),
        if (billType != null && billType.trim().isNotEmpty) 'billType': billType.trim(),
      };

      if (newLog['action'] == '사전 정산') {
        enrichedLog['from'] = newLog['from'] ?? '정산 시작';
        enrichedLog['to'] = newLog['to'] ?? '정산 완료';
      } else if (newLog['action'] == '사전 정산 취소') {
        enrichedLog['from'] = newLog['from'] ?? '정산 완료';
        enrichedLog['to'] = newLog['to'] ?? '정산 취소';
      }

      debugPrint('📌 DEBUG: 추가될 로그 내용 → ${jsonEncode(enrichedLog)}');

      existingLogs.add(enrichedLog);

      debugPrint('📌 DEBUG: 최종 로그 배열 길이 → ${existingLogs.length}');

      // 업로드
      final tempPath = '${Directory.systemTemp.path}/upload_${DateTime.now().millisecondsSinceEpoch}.json';
      final tempFile = File(tempPath);
      await tempFile.writeAsString(jsonEncode(existingLogs));
      final fileSize = await tempFile.length();

      debugPrint('📌 DEBUG: 업로드 파일 경로 → $tempPath');
      debugPrint('📌 DEBUG: 업로드 파일 크기 → ${fileSize}B');

      final media = Media(tempFile.openRead(), fileSize);

      await storage.objects.insert(
        Object()
          ..name = fileName
          ..acl = [
            ObjectAccessControl()
              ..entity = 'allUsers'
              ..role = 'READER'
          ],
        bucketName,
        uploadMedia: media,
      );

      debugPrint('✅ append 완료 및 업로드됨: $fileName');
    } catch (e, stack) {
      debugPrint('❌ 로그 업로드 실패: $e');
      debugPrint('$stack');
    } finally {
      client.close();
    }
  }

  Future<List<Map<String, dynamic>>> loadPlateLogs({
    required String plateNumber,
    required String division,
    required String area,
    required DateTime date,
  }) async {
    final safePlate = plateNumber.replaceAll(RegExp(r'\s'), '');
    final fileName = '$division/$area/${date.year}/${_two(date.month)}/${_two(date.day)}/logs/${safePlate}_log.json';

    final credentialsJson = await rootBundle.loadString(serviceAccountPath);
    final accountCredentials = ServiceAccountCredentials.fromJson(credentialsJson);
    final client = await clientViaServiceAccount(accountCredentials, [StorageApi.devstorageFullControlScope]);

    try {
      final storage = StorageApi(client);
      final obj = await storage.objects.get(bucketName, fileName, downloadOptions: DownloadOptions.fullMedia) as Media;
      final bytes = await obj.stream.expand((e) => e).toList();
      final content = utf8.decode(bytes);
      final decoded = jsonDecode(content);

      if (decoded is List) {
        return List<Map<String, dynamic>>.from(decoded);
      }
    } catch (e) {
      debugPrint('⚠️ 로그 로딩 실패: $e');
    } finally {
      client.close();
    }

    return [];
  }

  Future<void> uploadForJsonData(Map<String, dynamic> jsonData, String destinationPath) async {
    final credentialsJson = await rootBundle.loadString(serviceAccountPath);
    final accountCredentials = ServiceAccountCredentials.fromJson(credentialsJson);
    final client = await clientViaServiceAccount(accountCredentials, [StorageApi.devstorageFullControlScope]);

    try {
      final storage = StorageApi(client);
      final jsonString = jsonEncode(jsonData);
      final tempFile = File('${Directory.systemTemp.path}/upload_${DateTime.now().millisecondsSinceEpoch}.json');
      await tempFile.writeAsString(jsonString);
      final media = Media(tempFile.openRead(), await tempFile.length());

      await storage.objects.insert(
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

      debugPrint('✅ JSON 업로드 완료: $destinationPath');
    } catch (e, stack) {
      debugPrint('❌ JSON 업로드 실패: $e');
      debugPrint('$stack');
      rethrow;
    } finally {
      client.close();
    }
  }

  Future<void> generateSummaryLog({
    required String plateNumber,
    required String division,
    required String area,
    required DateTime date,
  }) async {
    final logs = await loadPlateLogs(
      plateNumber: plateNumber,
      division: division,
      area: area,
      date: date,
    );

    if (logs.isEmpty) {
      debugPrint("⚠️ 로그 없음: $plateNumber");
      return;
    }

    final timestamps = logs.map((log) => DateTime.tryParse(log['timestamp'] ?? '')).whereType<DateTime>().toList()
      ..sort();

    final latestBillingLog =
        logs.where((log) => log['action'] == '사전 정산').fold<Map<String, dynamic>?>(null, (prev, curr) {
      final currTime = DateTime.tryParse(curr['timestamp'] ?? '');
      final prevTime = prev != null ? DateTime.tryParse(prev['timestamp'] ?? '') : null;
      return (prevTime == null || (currTime != null && currTime.isAfter(prevTime))) ? curr : prev;
    });

    final now = DateTime.now();
    final safePlate = plateNumber.replaceAll(RegExp(r'\s'), '');
    final summaryFileName = '$division/$area/sources/${safePlate}_${_timeString(now)}.json';

    final summaryData = {
      'plateNumber': plateNumber,
      'inputTime': timestamps.isNotEmpty ? timestamps.first.toIso8601String() : null,
      'outputTime': timestamps.isNotEmpty ? timestamps.last.toIso8601String() : null,
      'lockedFee': latestBillingLog?['lockedFee'],
      'paymentMethod': latestBillingLog?['paymentMethod'],
      'billType': latestBillingLog?['billType'],
    };

    await uploadForJsonData(summaryData, summaryFileName);
    debugPrint('📦 서머리 업로드 완료: $summaryFileName');
  }
}
