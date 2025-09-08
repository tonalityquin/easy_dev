import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:googleapis_auth/auth_io.dart';
import 'package:googleapis/storage/v1.dart';


class GcsJsonUploader {
  final String bucketName = 'easydev-image';
  final String projectId = 'easydev-97fb6';
  final String serviceAccountPath = 'assets/keys/easydev-97fb6-e31d7e6b30f9.json';


  Future<List<Map<String, dynamic>>> loadPlateLogs({
    required String plateNumber,
    required String division,
    required String area,
    required DateTime date,
  }) async {
    // 헬퍼들 (메서드 내부에 국소 정의)
    String yyyymmdd(DateTime d) =>
        '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    String digitsOnly(String s) => s.replaceAll(RegExp(r'\D'), '');
    DateTime? parseTs(dynamic ts) {
      if (ts == null) return null;
      if (ts is int) {
        // 큰 값은 ms, 아니면 s 가정
        if (ts > 100000000000) return DateTime.fromMillisecondsSinceEpoch(ts).toLocal();
        return DateTime.fromMillisecondsSinceEpoch(ts * 1000).toLocal();
      }
      if (ts is String) return DateTime.tryParse(ts)?.toLocal();
      return null; // (GCS JSON에는 보통 String로 저장됨)
    }


    final dateStr = yyyymmdd(DateTime(date.year, date.month, date.day));
    final wantedSuffix = '_ToDoLogs_$dateStr.json';
    final prefix = '$division/$area/logs/';


    final credentialsJson = await rootBundle.loadString(serviceAccountPath);
    final accountCredentials = ServiceAccountCredentials.fromJson(credentialsJson);
    final client = await clientViaServiceAccount(
      accountCredentials,
      [StorageApi.devstorageFullControlScope],
    );


    try {
      final storage = StorageApi(client);


      // 1) 해당 경로(prefix)의 파일 목록을 가져와서, 그날짜 파일 한 개를 찾음
      final listRes = await storage.objects.list(bucketName, prefix: prefix);
      final items = listRes.items ?? const <Object>[];
      final target = items.firstWhere(
            (o) => (o.name ?? '').endsWith(wantedSuffix),
        orElse: () => Object(), // name == null 인 더미
      );
      final objectName = target.name;
      if (objectName == null) {
        debugPrint('⚠️ 해당 날짜 파일 없음: $prefix*$wantedSuffix');
        return <Map<String, dynamic>>[];
      }


      // 2) 파일 다운로드 & JSON 파싱
      final media = await storage.objects.get(
        bucketName,
        objectName,
        downloadOptions: DownloadOptions.fullMedia,
      ) as Media;
      final bytes = await media.stream.expand((e) => e).toList();
      final content = utf8.decode(bytes);
      final decoded = jsonDecode(content);


      // 3) 스키마: items 또는 data 배열 지원
      final List rootItems = (decoded is Map && decoded['items'] is List)
          ? decoded['items'] as List
          : (decoded is Map && decoded['data'] is List)
          ? decoded['data'] as List
          : const [];


      // 4) plateNumber(또는 4자리)로 필터 후 logs 모으기
      final needle = digitsOnly(plateNumber); // 전체를 넣어도 되고, 4자리만 넣어도 됨
      final needleTail4 = needle.length >= 4 ? needle.substring(needle.length - 4) : needle;


      final aggregated = <Map<String, dynamic>>[];


      for (final it in rootItems) {
        if (it is! Map) continue;
        final map = Map<String, dynamic>.from(it);
        final p = (map['plateNumber'] ?? map['docId'] ?? '').toString();
        final pd = digitsOnly(p);


        final matches = pd.isNotEmpty &&
            ((needle.length >= 4 && pd.endsWith(needleTail4)) // 4자리 일치 검색
                ||
                (needle.isNotEmpty && pd == needle)); // 전체 일치도 허용


        if (!matches) continue;


        final logs = (map['logs'] as List?)?.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList() ??
            const <Map<String, dynamic>>[];


        aggregated.addAll(logs);
      }


      // 5) 시간 오름차순 정렬
      aggregated.sort((a, b) {
        final at = parseTs(a['timestamp']) ?? DateTime.fromMillisecondsSinceEpoch(0);
        final bt = parseTs(b['timestamp']) ?? DateTime.fromMillisecondsSinceEpoch(0);
        return at.compareTo(bt);
      });


      return aggregated;
    } catch (e) {
      debugPrint('⚠️ loadPlateLogs 실패: $e');
      return <Map<String, dynamic>>[];
    } finally {
      client.close();
    }
  }
}
