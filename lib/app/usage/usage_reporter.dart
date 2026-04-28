import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../../features/dev/data/repositories/usage_repo_package/firestore_usage_report_repository.dart';
import '../../features/dev/domain/repositories/usage_repo_package/usage_report_repository.dart';

class UsageReporter {
  UsageReporter._();

  static final UsageReporter instance = UsageReporter._();

  static UsageReportRepository _repository = FirestoreUsageReportRepository();

  static void configureRepository(UsageReportRepository repository) {
    _repository = repository;
  }

  String? _installId;
  Future<void>? _initFuture;

  final Map<String, _PendingDocUpdate> _pending = {};
  Timer? _flushTimer;

  static const Duration _defaultFlushDelay = Duration(milliseconds: 600);

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

  String _slug(String s) {
    final lower = s.trim().toLowerCase();
    final cleaned = lower.replaceAll(RegExp(r'[^a-z0-9_\-\.]+'), '-');
    return cleaned.length > 120 ? cleaned.substring(0, 120) : cleaned;
  }

  String _localDateKey(DateTime now) {
    final y = now.year.toString().padLeft(4, '0');
    final m = now.month.toString().padLeft(2, '0');
    final d = now.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  int _fnv1a32(String s) {
    const int fnvPrime = 0x01000193;
    const int offsetBasis = 0x811C9DC5;
    var hash = offsetBasis;
    for (final codeUnit in s.codeUnits) {
      hash ^= codeUnit;
      hash = (hash * fnvPrime) & 0xFFFFFFFF;
    }
    return hash & 0x7FFFFFFF;
  }

  String _buildUserKey({
    required String baseId,
    required String? srcSlug,
    required bool useSourceOnlyKey,
    required int sourceShardCount,
  }) {
    if (!useSourceOnlyKey) {
      return (srcSlug == null) ? baseId : '${baseId}__$srcSlug';
    }

    final key = srcSlug ?? baseId;
    final shards = (sourceShardCount <= 0) ? 1 : sourceShardCount;

    if (srcSlug != null && shards > 1) {
      final idx = _fnv1a32(baseId) % shards;
      final suffix = idx.toString().padLeft(2, '0');
      return '${key}__s$suffix';
    }

    return key;
  }

  String _counterDocPath({
    required String date,
    required String area,
    required String userKey,
  }) {
    return 'usage_daily/$date/tenants/$area/users/$userKey';
  }

  void _scheduleFlush([Duration delay = _defaultFlushDelay]) {
    _flushTimer?.cancel();
    _flushTimer = Timer(delay, () {
      _flushTimer = null;
      flush();
    });
  }

  Future<void> flush() async {
    await ensureInitialized();

    if (_pending.isEmpty) return;

    final entries = _pending.entries.toList(growable: false);
    _pending.clear();

    final updates = entries
        .map((e) => UsageCounterDocUpdate(
              documentPath: e.key,
              date: e.value.date,
              area: e.value.area,
              userKey: e.value.userKey,
              reads: e.value.reads,
              writes: e.value.writes,
              deletes: e.value.deletes,
              hasTrace: e.value.hasTrace,
              lastTraceSource: e.value.lastTraceSource,
              lastTraceExtra: e.value.lastTraceExtra,
            ))
        .toList(growable: false);

    await _repository.flushDocUpdates(updates);
  }

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
    final srcSlug =
        (source == null || source.trim().isEmpty) ? null : _slug(source);

    final userKey = _buildUserKey(
      baseId: baseId,
      srcSlug: srcSlug,
      useSourceOnlyKey: useSourceOnlyKey,
      sourceShardCount: sourceShardCount,
    );

    final date = _localDateKey(DateTime.now());
    final docPath = _counterDocPath(date: date, area: area, userKey: userKey);

    final pending = _pending.putIfAbsent(
      docPath,
      () => _PendingDocUpdate(date: date, area: area, userKey: userKey),
    );

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
    final srcSlug =
        (source == null || source.trim().isEmpty) ? null : _slug(source);

    final userKey = _buildUserKey(
      baseId: baseId,
      srcSlug: srcSlug,
      useSourceOnlyKey: useSourceOnlyKey,
      sourceShardCount: sourceShardCount,
    );

    final date = _localDateKey(DateTime.now());
    final docPath = _counterDocPath(date: date, area: area, userKey: userKey);

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
