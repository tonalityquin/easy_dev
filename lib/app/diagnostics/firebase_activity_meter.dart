import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';

import '../../features/selector/application/dev_auth.dart';
import '../utils/secure_auth_diagnostics.dart';
import 'firebase_activity_journal.dart';
import 'firebase_auth_rules_diagnostics.dart';
import 'firestore_rules_audit.dart';

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
    this.requestId,
    this.actionId,
    this.actionKind,
    this.plateRef,
    this.readPurpose,
    this.parentOperationId,
    this.collection,
    this.pathTemplate,
    this.firebaseCode,
    this.responseSource,
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
  final String? requestId;
  final String? actionId;
  final String? actionKind;
  final String? plateRef;
  final String? readPurpose;
  final String? parentOperationId;
  final String? collection;
  final String? pathTemplate;
  final String? firebaseCode;
  final String? responseSource;
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
      if (requestId != null) 'requestId=$requestId',
      if (actionId != null) 'actionId=$actionId',
      if (actionKind != null) 'actionKind=$actionKind',
      if (plateRef != null) 'plateRef=$plateRef',
      if (readPurpose != null) 'readPurpose=$readPurpose',
      if (parentOperationId != null) 'parentOperationId=$parentOperationId',
      if (collection != null) 'collection=$collection',
      if (pathTemplate != null) 'pathTemplate=$pathTemplate',
      if (firebaseCode != null) 'firebaseCode=$firebaseCode',
      if (responseSource != null) 'responseSource=$responseSource',
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
  bool tracksOperations = false;
  final List<FirestoreRulesWriteTarget> targets = <FirestoreRulesWriteTarget>[];
  final List<FirestoreRulesWriteTarget> readTargets = <FirestoreRulesWriteTarget>[];
  final Map<String, bool> knownExistence = <String, bool>{};
  final Map<String, Map<String, dynamic>> knownBefore =
      <String, Map<String, dynamic>>{};
  final Set<String> pathsWithWrites = <String>{};

  int get writes => sets + updates;
  bool get hasOperations => writes > 0 || deletes > 0;

  void stage(String operation, String eventSource) {
    source = eventSource;
    if (tracksOperations) return;
    if (operation == 'STAGE_SET') sets++;
    if (operation == 'STAGE_UPDATE') updates++;
    if (operation == 'STAGE_DELETE') deletes++;
  }

  void trackDocument(String operation, String path, {
    Object? data,
    bool merge = false,
    bool mergeNestedMaps = false,
    bool exactDiffAllowed = true,
  }) {
    if (operation == 'SET') sets++;
    if (operation == 'UPDATE') updates++;
    if (operation == 'DELETE') deletes++;
    final exists = knownExistence[path];
    final exactKeys = exists == true && exactDiffAllowed &&
            !pathsWithWrites.contains(path) && operation != 'DELETE'
        ? FirestoreRulesAudit.affectedKeysFromKnownState(
            before: knownBefore[path],
            payload: data,
            merge: merge || operation == 'UPDATE',
            mergeNestedMaps: merge && mergeNestedMaps,
          )
        : null;
    final safeKeys = operation == 'UPDATE' || (operation == 'SET' && merge)
        ? FirestoreRulesAudit.safeProjectionKeys(data)
        : null;
    pathsWithWrites.add(path);
    targets.add(FirestoreRulesWriteTarget(
      operation: operation,
      collection: FirestoreRulesAudit.collectionFor(path),
      pathTemplate: FirestoreRulesAudit.pathTemplateFor(path),
      documentExists: exists,
      documentEvidence: exists == null ? 'UNKNOWN' : 'TRANSACTION_GET',
      changedKeys: exactKeys ?? safeKeys,
      fieldEvidence: exactKeys != null ? 'KNOWN_BEFORE_AFTER'
          : safeKeys != null ? 'WRITE_SCOPE' : 'UNKNOWN',
    ));
  }

  FirebaseWriteCommitDelta copy() {
    final result = FirebaseWriteCommitDelta();
    result.sets = sets;
    result.updates = updates;
    result.deletes = deletes;
    result.source = source;
    result.tracksOperations = tracksOperations;
    result.targets.addAll(targets);
    result.readTargets.addAll(readTargets);
    result.knownExistence.addAll(knownExistence);
    result.knownBefore.addAll(knownBefore);
    result.pathsWithWrites.addAll(pathsWithWrites);
    return result;
  }
}

class _TrackedFirestoreTransaction implements Transaction {
  _TrackedFirestoreTransaction(this._delegate, this._attempt);

  final Transaction _delegate;
  final FirebaseWriteCommitDelta _attempt;

  @override
  Future<DocumentSnapshot<T>> get<T extends Object?>(
    DocumentReference<T> documentReference,
  ) async {
    final snapshot = await _delegate.get<T>(documentReference);
    _attempt.readTargets.add(FirestoreRulesWriteTarget(
      operation: 'GET',
      collection: FirestoreRulesAudit.collectionFor(documentReference.path),
      pathTemplate: FirestoreRulesAudit.pathTemplateFor(documentReference.path),
      documentExists: snapshot.exists,
      documentEvidence: 'TRANSACTION_GET',
    ));
    _attempt.knownExistence[documentReference.path] = snapshot.exists;
    final data = snapshot.data();
    if (snapshot.exists && data is Map<String, dynamic>) {
      _attempt.knownBefore[documentReference.path] = data;
    }
    return snapshot;
  }

  @override
  Transaction set<T>(DocumentReference<T> documentReference, T data,
      [SetOptions? options]) {
    _delegate.set<T>(documentReference, data, options);
    _attempt.trackDocument(
      'SET', documentReference.path,
      data: data,
      merge: options?.merge == true || options?.mergeFields != null,
      mergeNestedMaps: options?.merge == true,
      exactDiffAllowed: options?.mergeFields == null,
    );
    return this;
  }

  @override
  Transaction update(DocumentReference<Object?> documentReference,
      Map<Object, Object?> data) {
    final dynamic delegate = _delegate;
    delegate.update(documentReference, data);
    _attempt.trackDocument('UPDATE', documentReference.path, data: data);
    return this;
  }

  @override
  Transaction delete(DocumentReference<Object?> documentReference) {
    _delegate.delete(documentReference);
    _attempt.trackDocument('DELETE', documentReference.path);
    return this;
  }
}

@immutable
class FirebaseActionTrace {
  const FirebaseActionTrace({
    required this.id,
    required this.kind,
    this.plateRef,
    this.parentId,
  });

  final String id;
  final String kind;
  final String? plateRef;
  final String? parentId;
}

class FirebaseActivityMeter {
  FirebaseActivityMeter._();

  static final FirebaseActivityMeter instance = FirebaseActivityMeter._();
  static const int maxEvents = 500;
  static const Object transactionAttemptKey = #firebaseActivityTransactionAttempt;
  static const Object actionTraceKey = #firebaseActionTrace;

  FirebaseActionTrace? get currentActionTrace =>
      Zone.current[actionTraceKey] as FirebaseActionTrace?;

  String? get currentActionId => currentActionTrace?.id;

  final Map<String, String> _plateAliases = <String, String>{};
  final Map<String, int> _viewFailuresByAction = <String, int>{};
  final Map<String, int> _resultFailuresByAction = <String, int>{};

  String plateRefFor(String plateId) {
    final normalized = plateId.trim();
    if (normalized.isEmpty) return 'P-unknown';
    return _plateAliases.putIfAbsent(
      normalized,
      () => 'P-${_plateAliases.length + 1}',
    );
  }

  Future<T> traceAction<T>({
    required String kind,
    required String source,
    required Future<T> Function() action,
    String? plateId,
    String? detail,
    bool Function(T result)? isFailureResult,
  }) {
    final parent = currentActionTrace;
    if (parent != null) {
      record(
        service: 'workflow',
        operation: 'ACTION_NESTED',
        source: source,
        detail: 'kind=$kind${detail == null ? '' : ' $detail'}',
      );
      if (isFailureResult == null) return action();
      return action().then((result) {
        if (isFailureResult(result)) {
          _resultFailuresByAction[parent.id] =
              (_resultFailuresByAction[parent.id] ?? 0) + 1;
          record(
            service: 'workflow',
            operation: 'ACTION_NESTED_RESULT_FAILED',
            source: source,
            result: 'error',
            detail: 'kind=$kind',
          );
        }
        return result;
      });
    }
    final trace = FirebaseActionTrace(
      id: nextOperationId(),
      kind: kind,
      plateRef: plateId == null ? null : plateRefFor(plateId),
    );
    return runZoned<Future<T>>(() async {
      final watch = Stopwatch()..start();
      record(
        service: 'workflow',
        operation: 'ACTION_START',
        source: source,
        detail: detail,
      );
      try {
        final result = await action();
        watch.stop();
        final viewFailures = _viewFailuresByAction.remove(trace.id) ?? 0;
        final resultFailures = _resultFailuresByAction.remove(trace.id) ?? 0;
        final failed = isFailureResult?.call(result) ?? false;
        record(
          service: 'workflow',
          operation: failed
              ? 'ACTION_FAILED'
              : result is bool && result == false
                  ? 'ACTION_BLOCKED'
                  : viewFailures == 0 && resultFailures == 0
                      ? 'ACTION_COMPLETE'
                      : 'ACTION_PARTIAL',
          source: source,
          result: failed ? 'error' : 'success',
          elapsedMs: watch.elapsedMilliseconds,
          detail: 'viewFailures=$viewFailures resultFailures=$resultFailures',
        );
        return result;
      } catch (error) {
        watch.stop();
        final viewFailures = _viewFailuresByAction.remove(trace.id) ?? 0;
        final resultFailures = _resultFailuresByAction.remove(trace.id) ?? 0;
        record(
          service: 'workflow',
          operation: 'ACTION_FAILED',
          source: source,
          result: 'error',
          elapsedMs: watch.elapsedMilliseconds,
          detail: 'errorType=${error.runtimeType} viewFailures=$viewFailures resultFailures=$resultFailures',
        );
        rethrow;
      }
    }, zoneValues: <Object, Object>{actionTraceKey: trace});
  }

  void traceStep(String operation, {
    required String source,
    String? detail,
    String result = 'success',
  }) {
    final actionId = currentActionId;
    if (operation == 'VIEW_WRITE_FAILED' && actionId != null) {
      _viewFailuresByAction[actionId] =
          (_viewFailuresByAction[actionId] ?? 0) + 1;
    }
    record(
      service: 'workflow',
      operation: operation,
      source: source,
      detail: detail,
      result: result,
    );
  }


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
    String? requestId,
    String? collection,
    String? pathTemplate,
    String? firebaseCode,
    String? responseSource,
    String? readPurpose,
    String? parentOperationId,
    int committedWrites = 0,
    int committedDeletes = 0,
  }) {
    final attempt = Zone.current[transactionAttemptKey];
    if (result == 'staged' && attempt is FirebaseWriteCommitDelta) {
      attempt.stage(operation, source);
    }
    final trace = currentActionTrace;
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
      requestId: requestId,
      actionId: trace?.id,
      actionKind: trace?.kind,
      plateRef: trace?.plateRef,
      readPurpose: readPurpose ??
          (service == 'firestore' && (operation == 'GET' || operation == 'QUERY')
              ? 'UNCLASSIFIED_CALL_SITE'
              : null),
      parentOperationId: parentOperationId ??
          (service == 'firestore' && requestId != null ? trace?.id : trace?.parentId),
      collection: collection,
      pathTemplate: pathTemplate,
      firebaseCode: firebaseCode,
      responseSource: responseSource,
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
        requestId: payload['requestId']?.toString(),
        actionId: payload['actionId']?.toString(),
        actionKind: payload['actionKind']?.toString(),
        plateRef: payload['plateRef']?.toString(),
        readPurpose: payload['readPurpose']?.toString(),
        parentOperationId: payload['parentOperationId']?.toString(),
        collection: payload['collection']?.toString(),
        pathTemplate: payload['pathTemplate']?.toString(),
        firebaseCode: payload['firebaseCode']?.toString(),
        responseSource: payload['responseSource']?.toString(),
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
      requestId: event.requestId,
      actionId: event.actionId,
      actionKind: event.actionKind,
      plateRef: event.plateRef,
      readPurpose: event.readPurpose,
      parentOperationId: event.parentOperationId,
      collection: event.collection,
      pathTemplate: event.pathTemplate,
      firebaseCode: event.firebaseCode,
      responseSource: event.responseSource,
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
      transaction: count('TRANSACTION') + count('COMMITTED_TRANSACTION'),
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

  void listenerOpened(String source, {
    String? requestId,
    String? collection,
    String? pathTemplate,
  }) {
    _active++;
    record(
      service: 'firestore', operation: 'LISTEN_START', source: source,
      requestId: requestId, collection: collection, pathTemplate: pathTemplate,
      readPurpose: 'REALTIME_LISTENER',
    );
  }

  void listenerClosed(String source, {
    String? requestId,
    String? collection,
    String? pathTemplate,
  }) {
    if (_active > 0) _active--;
    record(
      service: 'firestore', operation: 'LISTEN_CANCEL', source: source,
      requestId: requestId, collection: collection, pathTemplate: pathTemplate,
      readPurpose: 'REALTIME_LISTENER',
    );
  }

  void snapshotReceived(Object? value, String source, {
    String? requestId,
    String? collection,
    String? pathTemplate,
    FirebaseAuthRulesSnapshot? authAtEvent,
    bool sessionChanged = false,
    String? authEvidence,
    String? authContext,
  }) {
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
      requestId: requestId,
      readPurpose: 'REALTIME_LISTENER',
      collection: collection,
      pathTemplate: pathTemplate,
      responseSource: cache == null ? 'unknown' : cache ? 'cache' : 'server',
    );
    if (requestId != null) {
      recordRulesAudit(
        requestId: requestId,
        collection: collection,
        operation: value is QuerySnapshot
            ? 'QUERY'
            : value is DocumentSnapshot ? 'GET' : 'SNAP',
        source: source,
        pathTemplate: pathTemplate,
        success: true,
        fromCache: cache,
        authOverride: authAtEvent,
        sessionChanged: sessionChanged,
        authEvidence: authEvidence,
        authContext: authContext,
      );
    }
  }

  Future<T> trackFuture<T>(
    Future<T> future, {
    required String service,
    required String operation,
    required String source,
    int? bytes,
    String? collection,
    String? pathTemplate,
    Set<String>? changedKeys,
    String? readPurpose,
    FirebaseAuthRulesSnapshot? authOverride,
    bool useCapturedAuth = false,
  }) {
    final watch = Stopwatch()..start();
    final requestId = service == 'firestore' ? nextOperationId() : null;
    final authAtStart = useCapturedAuth
        ? authOverride
        : service == 'firestore'
            ? FirebaseAuthRulesDiagnostics.captureForRequest()
            : null;
    return future.then<T>((value) {
      watch.stop();
      String resolvedOperation = operation;
      int? documents;
      bool? cache;
      int? resolvedBytes = bytes;
      String? resolvedCollection = collection;
      String? resolvedPathTemplate = pathTemplate;
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
          final segments = value.reference.path.split('/');
          if (segments.length.isEven && segments.length >= 2) {
            resolvedCollection ??= segments.first;
            resolvedPathTemplate ??= List<String>.generate(
              segments.length,
              (index) => index.isEven ? segments[index] : '*',
            ).join('/');
          }
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
        requestId: requestId,
        readPurpose: readPurpose,
        collection: resolvedCollection,
        pathTemplate: resolvedPathTemplate,
        responseSource: service == 'firestore'
            ? (cache == true ? 'cache' : cache == false ? 'server'
                : <String>{'SET', 'CREATE', 'UPDATE', 'DELETE', 'BATCH', 'TRANSACTION'}.contains(resolvedOperation)
                    ? 'sdk_acknowledged' : 'unknown')
            : null,
      );
      if (service == 'firestore' && requestId != null) {
        recordRulesAudit(
          requestId: requestId,
          collection: resolvedCollection,
          operation: resolvedOperation,
          source: source,
          pathTemplate: resolvedPathTemplate,
          changedKeys: changedKeys,
          success: true,
          fromCache: cache,
          authOverride: authAtStart,
          sessionChanged: (authAtStart != null && !FirebaseAuthRulesDiagnostics.isSameSession(authAtStart)),
        );
      }
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
        requestId: requestId,
        readPurpose: readPurpose,
        collection: collection,
        pathTemplate: pathTemplate,
        firebaseCode: error is FirebaseException ? error.code : null,
        responseSource: 'unknown',
      );
      if (service == 'firestore' && requestId != null) {
        recordRulesAudit(
          requestId: requestId,
          collection: collection,
          operation: operation,
          source: source,
          pathTemplate: pathTemplate,
          changedKeys: changedKeys,
          success: false,
          firebaseCode: error is FirebaseException ? error.code : null,
          authOverride: authAtStart,
          sessionChanged: (authAtStart != null && !FirebaseAuthRulesDiagnostics.isSameSession(authAtStart)),
        );
      }
      Error.throwWithStackTrace(error, stack);
    });
  }

  void recordRulesAudit({
    required String requestId,
    required String? collection,
    required String operation,
    required String source,
    required bool success,
    String? firebaseCode,
    bool? fromCache,
    String? pathTemplate,
    Set<String>? changedKeys,
    bool? documentExists,
    FirebaseAuthRulesSnapshot? authOverride,
    bool sessionChanged = false,
    String? authEvidence,
    String? authContext,
    bool requestSent = true,
    String? expectedOverride,
  }) {
    if (!DevAuth.devModeEnabled.value) return;
    final audit = FirestoreRulesAudit.compare(
      collection: collection,
      operation: operation,
      success: success,
      firebaseCode: firebaseCode,
      fromCache: fromCache,
      pathTemplate: pathTemplate,
      changedKeys: changedKeys,
      documentExists: documentExists,
      authOverride: authOverride,
      requireCapturedAuth: true,
      sessionChanged: sessionChanged,
      authEvidence: authEvidence,
      requestSent: requestSent,
      expectedOverride: expectedOverride,
    );
    record(
      service: 'security',
      operation: 'RULES_COMPARE',
      source: source,
      result: 'audit',
      requestId: requestId,
      collection: collection,
      pathTemplate: pathTemplate,
      firebaseCode: firebaseCode,
      detail: 'firestoreOperation=$operation ${audit.detail}'
          '${authContext == null ? '' : ' $authContext'}',
    );
  }

  void recordWriteTargets({
    required String requestId,
    required String source,
    required List<FirestoreRulesWriteTarget> targets,
    required FirebaseAuthRulesSnapshot? authOverride,
    required String kind,
  }) {
    if (!DevAuth.devModeEnabled.value) return;
    for (var index = 0; index < targets.length; index++) {
      final target = targets[index];
      final expected = target.documentEvidence == 'PREEXISTING_SNAPSHOT' &&
              target.collection == 'user_accounts_show' &&
              target.operation == 'SET'
          ? 'UNKNOWN'
          : FirestoreRulesAudit.expected(
        collection: target.collection,
        operation: target.operation,
        pathTemplate: target.pathTemplate,
        changedKeys: target.changedKeys,
        documentExists: target.documentExists,
        authOverride: authOverride,
        requireCapturedAuth: true,
      );
      record(
        service: 'security',
        operation: 'RULES_ITEM',
        source: source,
        result: 'audit',
        requestId: requestId,
        collection: target.collection,
        pathTemplate: target.pathTemplate,
        detail: 'kind=$kind item=${index + 1} '
            'firestoreOperation=${target.operation} '
            'documentExists=${target.documentExists ?? 'unknown'} '
            'changedKeysKnown=${target.changedKeys != null} '
            'fieldEvidence=${target.fieldEvidence} '
            'documentEvidence=${target.documentEvidence} '
            'expected=$expected verification=POLICY_CANDIDATE',
      );
    }
  }

  Future<T> runFirestore<T>({
    required String operation,
    required String source,
    required String collection,
    required Future<T> Function() action,
    String? pathTemplate,
    Set<String>? changedKeys,
  }) {
    final authAtStart = FirebaseAuthRulesDiagnostics.captureForRequest();
    try {
      return trackFuture<T>(
        action(),
        service: 'firestore',
        operation: operation,
        source: source,
        collection: collection,
        pathTemplate: pathTemplate,
        changedKeys: changedKeys,
        authOverride: authAtStart,
        useCapturedAuth: true,
      );
    } catch (error, stack) {
      final requestId = nextOperationId();
      record(
        service: 'firestore',
        operation: operation,
        source: source,
        result: 'error',
        requestId: requestId,
        collection: collection,
        pathTemplate: pathTemplate,
        firebaseCode: error is FirebaseException ? error.code : null,
        detail: error.runtimeType.toString(),
      );
      recordRulesAudit(
        requestId: requestId,
        collection: collection,
        operation: operation,
        source: source,
        success: false,
        firebaseCode: error is FirebaseException ? error.code : null,
        pathTemplate: pathTemplate,
        changedKeys: changedKeys,
        authOverride: authAtStart,
        sessionChanged: (authAtStart != null && !FirebaseAuthRulesDiagnostics.isSameSession(authAtStart)),
        requestSent: false,
      );
      return Future<T>.error(error, stack);
    }
  }

  String get rulesAuditSummary {
    final selected = _events.where((event) =>
        event.service == 'security' && event.operation == 'RULES_COMPARE');
    var consistent = 0;
    var mismatched = 0;
    var unverified = 0;
    for (final event in selected) {
      final detail = event.detail ?? '';
      if (detail.contains('comparison=CONSISTENT')) {
        consistent++;
      } else if (detail.contains('comparison=UNEXPECTED_')) {
        mismatched++;
      } else {
        unverified++;
      }
    }
    return 'Rules 관측(최근 메모리): 일치 $consistent · 불일치 $mismatched · 확인 불가 $unverified';
  }

  Stream<T> observeSnapshots<T>(
    Stream<T> stream,
    String source, {
    String? collection,
    String? pathTemplate,
    String? operation,
  }) {
    final requestId = nextOperationId();
    StreamSubscription<T>? subscription;
    FirebaseAuthSessionIdentity? listenerIdentity;
    String? observedOperation = operation;
    bool open = false;
    late final StreamController<T> controller;
    String sessionEvidence(FirebaseAuthSessionIdentity current) {
      final started = listenerIdentity;
      if (started == null) return 'AUTH_AT_START_UNAVAILABLE';
      return FirebaseAuthRulesDiagnostics.sessionEvidence(started, current);
    }
    String sessionContext(
      FirebaseAuthSessionIdentity current,
      String evidence,
    ) {
      return 'authStartUidPresent=${listenerIdentity?.uid != null} '
          'authCurrentUidPresent=${current.uid != null} '
          'authSessionMatches=${evidence == 'MATCH'}';
    }
    FirebaseAuthRulesSnapshot? authForEvent(
      FirebaseAuthSessionIdentity current,
      String evidence,
    ) {
      if (evidence != 'MATCH' || current.uid == null) return null;
      final checked = FirebaseAuthRulesDiagnostics.captureForRequest();
      if (checked == null || checked.sessionUid != current.uid ||
          checked.sessionGeneration != current.generation) return null;
      return checked;
    }
    void stop() {
      if (!open) return;
      open = false;
      listenerClosed(
        source, requestId: requestId,
        collection: collection, pathTemplate: pathTemplate,
      );
    }
    void start() {
      if (open) return;
      open = true;
      observedOperation = operation;
      listenerIdentity = FirebaseAuthRulesDiagnostics.captureSessionIdentity();
      listenerOpened(
        source, requestId: requestId,
        collection: collection, pathTemplate: pathTemplate,
      );
      subscription = stream.listen(
        (event) {
          if (event is QuerySnapshot) {
            observedOperation = 'QUERY';
          } else if (event is DocumentSnapshot) {
            observedOperation = 'GET';
          }
          final currentIdentity =
              FirebaseAuthRulesDiagnostics.captureSessionIdentity();
          final evidence = sessionEvidence(currentIdentity);
          snapshotReceived(
            event, source,
            requestId: requestId,
            collection: collection,
            pathTemplate: pathTemplate,
            authAtEvent: authForEvent(currentIdentity, evidence),
            authEvidence: evidence == 'MATCH' ? null : evidence,
            authContext: sessionContext(currentIdentity, evidence),
          );
          controller.add(event);
        },
        onError: (Object error, StackTrace stack) {
          final currentIdentity =
              FirebaseAuthRulesDiagnostics.captureSessionIdentity();
          final evidence = sessionEvidence(currentIdentity);
          record(
            service: 'firestore',
            operation: 'SNAP',
            source: source,
            result: 'error',
            detail: error.runtimeType.toString(),
            requestId: requestId,
            collection: collection,
            pathTemplate: pathTemplate,
            firebaseCode: error is FirebaseException ? error.code : null,
          );
          recordRulesAudit(
            requestId: requestId,
            collection: collection,
            operation: observedOperation ?? 'SNAP',
            source: source,
            pathTemplate: pathTemplate,
            success: false,
            firebaseCode: error is FirebaseException ? error.code : null,
            authOverride: authForEvent(currentIdentity, evidence),
            authEvidence: evidence == 'MATCH' ? null : evidence,
            authContext: sessionContext(currentIdentity, evidence),
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
  final List<FirestoreRulesWriteTarget> _targets = <FirestoreRulesWriteTarget>[];
  int _writes = 0;
  int _deletes = 0;
  bool _committed = false;
  final Map<String, bool> _knownExistence = <String, bool>{};
  final Map<String, Map<String, dynamic>> _knownBefore =
      <String, Map<String, dynamic>>{};

  void observeDocument<T>(DocumentSnapshot<T> snapshot) {
    _knownExistence[snapshot.reference.path] = snapshot.exists;
    final data = snapshot.data();
    if (snapshot.exists && data is Map<String, dynamic>) {
      _knownBefore[snapshot.reference.path] = data;
    }
  }

  void set<T>(DocumentReference<T> document, T data, [SetOptions? options]) {
    _delegate.set<T>(document, data, options);
    _writes++;
    _targets.add(FirestoreRulesWriteTarget(
      operation: 'SET',
      collection: FirestoreRulesAudit.collectionFor(document.path),
      pathTemplate: FirestoreRulesAudit.pathTemplateFor(document.path),
      documentExists: _knownExistence[document.path],
      documentEvidence: _knownExistence.containsKey(document.path)
          ? 'PREEXISTING_SNAPSHOT' : 'UNKNOWN',
      changedKeys: _knownExistence[document.path] == true &&
              options?.mergeFields == null
          ? FirestoreRulesAudit.affectedKeysFromKnownState(
                  before: _knownBefore[document.path],
                  payload: data,
                  merge: options?.merge == true || options?.mergeFields != null,
                  mergeNestedMaps: options?.merge == true,
                ) ?? ((options?.merge == true || options?.mergeFields != null)
                    ? FirestoreRulesAudit.safeProjectionKeys(data) : null)
          : (options?.merge == true || options?.mergeFields != null)
              ? FirestoreRulesAudit.safeProjectionKeys(data)
              : null,
      fieldEvidence: _knownExistence[document.path] == true &&
              options?.mergeFields == null &&
              FirestoreRulesAudit.affectedKeysFromKnownState(
                before: _knownBefore[document.path],
                payload: data,
                merge: options?.merge == true || options?.mergeFields != null,
                mergeNestedMaps: options?.merge == true,
              ) != null
          ? 'PRIOR_SNAPSHOT_DIFF'
          : options?.merge == true || options?.mergeFields != null
              ? 'WRITE_SCOPE' : 'UNKNOWN',
    ));
  }

  void update(DocumentReference<Object?> document, Map<String, dynamic> data) {
    _delegate.update(document, data);
    _writes++;
    _targets.add(FirestoreRulesWriteTarget(
      operation: 'UPDATE',
      collection: FirestoreRulesAudit.collectionFor(document.path),
      pathTemplate: FirestoreRulesAudit.pathTemplateFor(document.path),
      changedKeys: _knownExistence[document.path] == true
          ? FirestoreRulesAudit.affectedKeysFromKnownState(
                before: _knownBefore[document.path],
                payload: data, merge: true,
              ) ?? FirestoreRulesAudit.safeProjectionKeys(data)
          : FirestoreRulesAudit.safeProjectionKeys(data),
      documentExists: true,
      documentEvidence: 'UPDATE_REQUIRES_EXISTENCE',
      fieldEvidence: _knownExistence[document.path] == true &&
              FirestoreRulesAudit.affectedKeysFromKnownState(
                before: _knownBefore[document.path],
                payload: data, merge: true,
              ) != null
          ? 'PRIOR_SNAPSHOT_DIFF'
          : FirestoreRulesAudit.safeProjectionKeys(data) != null
              ? 'WRITE_SCOPE' : 'UNKNOWN',
    ));
  }

  void delete(DocumentReference<Object?> document) {
    _delegate.delete(document);
    _deletes++;
    _targets.add(FirestoreRulesWriteTarget(
      operation: 'DELETE',
      collection: FirestoreRulesAudit.collectionFor(document.path),
      pathTemplate: FirestoreRulesAudit.pathTemplateFor(document.path),
    ));
  }

  Future<void> commit() async {
    final meter = FirebaseActivityMeter.instance;
    final requestId = meter.nextOperationId();
    final authAtStart = FirebaseAuthRulesDiagnostics.captureForRequest();
    var success = false;
    String? firebaseCode;
    try {
      await _delegate.commit();
      success = true;
      if (!_committed) {
        _committed = true;
        meter.record(
          service: 'firestore',
          operation: 'COMMITTED_BATCH',
          source: _source,
          requestId: requestId,
          committedWrites: _writes,
          committedDeletes: _deletes,
          detail: 'writes=$_writes deletes=$_deletes',
        );
      }
    } on FirebaseException catch (error) {
      firebaseCode = error.code;
      meter.record(
        service: 'firestore',
        operation: 'COMMITTED_BATCH',
        source: _source,
        result: 'error',
        requestId: requestId,
        firebaseCode: error.code,
        detail: 'writes=$_writes deletes=$_deletes',
      );
      rethrow;
    } catch (error) {
      meter.record(
        service: 'firestore',
        operation: 'COMMITTED_BATCH',
        source: _source,
        result: 'error',
        requestId: requestId,
        detail: error.runtimeType.toString(),
      );
      rethrow;
    } finally {
      meter.recordWriteTargets(
        requestId: requestId,
        source: _source,
        targets: _targets,
        authOverride: authAtStart,
        kind: 'BATCH',
      );
      meter.recordRulesAudit(
        requestId: requestId,
        collection: null,
        operation: 'BATCH',
        source: _source,
        success: success,
        firebaseCode: firebaseCode,
        authOverride: authAtStart,
        sessionChanged: (authAtStart != null && !FirebaseAuthRulesDiagnostics.isSameSession(authAtStart)),
        expectedOverride: FirestoreRulesAudit.expectedWrites(
          _targets, authOverride: authAtStart,
        ),
      );
    }
  }
}

extension FirebaseActivityFirestoreTransaction on FirebaseFirestore {
  Future<T> runTrackedActivityTransaction<T>(
    Future<T> Function(Transaction transaction) transactionHandler, {
    Duration timeout = const Duration(seconds: 30),
    int maxAttempts = 5,
    String? source,
  }) async {
    final meter = FirebaseActivityMeter.instance;
    final operationId = meter.nextOperationId();
    final authAtStart = FirebaseAuthRulesDiagnostics.captureForRequest();
    FirebaseWriteCommitDelta? latestAttempt;
    var attemptCount = 0;
    var success = false;
    String? firebaseCode;
    late final T result;
    try {
      result = await runTransaction<T>(
        (transaction) {
          final attempt = FirebaseWriteCommitDelta()..tracksOperations = true;
          attemptCount++;
          latestAttempt = attempt;
          return runZoned<Future<T>>(
            () async {
              final value = await transactionHandler(
                _TrackedFirestoreTransaction(transaction, attempt),
              );
              latestAttempt = attempt.copy();
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
      success = true;
      final delta = latestAttempt;
      meter.record(
        service: 'firestore',
        operation: 'COMMITTED_TRANSACTION',
        source: source ?? delta?.source ?? 'firestore.transaction',
        operationId: operationId,
        requestId: operationId,
        readPurpose: 'TRANSACTION_COMMIT',
        committedWrites: delta?.writes ?? 0,
        committedDeletes: delta?.deletes ?? 0,
        detail: 'reads=${delta?.readTargets.length ?? 0} '
            'sets=${delta?.sets ?? 0} updates=${delta?.updates ?? 0} '
            'deletes=${delta?.deletes ?? 0} attempts=$attemptCount',
      );
    } on FirebaseException catch (error) {
      firebaseCode = error.code;
      meter.record(
        service: 'firestore',
        operation: 'COMMITTED_TRANSACTION',
        source: source ?? 'firestore.transaction',
        result: 'error',
        requestId: operationId,
        firebaseCode: error.code,
        detail: 'attempts=$attemptCount',
      );
      rethrow;
    } catch (error) {
      meter.record(
        service: 'firestore',
        operation: 'COMMITTED_TRANSACTION',
        source: source ?? 'firestore.transaction',
        result: 'error',
        requestId: operationId,
        detail: 'attempts=$attemptCount errorType=${error.runtimeType}',
      );
      rethrow;
    } finally {
      final delta = latestAttempt;
      final targets = delta?.targets ?? <FirestoreRulesWriteTarget>[];
      final readTargets = delta?.readTargets ?? <FirestoreRulesWriteTarget>[];
      final eventSource = source ?? delta?.source ?? 'firestore.transaction';
      meter.recordWriteTargets(
        requestId: operationId,
        source: eventSource,
        targets: <FirestoreRulesWriteTarget>[...readTargets, ...targets],
        authOverride: authAtStart,
        kind: 'TRANSACTION',
      );
      meter.recordRulesAudit(
        requestId: operationId,
        collection: null,
        operation: 'TRANSACTION',
        source: eventSource,
        success: success,
        firebaseCode: firebaseCode,
        authOverride: authAtStart,
        sessionChanged: (authAtStart != null &&
            !FirebaseAuthRulesDiagnostics.isSameSession(authAtStart)),
        expectedOverride: FirestoreRulesAudit.expectedTransaction(
          reads: readTargets,
          writes: targets,
          authOverride: authAtStart,
        ),
      );
    }
    return result;
  }

  FirebaseActivityWriteBatch trackedActivityBatch(String source) =>
      FirebaseActivityWriteBatch(batch(), source);
}

extension FirebaseActivityFutureTracking<T> on Future<T> {
  Future<T> trackFirestore(
    String operation,
    String source, {
    String? collection,
    String? pathTemplate,
    Set<String>? changedKeys,
    String? readPurpose,
    DocumentReference? documentReference,
  }) {
    return FirebaseActivityMeter.instance.trackFuture<T>(
      this,
      service: 'firestore',
      operation: operation,
      source: source,
      collection: collection ?? (documentReference == null
          ? null : FirestoreRulesAudit.collectionFor(documentReference.path)),
      pathTemplate: pathTemplate ?? (documentReference == null
          ? null : FirestoreRulesAudit.pathTemplateFor(documentReference.path)),
      changedKeys: changedKeys,
      readPurpose: readPurpose,
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
  Stream<T> trackFirestoreSnapshots(
    String source, {
    String? collection,
    String? pathTemplate,
    String? operation,
  }) {
    return FirebaseActivityMeter.instance.observeSnapshots<T>(
      this, source, collection: collection, pathTemplate: pathTemplate,
      operation: operation,
    );
  }
}
