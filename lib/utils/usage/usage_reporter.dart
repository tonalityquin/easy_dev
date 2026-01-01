// lib/utils/usage/usage_reporter.dart
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

/// 설치 단위 사용량(읽기/쓰기/삭제)을 Firestore에 자가-보고.
/// - 인증 없이 동작 (자가 보고 특성상 조작 방지 한계)
///
/// ✅ 수정안(핵심):
/// - 기존: users/{userKey}/events/{eventId} 문서를 계속 생성(멱등/추적) + 카운터 증가
/// - 변경: events 하위 문서를 생성하지 않고, users/{userKey} 문서의 reads/writes/deletes만 누적
///
/// 경로:
/// usage_daily/{YYYY-MM-DD}/tenants/{area}/users/{userKey}
///
/// userKey:
/// - 기본: `{installId}__{slug(source)}`
/// - useSourceOnlyKey=true일 때: `{slug(source)}`
///   - 단, 이 경우 동일 source로 많은 클라이언트가 쓰면 핫스팟 가능.
///   - 이를 완화하기 위해 sourceShardCount>1 옵션을 제공(문서 ID에 shard suffix 추가).
class UsageReporter {
  UsageReporter._();

  static final UsageReporter instance = UsageReporter._();

  final _db = FirebaseFirestore.instance;

  String? _installId;
  Future<void>? _initFuture;

  /// ✅ 단기간 다중 호출을 1회 배치로 합쳐서 write 비용/경합을 줄이기 위한 버퍼
  final Map<String, _PendingDocUpdate> _pending = {};
  Timer? _flushTimer;

  /// ✅ 기본 flush 지연(짧게 잡아도 다중 호출을 합치는데 충분)
  static const Duration _defaultFlushDelay = Duration(milliseconds: 600);

  /// ✅ 한 번의 batch commit 최대 write 수(Firestore batch 제한 500)
  static const int _maxBatchWrites = 450;

  Future<void> init() async {
    final sp = await SharedPreferences.getInstance();
    var id = sp.getString('installId');
    if (id == null) {
      id = const Uuid().v4();
      await sp.setString('installId', id);
    }
    _installId = id;
  }

  Future<void> ensureInitialized() {
    return _initFuture ??= init();
  }

  Future<String> getInstallId() async {
    await ensureInitialized();
    final id = _installId;
    if (id == null) {
      throw StateError('UsageReporter 초기화 실패');
    }
    return id;
  }

  String get installId {
    final id = _installId;
    if (id == null) {
      throw StateError('UsageReporter.init()을 먼저 호출하세요.');
    }
    return id;
  }

  /// 메서드/화면명을 slug로 변환해 문서 ID로 안전하게 사용
  String _slug(String s) {
    final lower = s.trim().toLowerCase();
    // 영문/숫자/언더스코어/하이픈/점만 남기고 나머지는 하이픈으로
    final cleaned = lower.replaceAll(RegExp(r'[^a-z0-9_\-\.]+'), '-');
    // 길이 과도 방지(문서 ID 제한 충분히 넉넉하지만 안전 차원)
    return cleaned.length > 120 ? cleaned.substring(0, 120) : cleaned;
  }

  /// ✅ 로컬(디바이스) 기준 YYYY-MM-DD (UTC가 아니라 “현지 일자” 기준 집계)
  String _localDateKey(DateTime now) {
    final y = now.year.toString().padLeft(4, '0');
    final m = now.month.toString().padLeft(2, '0');
    final d = now.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  /// ✅ 간단/안정적인 32-bit FNV-1a 해시(샤딩 인덱스 산출용)
  int _fnv1a32(String s) {
    const int fnvPrime = 0x01000193;
    const int offsetBasis = 0x811C9DC5;
    int hash = offsetBasis;
    for (final codeUnit in s.codeUnits) {
      hash ^= codeUnit;
      hash = (hash * fnvPrime) & 0xFFFFFFFF;
    }
    return hash & 0x7FFFFFFF;
  }

  /// userKey 생성
  /// - useSourceOnlyKey=false : installId__sourceSlug (분산/핫스팟 완화)
  /// - useSourceOnlyKey=true  : sourceSlug (집계 단순, 그러나 핫스팟 위험)
  ///   - sourceShardCount>1이면: sourceSlug__sXX 형태로 샤딩(집계는 shard 합산)
  String _buildUserKey({
    required String baseId,
    required String? srcSlug,
    required bool useSourceOnlyKey,
    required int sourceShardCount,
  }) {
    if (!useSourceOnlyKey) {
      return (srcSlug == null) ? baseId : '${baseId}__$srcSlug';
    }

    // source-only
    final key = srcSlug ?? baseId;
    final shards = (sourceShardCount <= 0) ? 1 : sourceShardCount;

    if (srcSlug != null && shards > 1) {
      final idx = _fnv1a32(baseId) % shards;
      final suffix = idx.toString().padLeft(2, '0');
      return '${key}__s$suffix';
    }

    return key;
  }

  DocumentReference<Map<String, dynamic>> _counterDocRef({
    required String date,
    required String area,
    required String userKey,
  }) {
    return _db
        .collection('usage_daily')
        .doc(date)
        .collection('tenants')
        .doc(area)
        .collection('users')
        .doc(userKey);
  }

  void _scheduleFlush([Duration delay = _defaultFlushDelay]) {
    _flushTimer?.cancel();
    _flushTimer = Timer(delay, () {
      _flushTimer = null;
      // ✅ unawaited 제거: Dart/Flutter 버전에 따라 unawaited 미존재 이슈 방지
      // 타이머 콜백에서 await 불가이므로 그냥 호출만 하고, Future는 무시합니다.
      flush();
    });
  }

  /// ✅ 외부에서 강제 flush(필요 시)
  Future<void> flush() async {
    await ensureInitialized();

    if (_pending.isEmpty) return;

    // 스냅샷 후 비우기
    final entries = _pending.entries.toList(growable: false);
    _pending.clear();

    // batch 제한 고려: 여러 batch로 쪼개 커밋
    int cursor = 0;
    while (cursor < entries.length) {
      final end = (cursor + _maxBatchWrites < entries.length)
          ? cursor + _maxBatchWrites
          : entries.length;

      final batch = _db.batch();

      for (int i = cursor; i < end; i++) {
        final e = entries[i];
        final path = e.key;
        final upd = e.value;

        final docRef = _db.doc(path);

        final Map<String, dynamic> payload = {
          'date': upd.date,
          'tenantId': upd.area,
          'userId': upd.userKey,
          'updatedAt': FieldValue.serverTimestamp(),
        };

        if (upd.reads > 0) payload['reads'] = FieldValue.increment(upd.reads);
        if (upd.writes > 0) payload['writes'] = FieldValue.increment(upd.writes);
        if (upd.deletes > 0) payload['deletes'] = FieldValue.increment(upd.deletes);

        // ✅ trace(흔적)는 마지막 값만 유지(무한 누적 방지)
        if (upd.hasTrace) {
          payload['lastTraceAt'] = FieldValue.serverTimestamp();
          if (upd.lastTraceSource != null) {
            payload['lastTraceSource'] = upd.lastTraceSource;
          }
          if (upd.lastTraceExtra != null) {
            payload['lastTraceExtra'] = upd.lastTraceExtra;
          }
        }

        batch.set(docRef, payload, SetOptions(merge: true));
      }

      await batch.commit();
      cursor = end;
    }
  }

  /// 사용량 보고(카운터 증가)
  ///
  /// [area]: 테넌트/기업 식별자
  /// [action]: "read"|"write"|"delete"
  /// [n]: 개수
  /// [source]: 비용 발생 지점(메서드/화면명)
  ///
  /// 옵션:
  /// - useSourceOnlyKey=true: userKey에 installId prefix 제거(집계 단순, 핫스팟 위험)
  /// - sourceShardCount: useSourceOnlyKey=true일 때 샤딩 수(>1 권장 시 핫스팟 완화)
  /// - flushDelay: 버퍼 flush 지연(짧을수록 실시간성↑, 길수록 write↓)
  Future<void> report({
    required String area,
    required String action,
    int n = 1,
    String? source,
    bool useSourceOnlyKey = false,
    int sourceShardCount = 1,
    Duration flushDelay = _defaultFlushDelay,
  }) async {
    assert(action == 'read' || action == 'write' || action == 'delete');
    if (n <= 0) return;

    await ensureInitialized();

    final baseId = installId;
    final srcSlug = (source == null || source.trim().isEmpty) ? null : _slug(source);

    final userKey = _buildUserKey(
      baseId: baseId,
      srcSlug: srcSlug,
      useSourceOnlyKey: useSourceOnlyKey,
      sourceShardCount: sourceShardCount,
    );

    final date = _localDateKey(DateTime.now());
    final docRef = _counterDocRef(date: date, area: area, userKey: userKey);
    final docPath = docRef.path;

    final pending = _pending.putIfAbsent(
      docPath,
          () => _PendingDocUpdate(date: date, area: area, userKey: userKey),
    );

    // 안전: 동일 path라도 날짜/area/userKey가 다르면 새 객체로 교체
    if (pending.date != date || pending.area != area || pending.userKey != userKey) {
      _pending[docPath] = _PendingDocUpdate(date: date, area: area, userKey: userKey);
    }

    final upd = _pending[docPath]!;
    switch (action) {
      case 'read':
        upd.reads += n;
        break;
      case 'write':
        upd.writes += n;
        break;
      case 'delete':
        upd.deletes += n;
        break;
    }

    _scheduleFlush(flushDelay);
  }

  /// 샘플링 보고
  /// - sampleRate 확률로 report(카운터 증가)
  /// - 그 외에는 annotate(카운터 증가 없이 흔적만)
  ///
  /// ✅ 주의:
  /// - events 하위 문서를 만들지 않으므로 “완전한 멱등”은 보장 불가
  /// - telemetry 용도로는 통상 허용(약간의 중복 허용)
  Future<void> reportSampled({
    required String area,
    required String action,
    int n = 1,
    String? source,
    double sampleRate = 0.2,
    bool useSourceOnlyKey = false,
    int sourceShardCount = 1,
    Duration flushDelay = _defaultFlushDelay,
  }) async {
    assert(sampleRate >= 0 && sampleRate <= 1.0);

    // 간단한 난수(외부 의존 최소화)
    final seed = DateTime.now().microsecondsSinceEpoch ^ _fnv1a32(installId);
    final r = (seed % 10000) / 10000.0;

    if (r <= sampleRate) {
      await report(
        area: area,
        action: action,
        n: n,
        source: source,
        useSourceOnlyKey: useSourceOnlyKey,
        sourceShardCount: sourceShardCount,
        flushDelay: flushDelay,
      );
    } else {
      await annotate(
        area: area,
        source: source,
        extra: {'action': action, 'n': n, 'sampled': true},
        useSourceOnlyKey: useSourceOnlyKey,
        sourceShardCount: sourceShardCount,
        flushDelay: flushDelay,
      );
    }
  }

  /// 🔎 카운터를 증가시키지 않고 "흔적만" 남기는 보고
  /// - 기존: events/{eventId}에 trace 기록
  /// - 변경: 동일 카운터 문서에 lastTrace* 필드만 갱신(마지막 1개만 유지)
  Future<void> annotate({
    required String area,
    String? source,
    Map<String, dynamic>? extra,
    bool useSourceOnlyKey = false,
    int sourceShardCount = 1,
    Duration flushDelay = _defaultFlushDelay,
  }) async {
    await ensureInitialized();

    final baseId = installId;
    final srcSlug = (source == null || source.trim().isEmpty) ? null : _slug(source);

    final userKey = _buildUserKey(
      baseId: baseId,
      srcSlug: srcSlug,
      useSourceOnlyKey: useSourceOnlyKey,
      sourceShardCount: sourceShardCount,
    );

    final date = _localDateKey(DateTime.now());
    final docRef = _counterDocRef(date: date, area: area, userKey: userKey);
    final docPath = docRef.path;

    final pending = _pending.putIfAbsent(
      docPath,
          () => _PendingDocUpdate(date: date, area: area, userKey: userKey),
    );

    if (pending.date != date || pending.area != area || pending.userKey != userKey) {
      _pending[docPath] = _PendingDocUpdate(date: date, area: area, userKey: userKey);
    }

    final upd = _pending[docPath]!;
    upd.hasTrace = true;
    upd.lastTraceSource = source;
    upd.lastTraceExtra = extra;

    _scheduleFlush(flushDelay);
  }
}

class _PendingDocUpdate {
  final String date;
  final String area;
  final String userKey;

  int reads = 0;
  int writes = 0;
  int deletes = 0;

  bool hasTrace = false;
  String? lastTraceSource;
  Map<String, dynamic>? lastTraceExtra;

  _PendingDocUpdate({
    required this.date,
    required this.area,
    required this.userKey,
  });
}
