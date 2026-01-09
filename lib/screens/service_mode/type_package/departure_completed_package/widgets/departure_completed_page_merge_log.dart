import 'dart:convert';
import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:googleapis/storage/v1.dart' as gcs;
import 'package:http/http.dart' as http;

// 사진 다이얼로그(프로젝트 구조에 맞게 조정)
import 'departure_completed_plate_image_dialog.dart';

// ✅ OAuth 헬퍼 (패키지 import로 고정; 필요 시 상대경로로 교체 가능)
import 'package:easydev/utils/google_auth_v7.dart';

// ✅ API 디버그(통합 에러 로그) 로거
import 'package:easydev/screens/hubs_mode/dev_package/debug_package/debug_api_logger.dart';

/// === GCS 설정 ===
const String kBucketName = 'easydev-image';

/// === 내부 레이아웃 상수 ===
const double _kRowHeight = 56.0;
const double _kTimeColWidth = 84.0; // HH:mm:ss 고정폭
const double _kFeeColWidth = 108.0; // 요금/결제 표시
const double _kChevronWidth = 28.0; // 펼침 아이콘

// ─────────────────────────────────────────────────────────────
// ✅ API 디버그 로직: 표준 태그 / 로깅 헬퍼 (file-scope)
// ─────────────────────────────────────────────────────────────
const String _tLogs = 'logs';
const String _tLogsUi = 'logs/ui';
const String _tLogsLoad = 'logs/load';
const String _tLogsParse = 'logs/parse';
const String _tLogsSearch = 'logs/search';

const String _tGcs = 'gcs';
const String _tGcsList = 'gcs/list';
const String _tGcsGet = 'gcs/get';
const String _tAuth = 'google/auth';

Future<void> _logApiError({
  required String tag,
  required String message,
  required Object error,
  Map<String, dynamic>? extra,
  List<String>? tags,
}) async {
  try {
    await DebugApiLogger().log(
      <String, dynamic>{
        'tag': tag,
        'message': message,
        'error': error.toString(),
        if (extra != null) 'extra': extra,
      },
      level: 'error',
      tags: tags,
    );
  } catch (_) {
    // 로깅 실패는 기능에 영향 없도록 무시
  }
}

/// === GCS 헬퍼 (OAuth 사용) ===
class _GcsHelper {
  /// prefix 하위 object 목록 (페이지네이션 대응)
  Future<List<String>> listObjects(String prefix) async {
    late final http.Client client;
    try {
      client = await GoogleAuthV7.authedClient(
        [gcs.StorageApi.devstorageReadOnlyScope],
      );
    } catch (e) {
      await _logApiError(
        tag: '_GcsHelper.listObjects',
        message: 'GoogleAuthV7.authedClient 실패',
        error: e,
        extra: <String, dynamic>{'prefix': prefix},
        tags: const <String>[_tLogs, _tGcs, _tGcsList, _tAuth],
      );
      rethrow;
    }

    try {
      final storage = gcs.StorageApi(client);
      final acc = <String>[];
      String? pageToken;

      do {
        try {
          final res = await storage.objects.list(
            kBucketName,
            prefix: prefix,
            pageToken: pageToken,
          );
          final items = res.items ?? const <gcs.Object>[];
          for (final o in items) {
            final name = o.name;
            if (name != null && name.isNotEmpty) acc.add(name);
          }
          pageToken = res.nextPageToken;
        } catch (e) {
          await _logApiError(
            tag: '_GcsHelper.listObjects',
            message: 'GCS objects.list 실패',
            error: e,
            extra: <String, dynamic>{
              'bucket': kBucketName,
              'prefix': prefix,
              'pageToken': pageToken ?? '',
              'accCount': acc.length,
            },
            tags: const <String>[_tLogs, _tGcs, _tGcsList],
          );
          rethrow;
        }
      } while (pageToken != null && pageToken.isNotEmpty);

      return acc;
    } finally {
      client.close();
    }
  }

  /// public URL로 JSON 로드(버킷이 공개라면 그대로 사용).
  /// 비공개 버킷이면 아래 주석의 objects.get(fullMedia) 방식으로 교체하세요.
  /// (웹 호환을 위해 package:http 사용)
  Future<Map<String, dynamic>> loadJsonByObjectName(String objectName) async {
    final url = Uri.parse('https://storage.googleapis.com/$kBucketName/$objectName');

    http.Response resp;
    try {
      resp = await http.get(url);
    } catch (e) {
      await _logApiError(
        tag: '_GcsHelper.loadJsonByObjectName',
        message: 'HTTP GET 실패',
        error: e,
        extra: <String, dynamic>{
          'url': url.toString(),
          'objectName': objectName,
        },
        tags: const <String>[_tLogs, _tGcs, _tGcsGet],
      );
      rethrow;
    }

    if (resp.statusCode != 200) {
      await _logApiError(
        tag: '_GcsHelper.loadJsonByObjectName',
        message: 'GCS GET 실패(status != 200)',
        error: Exception('status=${resp.statusCode}'),
        extra: <String, dynamic>{
          'url': url.toString(),
          'objectName': objectName,
          'statusCode': resp.statusCode,
          'bodyPreview': resp.bodyBytes.isNotEmpty
              ? utf8.decode(resp.bodyBytes.take(120).toList(), allowMalformed: true)
              : '',
        },
        tags: const <String>[_tLogs, _tGcs, _tGcsGet],
      );
      throw Exception('GCS GET failed with ${resp.statusCode}');
    }

    try {
      final decoded = jsonDecode(utf8.decode(resp.bodyBytes));
      if (decoded is Map<String, dynamic>) return decoded;

      await _logApiError(
        tag: '_GcsHelper.loadJsonByObjectName',
        message: 'JSON이 Map 형태가 아님',
        error: Exception('decoded_type=${decoded.runtimeType}'),
        extra: <String, dynamic>{'objectName': objectName},
        tags: const <String>[_tLogs, _tGcs, _tGcsGet, _tLogsParse],
      );
      return <String, dynamic>{};
    } catch (e) {
      await _logApiError(
        tag: '_GcsHelper.loadJsonByObjectName',
        message: 'JSON 디코딩 실패',
        error: e,
        extra: <String, dynamic>{'objectName': objectName},
        tags: const <String>[_tLogs, _tGcs, _tGcsGet, _tLogsParse],
      );
      rethrow;
    }

    /*
    // 🔒 비공개 버킷일 때는 아래처럼 OAuth 클라이언트로 직접 다운(캐스팅 주의)
    final client = await GoogleAuthV7.authedClient(
      [gcs.StorageApi.devstorageReadOnlyScope],
    );
    try {
      final storage = gcs.StorageApi(client);
      final dynamic res = await storage.objects.get(
        kBucketName,
        objectName,
        downloadOptions: gcs.DownloadOptions.fullMedia,
      );
      if (res is! gcs.Media) {
        throw StateError('Unexpected response type: ${res.runtimeType}');
      }
      final bytes = await res.stream.expand((e) => e).toList();
      final decoded = jsonDecode(utf8.decode(bytes));
      return (decoded is Map<String, dynamic>) ? decoded : <String, dynamic>{};
    } finally {
      client.close();
    }
    */
  }
}

/// === 상단 컨트롤: 날짜 범위 버튼 + 불러오기 ===
class RangeControls extends StatelessWidget {
  const RangeControls({
    super.key,
    required this.start,
    required this.end,
    required this.loading,
    required this.onRangePicked,
    required this.onLoad,
  });

  final DateTime start;
  final DateTime end;
  final bool loading;
  final ValueChanged<DateTimeRange> onRangePicked;
  final VoidCallback onLoad;

  String _two(int n) => n.toString().padLeft(2, '0');
  String _ymd(DateTime d) => '${d.year}-${_two(d.month)}-${_two(d.day)}';

  Future<void> _pickRange(BuildContext context) async {
    final initial = DateTimeRange(start: start, end: end);
    final picked = await showDateRangePicker(
      context: context,
      initialDateRange: initial,
      firstDate: DateTime(2023, 1, 1),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      helpText: '날짜 범위 선택',
    );
    if (picked != null) onRangePicked(picked);
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: Row(
        children: [
          Expanded(
            flex: 5,
            child: OutlinedButton.icon(
              onPressed: () => _pickRange(context),
              icon: const Icon(Icons.calendar_month, size: 18),
              label: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text('${_ymd(start)}  ~  ${_ymd(end)}', maxLines: 1),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 3,
            child: FilledButton.icon(
              onPressed: loading ? null : onLoad,
              icon: loading
                  ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
              )
                  : const Icon(Icons.download),
              label: const FittedBox(child: Text('불러오기', maxLines: 1)),
            ),
          ),
        ],
      ),
    );
  }
}

/// === 위젯 ===
class MergedLogSection extends StatefulWidget {
  final List<Map<String, dynamic>> mergedLogs; // 시그니처 호환용(내부 미사용)
  final String division;
  final String area;

  const MergedLogSection({
    super.key,
    this.mergedLogs = const <Map<String, dynamic>>[],
    required this.division,
    required this.area,
  });

  @override
  State<MergedLogSection> createState() => _MergedLogSectionState();
}

class _MergedLogSectionState extends State<MergedLogSection> {
  // 날짜 범위(기본: 최근 7일)
  DateTime _start = DateTime.now().subtract(const Duration(days: 6));
  DateTime _end = DateTime.now();

  // 상태
  bool _loading = false;
  String? _error;

  final List<_DayBundle> _days = [];
  final Set<String> _expandedDocIds = {};

  // 검색
  final _tailCtrl = TextEditingController();
  List<_SearchHit> _hits = [];
  _SearchHit? _selectedHit;

  // 내부 페이지(0: 목록, 1: 검색)
  final PageController _pageController = PageController(initialPage: 0);
  int _currentPage = 0;

  @override
  void dispose() {
    _tailCtrl.dispose();
    _pageController.dispose();
    super.dispose();
  }

  // ===== 유틸 =====
  String _two(int n) => n.toString().padLeft(2, '0');
  String _yyyymmdd(DateTime d) => '${d.year}-${_two(d.month)}-${_two(d.day)}';
  String _yyyymm(DateTime d) => '${d.year}${_two(d.month)}';

  bool _validTail(String s) => RegExp(r'^\d{4}$').hasMatch(s);
  String _digitsOnly(String s) => s.replaceAll(RegExp(r'\D'), '');

  String? _toStr(dynamic v) {
    if (v == null) return null;
    final s = v.toString().trim();
    return s.isEmpty ? null : s;
    // ignore: dead_code
  }

  num? _toNum(dynamic v) {
    if (v == null) return null;
    if (v is num) return v;
    if (v is String) return num.tryParse(v.trim());
    return null;
  }

  DateTime? _parseTs(dynamic ts) {
    if (ts == null) return null;
    if (ts is DateTime) return ts.toLocal();
    if (ts is Timestamp) return ts.toDate().toLocal();
    if (ts is int) {
      if (ts > 100000000000) return DateTime.fromMillisecondsSinceEpoch(ts).toLocal();
      return DateTime.fromMillisecondsSinceEpoch(ts * 1000).toLocal();
    }
    if (ts is String) return DateTime.tryParse(ts)?.toLocal();
    return null;
  }

  String _fmtDateTime(DateTime? dt) {
    if (dt == null) return '--';
    return '${dt.year}-${_two(dt.month)}-${_two(dt.day)} ${_two(dt.hour)}:${_two(dt.minute)}:${_two(dt.second)}';
  }

  String _fmtTime(DateTime? dt) {
    if (dt == null) return '--';
    return '${_two(dt.hour)}:${_two(dt.minute)}:${_two(dt.second)}';
  }

  String _fmtWon(num? n) {
    if (n == null) return '—';
    final s = n.round().toString();
    final buf = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i != 0 && (s.length - i) % 3 == 0) buf.write(',');
      buf.write(s[i]);
    }
    return '₩$buf';
  }

  IconData _actionIcon(String action) {
    if (action.contains('사전 정산')) return Icons.receipt_long;
    if (action.contains('입차 완료')) return Icons.local_parking;
    if (action.contains('출차')) return Icons.exit_to_app;
    if (action.contains('취소')) return Icons.undo;
    if (action.contains('생성')) return Icons.add_circle_outline;
    return Icons.history;
  }

  Color _actionColor(String action) {
    if (action.contains('사전 정산')) return Colors.teal;
    if (action.contains('출차')) return Colors.orange;
    if (action.contains('취소')) return Colors.redAccent;
    if (action.contains('생성')) return Colors.indigo;
    return Colors.blueGrey;
  }

  // ===== 파싱/호환 리팩터링 =====

  Map<String, dynamic>? _asMap(dynamic v) {
    if (v is Map<String, dynamic>) return v;
    if (v is Map) return Map<String, dynamic>.from(v);
    return null;
  }

  Map<String, dynamic> _extractMeta(Map<String, dynamic> item) {
    final meta = <String, dynamic>{};

    item.forEach((k, v) {
      if (k == 'docId' || k == 'data' || k == 'logs') return;
      meta[k] = v;
    });

    final dataMap = _asMap(item['data']);
    if (dataMap != null) {
      dataMap.forEach((k, v) {
        if (k == 'logs') return;
        meta[k] = v;
      });
    }
    return meta;
  }

  String _extractPlate(Map<String, dynamic> item, Map<String, dynamic> meta, String docId) {
    final v = item['plateNumber'] ??
        meta['plateNumber'] ??
        meta['plate_number'] ??
        (docId.contains('_') ? docId.split('_').first : docId);
    return (v ?? '').toString();
  }

  List<Map<String, dynamic>> _extractLogs(Map<String, dynamic> item) {
    final dataMap = _asMap(item['data']);
    final raw = item['logs'] ?? dataMap?['logs'];

    if (raw is! List) return <Map<String, dynamic>>[];

    final logs = raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();

    logs.sort((a, b) {
      final at = _parseTs(a['timestamp']) ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bt = _parseTs(b['timestamp']) ?? DateTime.fromMillisecondsSinceEpoch(0);
      return at.compareTo(bt);
    });

    return logs;
  }

  num? _pickNumFromLogs(List<Map<String, dynamic>> logs, List<String> keys) {
    for (int i = logs.length - 1; i >= 0; i--) {
      final e = logs[i];
      for (final k in keys) {
        final n = _toNum(e[k]);
        if (n != null) return n;
      }
    }
    return null;
  }

  String? _pickStrFromLogs(List<Map<String, dynamic>> logs, List<String> keys) {
    for (int i = logs.length - 1; i >= 0; i--) {
      final e = logs[i];
      for (final k in keys) {
        final s = _toStr(e[k]);
        if (s != null) return s;
      }
    }
    return null;
  }

  String _tail4OfPlate(String plateNumber, String docId, {String? plateFourDigit}) {
    if (plateFourDigit != null && plateFourDigit.trim().length == 4) {
      return plateFourDigit.trim();
    }
    final d = _digitsOnly(plateNumber.isNotEmpty ? plateNumber : docId);
    if (d.length >= 4) return d.substring(d.length - 4);
    return '';
  }

  String _logSig(Map<String, dynamic> e) {
    final ts = (e['timestamp'] ?? '').toString();
    final action = (e['action'] ?? '').toString();
    final by = (e['performedBy'] ?? '').toString();
    final from = (e['from'] ?? '').toString();
    final to = (e['to'] ?? '').toString();
    final fee = (e['lockedFee'] ?? e['lockedFeeAmount'] ?? '').toString();
    final pay = (e['paymentMethod'] ?? '').toString();
    return '$ts|$action|$by|$from|$to|$fee|$pay';
  }

  List<Map<String, dynamic>> _mergeLogs(List<Map<String, dynamic>> a, List<Map<String, dynamic>> b) {
    final combined = <Map<String, dynamic>>[];
    combined.addAll(a);
    combined.addAll(b);

    final seen = <String>{};
    final unique = <Map<String, dynamic>>[];
    for (final e in combined) {
      final sig = _logSig(e);
      if (seen.add(sig)) unique.add(e);
    }

    unique.sort((x, y) {
      final xt = _parseTs(x['timestamp']) ?? DateTime.fromMillisecondsSinceEpoch(0);
      final yt = _parseTs(y['timestamp']) ?? DateTime.fromMillisecondsSinceEpoch(0);
      return xt.compareTo(yt);
    });

    return unique;
  }

  _DocBundle _makeDocBundle({
    required String docId,
    required String plateNumber,
    required Map<String, dynamic> meta,
    required List<Map<String, dynamic>> logs,
  }) {
    final plateFourDigit = _toStr(meta['plate_four_digit']) ?? _toStr(meta['plateFourDigit']);
    final billingType = _toStr(meta['billingType']);
    final location = _toStr(meta['location']);
    final userName = _toStr(meta['userName']);
    final customStatus = _toStr(meta['customStatus']);
    final type = _toStr(meta['type']);

    final basicAmount = _toNum(meta['basicAmount']);
    final addAmount = _toNum(meta['addAmount']);
    final regularAmount = _toNum(meta['regularAmount']);
    final userAdjustment = _toNum(meta['userAdjustment']);

    final lockedFeeAmount = _toNum(meta['lockedFeeAmount']) ??
        _toNum(meta['lockedFee']) ??
        _pickNumFromLogs(logs, ['lockedFee', 'lockedFeeAmount', 'lockedFeeAmount']);

    final paymentMethod = _toStr(meta['paymentMethod']) ?? _pickStrFromLogs(logs, ['paymentMethod']);

    final requestTime = _parseTs(meta['request_time'] ?? meta['requestTime']);
    final updatedAt = _parseTs(meta['updatedAt']);
    final parkingCompletedAt = _parseTs(meta['parkingCompletedAt']);
    final departureCompletedAt = _parseTs(meta['departureCompletedAt']);

    final lastLogTime = logs.isNotEmpty ? _parseTs(logs.last['timestamp']) : null;

    return _DocBundle(
      docId: docId,
      plateNumber: plateNumber,
      plateFourDigit: plateFourDigit,
      billingType: billingType,
      location: location,
      userName: userName,
      customStatus: customStatus,
      type: type,
      paymentMethod: paymentMethod,
      lockedFeeAmount: lockedFeeAmount,
      basicAmount: basicAmount,
      addAmount: addAmount,
      regularAmount: regularAmount,
      userAdjustment: userAdjustment,
      requestTime: requestTime,
      updatedAt: updatedAt,
      parkingCompletedAt: parkingCompletedAt,
      departureCompletedAt: departureCompletedAt,
      lastLogTime: lastLogTime,
      meta: meta,
      logs: logs,
    );
  }

  _DocBundle _mergeDocBundles(_DocBundle a, _DocBundle b) {
    final aU = a.updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
    final bU = b.updatedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
    final preferB = bU.isAfter(aU);

    final primary = preferB ? b : a;
    final secondary = preferB ? a : b;

    final mergedMeta = <String, dynamic>{};
    mergedMeta.addAll(secondary.meta);
    mergedMeta.addAll(primary.meta);

    final mergedLogs = _mergeLogs(a.logs, b.logs);

    final mergedPlate = primary.plateNumber.isNotEmpty ? primary.plateNumber : secondary.plateNumber;

    return _makeDocBundle(
      docId: primary.docId,
      plateNumber: mergedPlate,
      meta: mergedMeta,
      logs: mergedLogs,
    );
  }

  List<String> _monthKeysBetween(DateTime start, DateTime end) {
    final s = DateTime(start.year, start.month, 1);
    final e = DateTime(end.year, end.month, 1);
    final acc = <String>[];
    for (DateTime cur = s; !cur.isAfter(e); cur = DateTime(cur.year, cur.month + 1, 1)) {
      acc.add(_yyyymm(cur));
    }
    return acc;
  }

  // ===== 사진 다이얼로그 열기 =====
  void _openPlateImageDialog(String plateNumber) {
    try {
      showGeneralDialog(
        context: context,
        barrierDismissible: true,
        barrierLabel: "사진 보기",
        transitionDuration: const Duration(milliseconds: 300),
        pageBuilder: (_, __, ___) => DepartureCompletedPlateImageDialog(plateNumber: plateNumber),
      );
    } catch (e) {
      _logApiError(
        tag: '_MergedLogSectionState._openPlateImageDialog',
        message: '사진 다이얼로그 오픈 실패',
        error: e,
        extra: <String, dynamic>{'plateNumber': plateNumber},
        tags: const <String>[_tLogs, _tLogsUi],
      );
    }
  }

  // ===== GCS 로드 =====
  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _days.clear();
      _hits.clear();
      _selectedHit = null;
      _expandedDocIds.clear();
    });

    try {
      final division = widget.division.trim();
      final area = widget.area.trim();
      if (division.isEmpty || area.isEmpty) {
        throw StateError('지역/사업부가 설정되지 않았습니다. (division/area)');
      }

      final s0 = DateTime(_start.year, _start.month, _start.day);
      final e0 = DateTime(_end.year, _end.month, _end.day);
      final start = s0.isAfter(e0) ? e0 : s0;
      final end = s0.isAfter(e0) ? s0 : e0;

      final gcsHelper = _GcsHelper();

      final monthKeys = _monthKeysBetween(start, end);
      final names = <String>[];

      for (final mk in monthKeys) {
        final prefixMonth = '$division/$area/logs/$mk/';
        final partial = await gcsHelper.listObjects(prefixMonth);
        names.addAll(partial);
      }

      if (names.isEmpty) {
        final legacyPrefix = '$division/$area/logs/';
        names.addAll(await gcsHelper.listObjects(legacyPrefix));
      }

      final wantedSuffix = <String>{};
      for (DateTime d = start; !d.isAfter(end); d = d.add(const Duration(days: 1))) {
        wantedSuffix.add('_ToDoLogs_${_yyyymmdd(d)}.json');
      }

      final inRange = names.where((n) => wantedSuffix.any((suf) => n.endsWith(suf))).toList()..sort();

      if (inRange.isEmpty) {
        // 운영 분석용 로그
        await _logApiError(
          tag: '_MergedLogSectionState._load',
          message: '해당 기간에 로그 파일이 없음',
          error: StateError('no_files_in_range'),
          extra: <String, dynamic>{
            'division': division,
            'area': area,
            'start': _yyyymmdd(start),
            'end': _yyyymmdd(end),
            'monthKeys': monthKeys,
            'listedCount': names.length,
          },
          tags: const <String>[_tLogs, _tLogsLoad],
        );

        final prefixHint = '$division/$area/logs/<YYYYMM>/...';
        throw StateError('해당 기간에 파일이 없습니다.\nprefix=$prefixHint\nrange=${_yyyymmdd(start)}~${_yyyymmdd(end)}');
      }

      final Map<String, Map<String, _DocBundle>> dayDocMap = {};

      for (final objectName in inRange) {
        final m = RegExp(r'_ToDoLogs_(\d{4}-\d{2}-\d{2})\.json$').firstMatch(objectName);
        final dateStr = m?.group(1) ?? 'Unknown';

        final json = await gcsHelper.loadJsonByObjectName(objectName);
        final List items = (json['items'] as List?) ?? (json['data'] as List?) ?? const [];

        final Map<String, _DocBundle> docsById = dayDocMap.putIfAbsent(dateStr, () => <String, _DocBundle>{});

        for (final raw in items) {
          final item = _asMap(raw);
          if (item == null) continue;

          final docId = (item['docId'] ?? '').toString();
          if (docId.isEmpty) continue;

          final meta = _extractMeta(item);
          final plate = _extractPlate(item, meta, docId);
          final logs = _extractLogs(item);

          final doc = _makeDocBundle(docId: docId, plateNumber: plate, meta: meta, logs: logs);

          final existing = docsById[docId];
          if (existing == null) {
            docsById[docId] = doc;
          } else {
            docsById[docId] = _mergeDocBundles(existing, doc);
          }
        }
      }

      final dayKeys = dayDocMap.keys.toList()..sort();
      for (final dateStr in dayKeys) {
        final docs = dayDocMap[dateStr]!.values.toList();
        docs.sort((a, b) {
          final at = a.lastLogTime ?? DateTime.fromMillisecondsSinceEpoch(0);
          final bt = b.lastLogTime ?? DateTime.fromMillisecondsSinceEpoch(0);
          return at.compareTo(bt);
        });
        _days.add(_DayBundle(dateStr: dateStr, docs: docs));
      }

      setState(() => _loading = false);
    } catch (e) {
      await _logApiError(
        tag: '_MergedLogSectionState._load',
        message: 'GCS 로그 로드 실패',
        error: e,
        extra: <String, dynamic>{
          'division': widget.division,
          'area': widget.area,
          'start': _yyyymmdd(_start),
          'end': _yyyymmdd(_end),
        },
        tags: const <String>[_tLogs, _tLogsLoad],
      );

      setState(() {
        _loading = false;
        _error = '로드 실패: $e';
      });
    }
  }

  // ===== 검색 =====
  Future<void> _search() async {
    final q = _tailCtrl.text.trim();

    if (!_validTail(q)) {
      setState(() {
        _error = '번호판 4자리를 입력하세요.';
        _hits = [];
        _selectedHit = null;
      });
      return;
    }

    try {
      setState(() {
        _error = null;
        _hits = [];
        _selectedHit = null;
      });

      final hits = <_SearchHit>[];
      for (final day in _days) {
        for (final doc in day.docs) {
          final tail = _tail4OfPlate(doc.plateNumber, doc.docId, plateFourDigit: doc.plateFourDigit);
          if (tail == q) {
            hits.add(_SearchHit(dateStr: day.dateStr, doc: doc));
          }
        }
      }

      setState(() => _hits = hits);

      if (_currentPage != 1) {
        _pageController.animateToPage(1, duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
      }
    } catch (e) {
      await _logApiError(
        tag: '_MergedLogSectionState._search',
        message: '검색 처리 실패',
        error: e,
        extra: <String, dynamic>{
          'query': q,
          'daysCount': _days.length,
        },
        tags: const <String>[_tLogs, _tLogsSearch],
      );

      setState(() {
        _error = '검색 실패: $e';
        _hits = [];
        _selectedHit = null;
      });
    }
  }

  // ===== UI 헬퍼: 문서 요약 =====
  Widget _infoChip(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '$label: $value',
        style: const TextStyle(fontSize: 12, color: Colors.black87),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  Widget _buildDocSummary(_DocBundle doc) {
    final feeText = _fmtWon(doc.lockedFeeAmount);
    final payText = doc.paymentMethod ?? '—';

    final billingText = doc.billingType ?? '—';
    final locText = doc.location ?? '—';
    final userText = doc.userName ?? '—';
    final customText =
    (doc.customStatus != null && doc.customStatus!.trim().isNotEmpty) ? doc.customStatus! : '—';
    final typeText = doc.type ?? '—';

    final basicText = _fmtWon(doc.basicAmount);
    final addText = _fmtWon(doc.addAmount);
    final regularText = _fmtWon(doc.regularAmount);
    final adjText = _fmtWon(doc.userAdjustment);

    final reqText = _fmtDateTime(doc.requestTime);
    final updText = _fmtDateTime(doc.updatedAt);
    final depText = _fmtDateTime(doc.departureCompletedAt);
    final parkText = _fmtDateTime(doc.parkingCompletedAt);

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  doc.plateNumber.isNotEmpty ? doc.plateNumber : doc.docId,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(feeText, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                  Text(payText, style: const TextStyle(fontSize: 12, color: Colors.black54)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _infoChip('상태', typeText),
              _infoChip('과금', billingText),
              _infoChip('위치', locText),
              _infoChip('담당', userText),
              _infoChip('메모', customText),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _infoChip('기본', basicText),
              _infoChip('추가', addText),
              _infoChip('정규', regularText),
              _infoChip('조정', adjText),
            ],
          ),
          const SizedBox(height: 10),
          Text('요청: $reqText', style: const TextStyle(fontSize: 12, color: Colors.black54)),
          Text('업데이트: $updText', style: const TextStyle(fontSize: 12, color: Colors.black54)),
          Text('입차완료: $parkText', style: const TextStyle(fontSize: 12, color: Colors.black54)),
          Text('출차완료: $depText', style: const TextStyle(fontSize: 12, color: Colors.black54)),
        ],
      ),
    );
  }

  // ===== UI =====
  @override
  Widget build(BuildContext context) {
    final hasData = !_loading && _days.isNotEmpty;
    final mono = const TextStyle(fontFeatures: [FontFeature.tabularFigures()]);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: RangeControls(
                start: _start,
                end: _end,
                loading: _loading,
                onRangePicked: (range) {
                  final s = DateTime(range.start.year, range.start.month, range.start.day);
                  final e = DateTime(range.end.year, range.end.month, range.end.day);
                  setState(() {
                    if (s.isAfter(e)) {
                      _start = e;
                      _end = s;
                    } else {
                      _start = s;
                      _end = e;
                    }
                  });
                },
                onLoad: _load,
              ),
            ),
            const SizedBox(width: 6),
            SizedBox(
              width: 44,
              child: IconButton(
                tooltip: _currentPage == 0 ? '검색 화면으로' : '목록 화면으로',
                onPressed: () {
                  final next = (_currentPage == 0) ? 1 : 0;
                  try {
                    _pageController.animateToPage(
                      next,
                      duration: const Duration(milliseconds: 200),
                      curve: Curves.easeOut,
                    );
                  } catch (e) {
                    _logApiError(
                      tag: '_MergedLogSectionState.build.togglePage',
                      message: '페이지 전환(animateToPage) 실패',
                      error: e,
                      extra: <String, dynamic>{'from': _currentPage, 'to': next},
                      tags: const <String>[_tLogs, _tLogsUi],
                    );
                  }
                },
                icon: Icon(_currentPage == 0 ? Icons.search : Icons.list),
                visualDensity: VisualDensity.compact,
              ),
            ),
          ],
        ),
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(_error!, style: const TextStyle(color: Colors.red)),
        ],
        const SizedBox(height: 8),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : !hasData
              ? const Center(child: Text('기간을 설정하고 불러오기를 눌러주세요.'))
              : PageView(
            controller: _pageController,
            onPageChanged: (i) => setState(() => _currentPage = i),
            children: [
              Scrollbar(
                child: ListView.builder(
                  padding: const EdgeInsets.only(bottom: 12),
                  itemCount: _days.length,
                  itemBuilder: (_, i) {
                    final day = _days[i];
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          color: Colors.grey.shade200,
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(day.dateStr, style: const TextStyle(fontWeight: FontWeight.bold)),
                              const SizedBox(height: 8),
                              SizedBox(
                                height: 24,
                                child: Row(
                                  children: const [
                                    SizedBox(
                                      width: _kTimeColWidth,
                                      child: Text('시간',
                                          style: TextStyle(fontSize: 12, color: Colors.black54),
                                          textAlign: TextAlign.center),
                                    ),
                                    SizedBox(width: 8),
                                    Expanded(
                                      child: Text('번호판',
                                          style: TextStyle(fontSize: 12, color: Colors.black54),
                                          textAlign: TextAlign.center),
                                    ),
                                    SizedBox(
                                      width: _kFeeColWidth,
                                      child: Text('요금/결제',
                                          style: TextStyle(fontSize: 12, color: Colors.black54),
                                          textAlign: TextAlign.center),
                                    ),
                                    SizedBox(width: _kChevronWidth),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        ...day.docs.map((doc) {
                          final expanded = _expandedDocIds.contains(doc.docId);
                          final lastTs = doc.lastLogTime;

                          final feeText = _fmtWon(doc.lockedFeeAmount);
                          final payText = doc.paymentMethod ?? '—';

                          return Column(
                            children: [
                              InkWell(
                                onTap: () {
                                  setState(() {
                                    if (expanded) {
                                      _expandedDocIds.remove(doc.docId);
                                    } else {
                                      _expandedDocIds.add(doc.docId);
                                    }
                                  });
                                },
                                child: Container(
                                  height: _kRowHeight,
                                  padding: const EdgeInsets.symmetric(horizontal: 12),
                                  decoration: const BoxDecoration(
                                    border: Border(bottom: BorderSide(color: Color(0xFFE0E0E0))),
                                  ),
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.center,
                                    children: [
                                      SizedBox(
                                        width: _kTimeColWidth,
                                        child: Text(
                                          _fmtTime(lastTs),
                                          maxLines: 1,
                                          softWrap: false,
                                          overflow: TextOverflow.clip,
                                          textAlign: TextAlign.center,
                                          style: mono.copyWith(fontSize: 15),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          doc.plateNumber.isNotEmpty ? doc.plateNumber : doc.docId,
                                          maxLines: 1,
                                          softWrap: false,
                                          overflow: TextOverflow.ellipsis,
                                          textAlign: TextAlign.center,
                                          style: const TextStyle(fontSize: 16),
                                        ),
                                      ),
                                      SizedBox(
                                        width: _kFeeColWidth,
                                        child: Column(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            Text(feeText,
                                                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                                            Text(payText,
                                                style: const TextStyle(fontSize: 11, color: Colors.black54),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis),
                                          ],
                                        ),
                                      ),
                                      SizedBox(
                                        width: _kChevronWidth,
                                        child: Icon(
                                          expanded ? Icons.expand_less : Icons.expand_more,
                                          size: 20,
                                          color: Colors.black54,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              if (expanded) ...[
                                _buildDocSummary(doc),
                                _buildLogsDetail(doc.logs, plateNumber: doc.plateNumber, scrollable: false),
                              ],
                            ],
                          );
                        }),
                      ],
                    );
                  },
                ),
              ),
              _buildSearchPage(),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 6.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _Dot(active: _currentPage == 0),
              const SizedBox(width: 6),
              _Dot(active: _currentPage == 1),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSearchPage() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _tailCtrl,
                maxLength: 4,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  counterText: '',
                  labelText: '번호판 4자리',
                  hintText: '예) 4444',
                  border: OutlineInputBorder(),
                ),
                onSubmitted: (_) => _search(),
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton.icon(
              onPressed: _loading || _days.isEmpty ? null : _search,
              icon: const Icon(Icons.search),
              label: const Text('검색'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Expanded(
          child: _hits.isEmpty
              ? const Center(child: Text('검색 결과가 없습니다.'))
              : (_selectedHit == null
              ? ListView.separated(
            itemCount: _hits.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, i) {
              final h = _hits[i];
              final feeText = _fmtWon(h.doc.lockedFeeAmount);
              final payText = h.doc.paymentMethod ?? '—';
              final lastTs = h.doc.lastLogTime;

              return ListTile(
                dense: true,
                title: Text(h.doc.plateNumber.isNotEmpty ? h.doc.plateNumber : h.doc.docId),
                subtitle: Text('${h.dateStr} • $feeText • $payText'),
                trailing: Text(_fmtTime(lastTs), style: const TextStyle(fontSize: 12)),
                onTap: () => setState(() => _selectedHit = h),
              );
            },
          )
              : Column(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                color: Colors.grey.shade100,
                child: Row(
                  children: [
                    IconButton(
                      tooltip: '선택 해제',
                      onPressed: () => setState(() => _selectedHit = null),
                      icon: const Icon(Icons.close),
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _selectedHit!.doc.plateNumber.isNotEmpty
                                ? _selectedHit!.doc.plateNumber
                                : _selectedHit!.doc.docId,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${_selectedHit!.dateStr} • ${_selectedHit!.doc.docId}',
                            style: const TextStyle(fontSize: 12, color: Colors.black54),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      onPressed: () {
                        final plate = _selectedHit!.doc.plateNumber.isNotEmpty
                            ? _selectedHit!.doc.plateNumber
                            : _selectedHit!.doc.docId.split('_').first;
                        _openPlateImageDialog(plate);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.grey.shade100,
                        foregroundColor: Colors.black87,
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      ),
                      icon: const Icon(Icons.photo, size: 18),
                      label: const Text('사진', style: TextStyle(fontSize: 13)),
                    ),
                  ],
                ),
              ),
              _buildDocSummary(_selectedHit!.doc),
              Expanded(
                child: _buildLogsDetail(
                  _selectedHit!.doc.logs,
                  plateNumber: _selectedHit!.doc.plateNumber,
                  scrollable: true,
                ),
              ),
            ],
          )),
        ),
      ],
    );
  }

  Widget _buildLogsDetail(
      List<Map<String, dynamic>> logs, {
        required String plateNumber,
        bool scrollable = false,
      }) {
    if (logs.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(12),
        child: Text('로그가 없습니다.'),
      );
    }

    final listView = ListView.separated(
      physics: scrollable ? const AlwaysScrollableScrollPhysics() : const NeverScrollableScrollPhysics(),
      shrinkWrap: !scrollable,
      itemCount: logs.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (_, i) {
        final e = logs[i];
        final action = (e['action'] ?? '-').toString();
        final from = (e['from'] ?? '').toString();
        final to = (e['to'] ?? '').toString();
        final by = (e['performedBy'] ?? '').toString();
        final ts = _parseTs(e['timestamp']);
        final tsText = _fmtDateTime(ts);

        final feeNum = (e['lockedFee'] ?? e['lockedFeeAmount']);
        final fee = (feeNum is num) ? _fmtWon(feeNum) : (feeNum is String ? _fmtWon(num.tryParse(feeNum)) : null);
        final pay = (e['paymentMethod']?.toString().trim().isNotEmpty ?? false) ? e['paymentMethod'].toString() : null;
        final reason = (e['reason']?.toString().trim().isNotEmpty ?? false) ? e['reason'].toString() : null;

        final color = _actionColor(action);

        return ListTile(
          dense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          leading: Icon(_actionIcon(action), color: color),
          title: Text(action, style: TextStyle(fontWeight: FontWeight.w600, color: color)),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (from.isNotEmpty || to.isNotEmpty) Text('$from → $to'),
              if (by.isNotEmpty) const SizedBox(height: 2),
              if (by.isNotEmpty) const Text('담당자:', style: TextStyle(fontSize: 12)),
              if (by.isNotEmpty) Text(by, style: const TextStyle(fontSize: 12)),
              if (fee != null || pay != null || reason != null) const SizedBox(height: 2),
              if (fee != null) Text('확정요금: $fee', style: const TextStyle(fontSize: 12)),
              if (pay != null) Text('결제수단: $pay', style: const TextStyle(fontSize: 12)),
              if (reason != null) Text('사유: $reason', style: const TextStyle(fontSize: 12)),
            ],
          ),
          trailing: Text(tsText, style: const TextStyle(fontSize: 12)),
          isThreeLine: true,
        );
      },
    );

    return Container(
      color: Colors.grey.shade50,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: listView,
    );
  }
}

// ===== 내부 모델 =====
class _DayBundle {
  final String dateStr;
  final List<_DocBundle> docs;

  _DayBundle({required this.dateStr, required this.docs});
}

class _DocBundle {
  final String docId;
  final String plateNumber;

  final String? plateFourDigit;
  final String? billingType;
  final String? location;
  final String? userName;
  final String? customStatus;
  final String? type;

  final String? paymentMethod;
  final num? lockedFeeAmount;
  final num? basicAmount;
  final num? addAmount;
  final num? regularAmount;
  final num? userAdjustment;

  final DateTime? requestTime;
  final DateTime? updatedAt;
  final DateTime? parkingCompletedAt;
  final DateTime? departureCompletedAt;

  final DateTime? lastLogTime;

  final Map<String, dynamic> meta;
  final List<Map<String, dynamic>> logs;

  _DocBundle({
    required this.docId,
    required this.plateNumber,
    required this.plateFourDigit,
    required this.billingType,
    required this.location,
    required this.userName,
    required this.customStatus,
    required this.type,
    required this.paymentMethod,
    required this.lockedFeeAmount,
    required this.basicAmount,
    required this.addAmount,
    required this.regularAmount,
    required this.userAdjustment,
    required this.requestTime,
    required this.updatedAt,
    required this.parkingCompletedAt,
    required this.departureCompletedAt,
    required this.lastLogTime,
    required this.meta,
    required this.logs,
  });
}

class _SearchHit {
  final String dateStr;
  final _DocBundle doc;

  _SearchHit({required this.dateStr, required this.doc});
}

class _Dot extends StatelessWidget {
  final bool active;

  const _Dot({required this.active});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: active ? 20 : 8,
      height: 8,
      decoration: BoxDecoration(
        color: active ? Colors.black87 : Colors.black26,
        borderRadius: BorderRadius.circular(999),
      ),
    );
  }
}
