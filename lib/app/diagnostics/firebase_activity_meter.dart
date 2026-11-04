import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';

import '../../features/selector/application/dev_auth.dart';
import '../utils/secure_auth_diagnostics.dart';
import 'firebase_activity_journal.dart';

@immutable
class FirebaseActivityEvent {
  const FirebaseActivityEvent({
    required this.time,
    required this.service,
    required this.operation,
    required this.source,
    required this.result,
    required this.elapsedMs,
    required this.eventId,
    required this.sessionId,
    required this.origin,
    this.operationId,
    this.documents,
    this.bytes,
    this.fromCache,
    this.detail,
    this.committedWrites = 0,
    this.committedDeletes = 0,
  });

  final DateTime time;
  final String service;
  final String operation;
  final String source;
  final String result;
  final int elapsedMs;
  final String eventId;
  final String sessionId;
  final String origin;
  final String? operationId;
  final int? documents;
  final int? bytes;
  final bool? fromCache;
  final String? detail;
  final int committedWrites;
  final int committedDeletes;

  String get line {
    final fields = <String>[
      '[FIREBASE_ACTIVITY]',
      'timestamp=${time.toIso8601String()}',
      'service=$service',
      'operation=$operation',
      'source=$source',
      'result=$result',
      'elapsedMs=$elapsedMs',
      'eventId=$eventId',
      'sessionId=$sessionId',
      'origin=$origin',
      if (operationId != null) 'operationId=$operationId',
      if (documents != null) 'documents=$documents',
      if (bytes != null) 'payloadBytes=$bytes',
      if (fromCache != null) 'fromCache=$fromCache',
      if (committedWrites > 0) 'committedWrites=$committedWrites',
      if (committedDeletes > 0) 'committedDeletes=$committedDeletes',
      if (detail != null) 'detail=$detail',
    ];
    return SecureAuthDiagnostics.redact(fields.join(' '));
  }
}

@immutable
class FirebaseActivitySummary {
  const FirebaseActivitySummary({
    this.read = 0,
    this.write = 0,
    this.delete = 0,
    this.snap = 0,
    this.activeListeners = 0,
    this.storage = 0,
    this.aggregation = 0,
    this.transaction = 0,
    this.batch = 0,
    this.errors = 0,
    this.uploadBytes = 0,
    this.downloadBytes = 0,
    this.eventCount = 0,
    this.resultDocuments = 0,
    this.cacheResults = 0,
    this.serverResults = 0,
    this.committedWrites = 0,
    this.committedDeletes = 0,
  });

  final int read;
  final int write;
  final int delete;
  final int snap;
  final int activeListeners;
  final int storage;
  final int aggregation;
  final int transaction;
  final int batch;
  final int errors;
  final int uploadBytes;
  final int downloadBytes;
  final int eventCount;
  final int resultDocuments;
  final int cacheResults;
  final int serverResults;
  final int committedWrites;
  final int committedDeletes;
}

@immutable
class FirebaseCostSummary {
  const FirebaseCostSummary(
    this.activity, {
    this.archived = false,
    this.listenStarts = 0,
    this.listenCancels = 0,
  });

  final FirebaseActivitySummary activity;
  final bool archived;
  final int listenStarts;
  final int listenCancels;

  List<String> get observed => <String>[
        'READ CALLS ${activity.read} · RESULT DOCS ${activity.resultDocuments}',
        'CACHE RESULTS ${activity.cacheResults} · SERVER RESULTS ${activity.serverResults}',
        'COMMITTED WRITES ${activity.write} · DELETES ${activity.delete}',
        'TRANSACTION COMMIT WRITES ${activity.committedWrites} · DELETES ${activity.committedDeletes}',
        archived
            ? 'SNAP EVENTS ${activity.snap} · LISTEN START ${listenStarts} · LISTEN CANCEL ${listenCancels}'
            : 'SNAP EVENTS ${activity.snap} · ACTIVE LISTENERS ${activity.activeListeners}',
        'STORAGE OPS ${activity.storage} · UPLOAD PAYLOAD ${activity.uploadBytes}B · DOWNLOAD PAYLOAD ${activity.downloadBytes}B',
        'ERROR EVENTS ${activity.errors}',
      ];

  List<String> get estimated => const <String>[
        '요금 추정값 미산출: 앱에서 관측한 호출·문서 수·본문 크기는 청구 단위와 일치하지 않을 수 있습니다.',
        '서버 결과 문서 수는 과금 읽기 수의 확정값이나 하한값으로 사용하지 않습니다.',
        '실제 비용은 Firebase Console·Google Cloud Billing의 프로젝트 지표와 대조해야 합니다.',
      ];

  List<String> get unavailable => const <String>[
        'Firestore 인덱스 항목 읽기와 Security Rules 의존 읽기',
        'SDK 내부 재시도·재연결의 청구 상세 및 서버 측 작업',
        'Firestore·Storage 전체 저장 용량 및 객체 수명',
        '다른 기기·서버에서 발생한 작업과 네트워크 청구 전송량',
        '포그라운드 Plate TTS Isolate의 Firestore 읽기·스냅샷 및 계측되지 않은 HTTP 활동',
      ];
}

class FirebaseWriteCommitDelta {
  int sets = 0;
  int updates = 0;
  int deletes = 0;
  String source = 'firestore.transaction';

  int get writes => sets + updates;
  bool get hasOperations => writes > 0 || deletes > 0;

  void stage(String operation, String eventSource) {
    source = eventSource;
    if (operation == 'STAGE_SET') sets++;
    if (operation == 'STAGE_UPDATE') updates++;
    if (operation == 'STAGE_DELETE') deletes++;
  }

  FirebaseWriteCommitDelta copy() {
    final result = FirebaseWriteCommitDelta();
    result.sets = sets;
    result.updates = updates;
    result.deletes = deletes;
    result.source = source;
    return result;
  }
}

class FirebaseActivityMeter {
  FirebaseActivityMeter._();

  static final FirebaseActivityMeter instance = FirebaseActivityMeter._();
  static const int maxEvents = 500;
  static const Object transactionAttemptKey = #firebaseActivityTransactionAttempt;

  final ValueNotifier<FirebaseActivitySummary> summary =
      ValueNotifier<FirebaseActivitySummary>(const FirebaseActivitySummary());
  final List<FirebaseActivityEvent> _events = <FirebaseActivityEvent>[];
  final Map<String, int> _counts = <String, int>{};
  final LinkedHashSet<String> _receivedIds = LinkedHashSet<String>();
  final Map<String, int> _remoteListeners = <String, int>{};
  final String sessionId = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
  late final FirebaseActivityJournal journal = FirebaseActivityJournal(sessionId);
  bool _sessionStarted = false;

  void startSession() {
    if (_sessionStarted) return;
    _sessionStarted = true;
    record(
      service: 'lifecycle',
      operation: 'SESSION_START',
      source: 'main',
    );
  }

  Future<void> initializeJournal() async {
    await journal.initialize();
    for (final previousSession in journal.previousUncleanSessions) {
      record(
        service: 'lifecycle',
        operation: 'PREVIOUS_SESSION_UNCLEAN',
        source: 'firebase_activity_journal',
        detail: 'previousSession=$previousSession',
      );
    }
    for (final previousSession in journal.previousUnknownSessions) {
      record(
        service: 'lifecycle',
        operation: 'PREVIOUS_SESSION_OUTCOME_UNKNOWN',
        source: 'firebase_activity_journal',
        detail: 'previousSession=$previousSession',
      );
    }
  }

  Future<void> flushJournal() => journal.flush();

  Timer? _notifyTimer;
  void Function(FirebaseActivityEvent event)? outbound;
  int _sequence = 0;
  int _active = 0;
  int _uploadBytes = 0;
  int _downloadBytes = 0;
  int _errors = 0;
  int _totalEvents = 0;
  int _resultDocuments = 0;
  int _cacheResults = 0;
  int _serverResults = 0;
  int _committedWrites = 0;
  int _committedDeletes = 0;

  List<FirebaseActivityEvent> get events =>
      List<FirebaseActivityEvent>.unmodifiable(_events.reversed);

  int count(String operation) => _counts[operation] ?? 0;

  String nextOperationId() => '$sessionId:${++_sequence}';

  void record({
    required String service,
    required String operation,
    required String source,
    String result = 'success',
    int elapsedMs = 0,
    int? documents,
    int? bytes,
    bool? fromCache,
    String? detail,
    String? operationId,
    int committedWrites = 0,
    int committedDeletes = 0,
  }) {
    final attempt = Zone.current[transactionAttemptKey];
    if (result == 'staged' && attempt is FirebaseWriteCommitDelta) {
      attempt.stage(operation, source);
    }
    final normalizedSource = source.replaceAll(RegExp(r'[^a-zA-Z0-9_./-]'), '_');
    final event = FirebaseActivityEvent(
      time: DateTime.now(),
      service: service,
      operation: operation,
      source: normalizedSource,
      result: result,
      elapsedMs: elapsedMs,
      eventId: nextOperationId(),
      sessionId: sessionId,
      origin: 'app',
      operationId: operationId,
      documents: documents,
      bytes: bytes,
      fromCache: fromCache,
      detail: detail == null ? null : SecureAuthDiagnostics.redact(detail),
      committedWrites: committedWrites,
      committedDeletes: committedDeletes,
    );
    _append(event, relay: true);
  }

  void acceptRemote(Map<dynamic, dynamic> payload) {
    try {
      final id = (payload['eventId'] ?? '').toString();
      final remoteSession = (payload['sessionId'] ?? '').toString();
      if (id.isEmpty || remoteSession.isEmpty || _receivedIds.contains(id)) return;
      _receivedIds.add(id);
      if (_receivedIds.length > 1600) _receivedIds.remove(_receivedIds.first);
      final event = FirebaseActivityEvent(
        time: DateTime.fromMillisecondsSinceEpoch(
          (payload['timestampMs'] as num?)?.toInt() ?? DateTime.now().millisecondsSinceEpoch,
        ),
        service: (payload['service'] ?? '').toString(),
        operation: (payload['operation'] ?? '').toString(),
        source: (payload['source'] ?? '').toString(),
        result: (payload['result'] ?? '').toString(),
        elapsedMs: (payload['elapsedMs'] as num?)?.toInt() ?? 0,
        eventId: id,
        sessionId: remoteSession,
        origin: 'foreground',
        operationId: payload['operationId']?.toString(),
        documents: (payload['documents'] as num?)?.toInt(),
        bytes: (payload['bytes'] as num?)?.toInt(),
        fromCache: payload['fromCache'] as bool?,
        detail: payload['detail']?.toString(),
        committedWrites: (payload['committedWrites'] as num?)?.toInt() ?? 0,
        committedDeletes: (payload['committedDeletes'] as num?)?.toInt() ?? 0,
      );
      if (event.operation == 'LISTEN_START' && event.result == 'success') {
        _remoteListeners[remoteSession] = (_remoteListeners[remoteSession] ?? 0) + 1;
        _active++;
      } else if (event.operation == 'LISTEN_CANCEL' && event.result == 'success') {
        final count = _remoteListeners[remoteSession] ?? 0;
        if (count > 0) {
          _remoteListeners[remoteSession] = count - 1;
          if (_active > 0) _active--;
        }
      }
      _append(event, relay: false);
    } catch (error) {
      debugPrint('[FIREBASE_ACTIVITY] remote_event_rejected type=${error.runtimeType}');
    }
  }

  void remoteSessionEnded(String remoteSession) {
    final outstanding = _remoteListeners.remove(remoteSession) ?? 0;
    if (outstanding > 0) {
      _active = (_active - outstanding).clamp(0, 1 << 30).toInt();
      record(
        service: 'firestore',
        operation: 'REMOTE_LISTEN_CLEANUP',
        source: 'firebase_activity_bridge',
        detail: 'listeners=$outstanding',
      );
    }
  }

  void _append(FirebaseActivityEvent event, {required bool relay}) {
    _events.add(event);
    journal.append(
      time: event.time,
      eventId: event.eventId,
      eventSessionId: event.sessionId,
      service: event.service,
      operation: event.operation,
      result: event.result,
      line: event.line,
      documents: event.documents,
      bytes: event.bytes,
      fromCache: event.fromCache,
      committedWrites: event.committedWrites,
      committedDeletes: event.committedDeletes,
    );
    if (_events.length > maxEvents) {
      _events.removeRange(0, _events.length - maxEvents);
    }
    _totalEvents++;
    if (event.result == 'success') {
      _counts[event.operation] = (_counts[event.operation] ?? 0) + 1;
      _committedWrites += event.committedWrites;
      _committedDeletes += event.committedDeletes;
      if (event.service == 'firestore' &&
          (event.operation == 'GET' || event.operation == 'QUERY')) {
        _resultDocuments += event.documents ?? 0;
        if (event.fromCache == true) _cacheResults++;
        if (event.fromCache == false) _serverResults++;
      }
      if (event.service == 'storage' && event.bytes != null) {
        if (event.operation == 'UPLOAD') _uploadBytes += event.bytes!;
        if (event.operation == 'DOWNLOAD' || event.operation == 'URL_ACCESS') {
          _downloadBytes += event.bytes!;
        }
      }
    } else if (event.result == 'error') {
      _errors++;
    }
    if (DevAuth.devModeEnabled.value) {
      debugPrint(event.line);
    }
    if (relay) {
      try {
        outbound?.call(event);
      } catch (error) {
        debugPrint('[FIREBASE_ACTIVITY] relay_failed type=${error.runtimeType}');
      }
    }
    _notifyTimer ??= Timer(const Duration(milliseconds: 120), _emit);
  }

  void _emit() {
    _notifyTimer = null;
    const reads = <String>['GET', 'QUERY'];
    const writes = <String>['SET', 'CREATE', 'UPDATE'];
    const storageOperations = <String>[
      'UPLOAD', 'DOWNLOAD', 'STORAGE_DELETE', 'STORAGE_LIST',
      'METADATA', 'URL_ACCESS',
    ];
    int sum(List<String> keys) =>
        keys.fold<int>(0, (value, key) => value + count(key));
    summary.value = FirebaseActivitySummary(
      read: sum(reads),
      write: sum(writes) + _committedWrites,
      delete: count('DELETE') + _committedDeletes,
      snap: count('SNAP'),
      activeListeners: _active,
      storage: sum(storageOperations),
      aggregation: count('AGGREGATION'),
      transaction: count('TRANSACTION'),
      batch: count('BATCH'),
      errors: _errors,
      uploadBytes: _uploadBytes,
      downloadBytes: _downloadBytes,
      eventCount: _totalEvents,
      resultDocuments: _resultDocuments,
      cacheResults: _cacheResults,
      serverResults: _serverResults,
      committedWrites: _committedWrites,
      committedDeletes: _committedDeletes,
    );
  }

  void listenerOpened(String source) {
    _active++;
    record(service: 'firestore', operation: 'LISTEN_START', source: source);
  }

  void listenerClosed(String source) {
    if (_active > 0) _active--;
    record(service: 'firestore', operation: 'LISTEN_CANCEL', source: source);
  }

  void snapshotReceived(Object? value, String source) {
    int? documents;
    bool? cache;
    String? detail;
    if (value is QuerySnapshot) {
      documents = value.docs.length;
      cache = value.metadata.isFromCache;
      detail = 'changes=${value.docChanges.length} pending=${value.metadata.hasPendingWrites}';
    } else if (value is DocumentSnapshot) {
      documents = value.exists ? 1 : 0;
      cache = value.metadata.isFromCache;
      detail = 'pending=${value.metadata.hasPendingWrites}';
    }
    record(
      service: 'firestore',
      operation: 'SNAP',
      source: source,
      documents: documents,
      fromCache: cache,
      detail: detail,
    );
  }

  Future<T> trackFuture<T>(
    Future<T> future, {
    required String service,
    required String operation,
    required String source,
    int? bytes,
  }) {
    final watch = Stopwatch()..start();
    return future.then<T>((value) {
      watch.stop();
      String resolvedOperation = operation;
      int? documents;
      bool? cache;
      int? resolvedBytes = bytes;
      if (service == 'firestore') {
        if (operation == 'GET' && value is QuerySnapshot) {
          resolvedOperation = 'QUERY';
        }
        if (value is QuerySnapshot) {
          documents = value.docs.length;
          cache = value.metadata.isFromCache;
        } else if (value is DocumentSnapshot) {
          documents = value.exists ? 1 : 0;
          cache = value.metadata.isFromCache;
        }
      }
      if (service == 'storage') {
        if (resolvedOperation == 'DOWNLOAD' && value is List<int>) {
          resolvedBytes = value.length;
        } else if (resolvedOperation == 'UPLOAD' && value is TaskSnapshot) {
          resolvedBytes = value.bytesTransferred > 0
              ? value.bytesTransferred
              : resolvedBytes;
        }
      }
      record(
        service: service,
        operation: resolvedOperation,
        source: source,
        elapsedMs: watch.elapsedMilliseconds,
        documents: documents,
        fromCache: cache,
        bytes: resolvedBytes,
      );
      return value;
    }, onError: (Object error, StackTrace stack) {
      watch.stop();
      record(
        service: service,
        operation: operation,
        source: source,
        result: 'error',
        elapsedMs: watch.elapsedMilliseconds,
        detail: error.runtimeType.toString(),
      );
      Error.throwWithStackTrace(error, stack);
    });
  }

  Stream<T> observeSnapshots<T>(Stream<T> stream, String source) {
    StreamSubscription<T>? subscription;
    bool open = false;
    late final StreamController<T> controller;
    void stop() {
      if (!open) return;
      open = false;
      listenerClosed(source);
    }
    void start() {
      if (open) return;
      open = true;
      listenerOpened(source);
      subscription = stream.listen(
        (event) {
          snapshotReceived(event, source);
          controller.add(event);
        },
        onError: (Object error, StackTrace stack) {
          record(
            service: 'firestore',
            operation: 'SNAP',
            source: source,
            result: 'error',
            detail: error.runtimeType.toString(),
          );
          controller.addError(error, stack);
        },
        onDone: () {
          stop();
          controller.close();
        },
      );
    }
    if (stream.isBroadcast) {
      controller = StreamController<T>.broadcast(
        sync: true,
        onListen: start,
        onCancel: () {
          stop();
          final sub = subscription;
          if (sub != null) unawaited(sub.cancel());
        },
      );
    } else {
      controller = StreamController<T>(
        sync: true,
        onListen: start,
        onPause: () => subscription?.pause(),
        onResume: () => subscription?.resume(),
        onCancel: () async {
          stop();
          await subscription?.cancel();
        },
      );
    }
    return controller.stream;
  }

  FirebaseCostSummary get costSummary => FirebaseCostSummary(summary.value);

  FirebaseCostSummary costFromJournal(FirebaseActivityJournalCost report) {
    return FirebaseCostSummary(
      FirebaseActivitySummary(
        read: report.read,
        write: report.write,
        delete: report.delete,
        snap: report.snap,
        storage: report.storage,
        aggregation: report.aggregation,
        transaction: report.transaction,
        batch: report.batch,
        errors: report.errors,
        uploadBytes: report.uploadBytes,
        downloadBytes: report.downloadBytes,
        eventCount: report.totalEvents,
        resultDocuments: report.resultDocuments,
        cacheResults: report.cacheResults,
        serverResults: report.serverResults,
        committedWrites: report.committedWrites,
        committedDeletes: report.committedDeletes,
      ),
      archived: true,
      listenStarts: report.listenStarts,
      listenCancels: report.listenCancels,
    );
  }

  String exportJournalCostCode(FirebaseActivityJournalCost report, {
    String? requestedSessionId,
    DateTime? since,
    bool allSessions = false,
  }) {
    final cost = costFromJournal(report);
    final lines = <String>[
      '[FIREBASE_COST] scope=${allSessions ? 'all' : requestedSessionId ?? sessionId} since=${since?.toIso8601String() ?? 'all'} sessions=${report.sessionCount} records=${report.totalEvents}',
      '[FIREBASE_COST] OBSERVED',
      ...cost.observed.map((line) => '[FIREBASE_COST] $line'),
      '[FIREBASE_COST] ESTIMATED',
      ...cost.estimated.map((line) => '[FIREBASE_COST] $line'),
      '[FIREBASE_COST] UNAVAILABLE',
      ...cost.unavailable.map((line) => '[FIREBASE_COST] $line'),
      '[FIREBASE_COST] complete=${!report.incomplete} legacyEvents=${report.legacyEvents} droppedEvents=${report.droppedEvents} droppedFiles=${report.droppedFiles} writeErrors=${report.writeErrors} available=${report.available}',
      if (report.incomplete)
        '[FIREBASE_COST] 과거 스키마·보관 삭제·기록 오류·비활성 저장소 등으로 일부 통계가 누락될 수 있습니다. 표시 수치는 보관된 계측 데이터만의 합계입니다.',
    ];
    return lines
        .map((line) => 'debugPrint(${jsonEncode(SecureAuthDiagnostics.redact(line))});')
        .join('\n');
  }

  Future<List<String>> journalSessions() => journal.sessions();

  Future<String> exportJournalCode({
    String? service,
    String? requestedSessionId,
    DateTime? since,
    bool allSessions = false,
  }) async {
    if (service == 'cost') {
      final report = await journal.readCost(
        requestedSessionId: requestedSessionId,
        since: since,
        allSessions: allSessions,
      );
      return exportJournalCostCode(
        report,
        requestedSessionId: requestedSessionId,
        since: since,
        allSessions: allSessions,
      );
    }
    final archive = await journal.readArchive(
      requestedSessionId: requestedSessionId,
      service: service,
      since: since,
      allSessions: allSessions,
    );
    final output = <String>[
      '[FIREBASE_JOURNAL] session=${allSessions ? 'all' : requestedSessionId ?? sessionId} records=${archive.totalLines} sessions=${archive.sessionCount} available=${archive.available}',
      '[FIREBASE_JOURNAL] retainedDays=${FirebaseActivityJournal.retention.inDays} maxBytes=${FirebaseActivityJournal.maxStorageBytes} droppedEvents=${archive.droppedEvents} droppedFiles=${archive.droppedFiles} writeErrors=${archive.writeErrors} pending=${journal.pendingEvents}',
    ];
    if (archive.lines.isNotEmpty) {
      output.addAll(archive.lines);
    } else if ((requestedSessionId == null || requestedSessionId == sessionId) &&
        !allSessions && since == null && !archive.available) {
      output.add('[FIREBASE_JOURNAL] 파일 기록 불가: 메모리의 최근 이벤트로 대체합니다.');
      output.addAll(_events.where((event) =>
          service == null || service == 'all' || event.service == service ||
          (service == 'realtime' &&
              (event.operation.startsWith('LISTEN') || event.operation == 'SNAP')))
          .map((event) => event.line));
    } else if (archive.lines.isEmpty) {
      output.add('[FIREBASE_JOURNAL] 선택한 범위에 기록이 없습니다.');
    }
    return output
        .map((line) => 'debugPrint(${jsonEncode(SecureAuthDiagnostics.redact(line))});')
        .join('\n');
  }

  String exportCode({String? service}) {
    if (service == 'cost') {
      final cost = costSummary;
      final lines = <String>[
        '[FIREBASE_COST] OBSERVED',
        ...cost.observed.map((value) => '[FIREBASE_COST] $value'),
        '[FIREBASE_COST] ESTIMATED',
        ...cost.estimated.map((value) => '[FIREBASE_COST] $value'),
        '[FIREBASE_COST] UNAVAILABLE',
        ...cost.unavailable.map((value) => '[FIREBASE_COST] $value'),
      ];
      return lines.map((line) => 'debugPrint(${jsonEncode(line)});').join('\n');
    }
    final selected = _events.where((event) =>
        service == null || service == 'all' || event.service == service ||
        (service == 'realtime' &&
            (event.operation.startsWith('LISTEN') || event.operation == 'SNAP')));
    final lines = selected.map((event) =>
        'debugPrint(${jsonEncode(event.line)});').toList(growable: false);
    if (lines.isEmpty) {
      return 'debugPrint(${jsonEncode('[FIREBASE_ACTIVITY] 기록이 없습니다.')});';
    }
    return lines.join('\n');
  }
}

class FirebaseActivityWriteBatch {
  FirebaseActivityWriteBatch(this._delegate, this._source);

  final WriteBatch _delegate;
  final String _source;
  int _writes = 0;
  int _deletes = 0;
  bool _committed = false;

  void set<T>(DocumentReference<T> document, T data, [SetOptions? options]) {
    _delegate.set<T>(document, data, options);
    _writes++;
  }

  void update(DocumentReference<Object?> document, Map<Object, Object?> data) {
    _delegate.update(document, data);
    _writes++;
  }

  void delete(DocumentReference<Object?> document) {
    _delegate.delete(document);
    _deletes++;
  }

  Future<void> commit() async {
    await _delegate.commit();
    if (_committed) return;
    _committed = true;
    FirebaseActivityMeter.instance.record(
      service: 'firestore',
      operation: 'COMMITTED_BATCH',
      source: _source,
      committedWrites: _writes,
      committedDeletes: _deletes,
      detail: 'writes=$_writes deletes=$_deletes',
    );
  }
}

extension FirebaseActivityFirestoreTransaction on FirebaseFirestore {
  Future<T> runTrackedActivityTransaction<T>(
    Future<T> Function(Transaction transaction) transactionHandler, {
    Duration timeout = const Duration(seconds: 30),
    int maxAttempts = 5,
  }) async {
    final meter = FirebaseActivityMeter.instance;
    final operationId = meter.nextOperationId();
    FirebaseWriteCommitDelta? successfulAttempt;
    final result = await runTransaction<T>(
      (transaction) {
        final attempt = FirebaseWriteCommitDelta();
        return runZoned<Future<T>>(
          () async {
            final value = await transactionHandler(transaction);
            successfulAttempt = attempt.copy();
            return value;
          },
          zoneValues: <Object, Object>{
            FirebaseActivityMeter.transactionAttemptKey: attempt,
          },
        );
      },
      timeout: timeout,
      maxAttempts: maxAttempts,
    );
    final delta = successfulAttempt;
    if (delta != null && delta.hasOperations) {
      meter.record(
        service: 'firestore',
        operation: 'COMMITTED_TRANSACTION',
        source: delta.source,
        operationId: operationId,
        committedWrites: delta.writes,
        committedDeletes: delta.deletes,
        detail: 'sets=${delta.sets} updates=${delta.updates} deletes=${delta.deletes}',
      );
    }
    return result;
  }

  FirebaseActivityWriteBatch trackedActivityBatch(String source) =>
      FirebaseActivityWriteBatch(batch(), source);
}

extension FirebaseActivityFutureTracking<T> on Future<T> {
  Future<T> trackFirestore(String operation, String source) {
    return FirebaseActivityMeter.instance.trackFuture<T>(
      this,
      service: 'firestore',
      operation: operation,
      source: source,
    );
  }

  Future<T> trackStorage(String operation, String source, {int? bytes}) {
    return FirebaseActivityMeter.instance.trackFuture<T>(
      this,
      service: 'storage',
      operation: operation,
      source: source,
      bytes: bytes,
    );
  }
}

extension FirebaseActivityStreamTracking<T> on Stream<T> {
  Stream<T> trackFirestoreSnapshots(String source) {
    return FirebaseActivityMeter.instance.observeSnapshots<T>(this, source);
  }
}
