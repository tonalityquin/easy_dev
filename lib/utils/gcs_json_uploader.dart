// lib/utils/gcs_json_uploader.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:googleapis/storage/v1.dart' as gcs;

import 'google_auth_session.dart';

class GcsJsonUploader {
  final String bucketName = 'easydev-image';

  Future<List<Map<String, dynamic>>> loadPlateLogs({
    required String plateNumber,
    required String division,
    required String area,
    required DateTime date,
  }) async {
    String yyyymmdd(DateTime d) =>
        '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    String digitsOnly(String s) => s.replaceAll(RegExp(r'\D'), '');
    DateTime? parseTs(dynamic ts) {
      if (ts == null) return null;
      if (ts is int) {
        if (ts > 100000000000) return DateTime.fromMillisecondsSinceEpoch(ts).toLocal();
        return DateTime.fromMillisecondsSinceEpoch(ts * 1000).toLocal();
      }
      if (ts is String) return DateTime.tryParse(ts)?.toLocal();
      return null;
    }

    final dateStr = yyyymmdd(DateTime(date.year, date.month, date.day));
    final wantedSuffix = '_ToDoLogs_$dateStr.json';
    final prefix = '$division/$area/logs/';

    final client = await GoogleAuthSession.instance.client();

    try {
      final storage = gcs.StorageApi(client);

      // 페이지네이션 대응
      final List<gcs.Object> all = [];
      String? pageToken;
      do {
        final res = await storage.objects.list(
          bucketName,
          prefix: prefix,
          pageToken: pageToken,
        );
        if (res.items != null) all.addAll(res.items!);
        pageToken = res.nextPageToken;
      } while (pageToken != null && pageToken.isNotEmpty);

      // 날짜 suffix 매칭 → 최신(updated) 선택
      final candidates = all.where((o) => (o.name ?? '').endsWith(wantedSuffix)).toList();
      if (candidates.isEmpty) {
        debugPrint('⚠️ 해당 날짜 파일 없음: $prefix*$wantedSuffix');
        return <Map<String, dynamic>>[];
      }
      candidates.sort((a, b) {
        final au = a.updated ?? DateTime.fromMillisecondsSinceEpoch(0);
        final bu = b.updated ?? DateTime.fromMillisecondsSinceEpoch(0);
        return au.compareTo(bu);
      });
      final objectName = candidates.last.name!;

      // 객체 다운로드 → JSON
      final dynamic res = await storage.objects.get(
        bucketName,
        objectName,
        downloadOptions: gcs.DownloadOptions.fullMedia,
      );
      if (res is! gcs.Media) {
        debugPrint('⚠️ 예상치 못한 반환 타입: ${res.runtimeType}');
        return <Map<String, dynamic>>[];
      }
      final gcs.Media media = res;
      final bytes = await media.stream.expand((e) => e).toList();
      final decoded = jsonDecode(utf8.decode(bytes));

      // items 또는 data 배열 지원
      final List rootItems = (decoded is Map && decoded['items'] is List)
          ? decoded['items'] as List
          : (decoded is Map && decoded['data'] is List)
          ? decoded['data'] as List
          : const [];

      final needle = digitsOnly(plateNumber);
      final needleTail4 = needle.length >= 4 ? needle.substring(needle.length - 4) : needle;

      final aggregated = <Map<String, dynamic>>[];

      for (final it in rootItems) {
        if (it is! Map) continue;
        final map = Map<String, dynamic>.from(it);
        final p = (map['plateNumber'] ?? map['docId'] ?? '').toString();
        final pd = digitsOnly(p);

        final matches = pd.isNotEmpty &&
            ((needle.length >= 4 && pd.endsWith(needleTail4)) ||
                (needle.isNotEmpty && pd == needle));
        if (!matches) continue;

        final logs = (map['logs'] as List?)
            ?.whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList() ??
            const <Map<String, dynamic>>[];

        aggregated.addAll(logs);
      }

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
      // 세션 클라이언트는 닫지 않습니다.
    }
  }
}
