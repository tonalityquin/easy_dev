import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../../features/selector/application/dev_auth.dart';
import 'firebase_activity_write_scope.dart';

enum FirebaseActivityKind {
  read,
  snapshot,
  write,
  set,
  create,
  update,
  delete,
  batch,
  transaction,
  storage,
  authentication,
  initialization,
}

enum FirebaseActivityPhase { started, received, completed, failed }

@immutable
class FirebaseActivityEvent {
  const FirebaseActivityEvent({
    required this.sequence,
    required this.timestamp,
    required this.kind,
    required this.phase,
    required this.source,
    this.operationId,
    this.parentOperationId,
    this.durationMs,
    this.documents,
    this.fromCache,
    this.pendingWrites,
    this.errorCode,
    this.setCommands = 0,
    this.createCommands = 0,
    this.updateCommands = 0,
    this.deleteCommands = 0,
    this.attempts = 0,
    this.added = 0,
    this.modified = 0,
    this.removed = 0,
  });

  final int sequence;
  final DateTime timestamp;
  final FirebaseActivityKind kind;
  final FirebaseActivityPhase phase;
  final String source;
  final int? operationId;
  final int? parentOperationId;
  final int? durationMs;
  final int? documents;
  final bool? fromCache;
  final bool? pendingWrites;
  final String? errorCode;
  final int setCommands;
  final int createCommands;
  final int updateCommands;
  final int deleteCommands;
  final int attempts;
  final int added;
  final int modified;
  final int removed;

  int get documentCommands =>
      setCommands + createCommands + updateCommands + deleteCommands;

  bool matchesStatusFilter(
    String filter, {
    required bool isRunning,
  }) {
    switch (filter) {
      case 'all':
        return true;
      case 'running':
        return phase == FirebaseActivityPhase.started && isRunning;
      case 'completed':
        return phase == FirebaseActivityPhase.completed;
      case 'received':
        return phase == FirebaseActivityPhase.received;
      case 'failed':
        return phase == FirebaseActivityPhase.failed;
      default:
        return false;
    }
  }

  bool matchesFilter(String filter) {
    switch (filter) {
      case 'all':
        return true;
      case 'failed':
        return phase == FirebaseActivityPhase.failed;
      case 'read':
        return kind == FirebaseActivityKind.read;
      case 'snapshot':
        return kind == FirebaseActivityKind.snapshot;
      case 'create':
        return kind == FirebaseActivityKind.create || createCommands > 0;
      case 'update':
        return kind == FirebaseActivityKind.update || updateCommands > 0;
      case 'set':
        return kind == FirebaseActivityKind.set || setCommands > 0;
      case 'delete':
        return kind == FirebaseActivityKind.delete || deleteCommands > 0;
      case 'write':
        return kind == FirebaseActivityKind.write ||
            kind == FirebaseActivityKind.set ||
            kind == FirebaseActivityKind.create ||
            kind == FirebaseActivityKind.update ||
            kind == FirebaseActivityKind.delete ||
            documentCommands > 0;
      case 'batch':
        return kind == FirebaseActivityKind.batch;
      case 'transaction':
        return kind == FirebaseActivityKind.transaction;
      default:
        return false;
    }
  }

  String get debugLine => <String>[
        '[FIREBASE_ACTIVITY]',
        timestamp.toIso8601String(),
        kind.name,
        phase.name,
        'source=$source',
        if (operationId != null) 'operationId=$operationId',
        if (parentOperationId != null) 'parentId=$parentOperationId',
        if (durationMs != null) 'elapsedMs=$durationMs',
        if (documents != null) 'resultDocuments=$documents',
        if (documentCommands > 0)
          'commands=set:$setCommands,create:$createCommands,update:$updateCommands,delete:$deleteCommands',
        if (attempts > 0) 'attempts=$attempts',
        if (kind == FirebaseActivityKind.snapshot)
          'changes=added:$added,modified:$modified,removed:$removed',
        if (fromCache != null) 'fromCache=$fromCache',
        if (pendingWrites != null) 'pendingWrites=$pendingWrites',
        if (errorCode != null) 'error=$errorCode',
      ].join(' ');
}

class FirebaseActivityMonitor extends ChangeNotifier {
  FirebaseActivityMonitor._();

  static final FirebaseActivityMonitor instance = FirebaseActivityMonitor._();
  static final Object _parentOperationKey = Object();
  static final Object _transactionScopeKey = Object();
  static const int maxEvents = 200;
  static const Duration idleDelay = Duration(milliseconds: 1500);

  final Queue<FirebaseActivityEvent> _events = Queue<FirebaseActivityEvent>();
  final Map<int, FirebaseActivityEvent> _running =
      <int, FirebaseActivityEvent>{};
  final Set<int> _finished = <int>{};
  final Queue<int> _finishedOrder = Queue<int>();
  final Map<FirebaseActivityKind, int> _completed =
      <FirebaseActivityKind, int>{};
  FirebaseActivityEvent? _latest;
  Timer? _refreshTimer;
  Timer? _idleTimer;
  int _sequence = 0;
  int _operationSequence = 0;
  int _snapshotReceivedCount = 0;
  int _cachedSnapshotCount = 0;
  int _localSnapshotCount = 0;
  int _snapshotAddedCount = 0;
  int _snapshotModifiedCount = 0;
  int _snapshotRemovedCount = 0;
  int _failedEventCount = 0;
  int _setCommandCount = 0;
  int _createCommandCount = 0;
  int _updateCommandCount = 0;
  int _deleteCommandCount = 0;
  int _topLevelCompletedCount = 0;
  int _nestedCompletedCount = 0;
  int _readResultDocumentCount = 0;
  int _cacheReadResponseCount = 0;
  bool _started = false;
  bool _isIdle = true;
  DateTime? _lastNotification;

  FirebaseActivityEvent? get latest => _latest;
  FirebaseActivityEvent? get visibleEvent => _isIdle ? null : _latest;
  bool get isIdle => _isIdle;
  bool get started => _started;
  int get activeOperationCount => _running.length;
  bool isOperationRunning(int? operationId) =>
      operationId != null && _running.containsKey(operationId);
  int get snapshotCount => _snapshotReceivedCount;
  int get failureCount => _failedEventCount;
  int get cacheSnapshotCount => _cachedSnapshotCount;
  int get localSnapshotCount => _localSnapshotCount;
  int get setCount => _setCommandCount;
  int get createCount => _createCommandCount;
  int get updateCount => _updateCommandCount;
  int get deleteCount => _deleteCommandCount;
  int get documentCommandCount =>
      _setCommandCount + _createCommandCount + _updateCommandCount + _deleteCommandCount;
  int count(FirebaseActivityKind kind) => _completed[kind] ?? 0;
  int get completedOperationCount =>
      _completed.values.fold<int>(0, (sum, count) => sum + count);
  int get topLevelCompletedCount => _topLevelCompletedCount;
  int get nestedCompletedCount => _nestedCompletedCount;
  int get readResultDocumentCount => _readResultDocumentCount;
  int get cacheReadResponseCount => _cacheReadResponseCount;
  int get totalActivityCount =>
      _topLevelCompletedCount + _snapshotReceivedCount;
  int get snapshotAddedCount => _snapshotAddedCount;
  int get snapshotModifiedCount => _snapshotModifiedCount;
  int get snapshotRemovedCount => _snapshotRemovedCount;
  List<FirebaseActivityEvent> get events =>
      List<FirebaseActivityEvent>.unmodifiable(_events);
  List<FirebaseActivityEvent> get runningOperations =>
      List<FirebaseActivityEvent>.unmodifiable(_running.values);

  void start() {
    if (_started) return;
    _started = true;
    emit(FirebaseActivityKind.initialization, FirebaseActivityPhase.received,
        source: 'app.start');
  }

  void _requestRefresh() {
    if (_refreshTimer != null) return;
    final now = DateTime.now();
    final last = _lastNotification;
    if (last == null || now.difference(last).inMilliseconds >= 70) {
      _lastNotification = now;
      notifyListeners();
    } else {
      _refreshTimer = Timer(const Duration(milliseconds: 70), () {
        _refreshTimer = null;
        _lastNotification = DateTime.now();
        notifyListeners();
      });
    }
  }

  void _scheduleIdle() {
    _idleTimer?.cancel();
    _idleTimer = null;
    if (_running.isNotEmpty) return;
    _idleTimer = Timer(idleDelay, () {
      _idleTimer = null;
      if (_running.isNotEmpty) return;
      _isIdle = true;
      _requestRefresh();
    });
  }

  void emit(
    FirebaseActivityKind kind,
    FirebaseActivityPhase phase, {
    required String source,
    int? operationId,
    int? parentOperationId,
    int? durationMs,
    int? documents,
    bool? fromCache,
    bool? pendingWrites,
    String? errorCode,
    FirebaseActivityWriteCounts? commands,
    int added = 0,
    int modified = 0,
    int removed = 0,
  }) {
    if (!_started) start();
    if (operationId != null &&
        phase != FirebaseActivityPhase.started &&
        _finished.contains(operationId)) {
      return;
    }
    final event = FirebaseActivityEvent(
      sequence: ++_sequence,
      timestamp: DateTime.now(),
      kind: kind,
      phase: phase,
      source: _safeSource(source),
      operationId: operationId,
      parentOperationId: parentOperationId,
      durationMs: durationMs,
      documents: documents,
      fromCache: fromCache,
      pendingWrites: pendingWrites,
      errorCode: errorCode,
      setCommands: commands?.sets ?? 0,
      createCommands: commands?.creates ?? 0,
      updateCommands: commands?.updates ?? 0,
      deleteCommands: commands?.deletes ?? 0,
      attempts: commands?.attempts ?? 0,
      added: added,
      modified: modified,
      removed: removed,
    );
    if (operationId != null) {
      if (phase == FirebaseActivityPhase.started) {
        _running[operationId] = event;
      } else {
        _running.remove(operationId);
        _finished.add(operationId);
        _finishedOrder.addLast(operationId);
        while (_finishedOrder.length > 1000) {
          _finished.remove(_finishedOrder.removeFirst());
        }
      }
    }
    if (phase == FirebaseActivityPhase.completed) {
      _completed.update(kind, (value) => value + 1, ifAbsent: () => 1);
      if (parentOperationId == null) {
        _topLevelCompletedCount++;
      } else {
        _nestedCompletedCount++;
      }
      if (kind == FirebaseActivityKind.read) {
        _readResultDocumentCount += event.documents ?? 0;
        if (fromCache == true) _cacheReadResponseCount++;
      }
      if (event.documentCommands > 0) {
        _setCommandCount += event.setCommands;
        _createCommandCount += event.createCommands;
        _updateCommandCount += event.updateCommands;
        _deleteCommandCount += event.deleteCommands;
      } else {
        if (kind == FirebaseActivityKind.set) _setCommandCount++;
        if (kind == FirebaseActivityKind.create) _createCommandCount++;
        if (kind == FirebaseActivityKind.update) _updateCommandCount++;
        if (kind == FirebaseActivityKind.delete) _deleteCommandCount++;
      }
    }
    if (kind == FirebaseActivityKind.snapshot &&
        phase == FirebaseActivityPhase.received) {
      _snapshotReceivedCount++;
      if (fromCache == true) _cachedSnapshotCount++;
      if (pendingWrites == true) _localSnapshotCount++;
      _snapshotAddedCount += added;
      _snapshotModifiedCount += modified;
      _snapshotRemovedCount += removed;
    }
    if (phase == FirebaseActivityPhase.failed) _failedEventCount++;
    _events.addLast(event);
    while (_events.length > maxEvents) {
      _events.removeFirst();
    }
    _latest = event;
    _isIdle = false;
    _scheduleIdle();
    if (DevAuth.devModeEnabled.value) debugPrint(event.debugLine);
    _requestRefresh();
  }

  static void beginTransactionAttempt() {
    final scope = Zone.current[_transactionScopeKey];
    if (scope is FirebaseActivityWriteCounts) scope.resetAttempt();
  }

  static void transactionCommand(
    FirebaseActivityDocumentCommand kind,
    void Function() execute,
  ) {
    execute();
    final scope = Zone.current[_transactionScopeKey];
    if (scope is FirebaseActivityWriteCounts) scope.add(kind);
  }

  static Future<T> track<T>(
    FirebaseActivityKind kind,
    Future<T> Function() execute, {
    required String source,
    Object? batch,
  }) async {
    final monitor = instance;
    final operationId = ++monitor._operationSequence;
    final parentOperationId = Zone.current[_parentOperationKey] as int?;
    final transactionScope = kind == FirebaseActivityKind.transaction
        ? FirebaseActivityWriteCounts()
        : null;
    monitor.emit(kind, FirebaseActivityPhase.started,
        source: source,
        operationId: operationId,
        parentOperationId: parentOperationId);
    final stopwatch = Stopwatch()..start();
    try {
      final result = await runZoned<Future<T>>(
        execute,
        zoneValues: <Object, Object>{
          _parentOperationKey: operationId,
          if (transactionScope != null) _transactionScopeKey: transactionScope,
        },
      );
      stopwatch.stop();
      final metadata = _snapshotMetadata(result);
      final commands = kind == FirebaseActivityKind.batch
          ? FirebaseActivityWriteScope.takeBatch(batch)
          : transactionScope?.copy();
      monitor.emit(kind, FirebaseActivityPhase.completed,
          source: source,
          operationId: operationId,
          parentOperationId: parentOperationId,
          durationMs: stopwatch.elapsedMilliseconds,
          documents: metadata.$1,
          fromCache: metadata.$2,
          pendingWrites: metadata.$3,
          commands: commands);
      return result;
    } catch (error) {
      stopwatch.stop();
      final commands = kind == FirebaseActivityKind.batch
          ? FirebaseActivityWriteScope.takeBatch(batch)
          : transactionScope?.copy();
      monitor.emit(kind, FirebaseActivityPhase.failed,
          source: source,
          operationId: operationId,
          parentOperationId: parentOperationId,
          durationMs: stopwatch.elapsedMilliseconds,
          commands: commands,
          errorCode: _safeError(error));
      rethrow;
    }
  }

  static Stream<T> observe<T>(Stream<T> source, {required String origin}) {
    return source.transform(
      StreamTransformer<T, T>.fromHandlers(
        handleData: (event, sink) {
          final metadata = _snapshotMetadata(event);
          var added = 0;
          var modified = 0;
          var removed = 0;
          if (event is QuerySnapshot) {
            for (final change in event.docChanges) {
              switch (change.type) {
                case DocumentChangeType.added:
                  added++;
                case DocumentChangeType.modified:
                  modified++;
                case DocumentChangeType.removed:
                  removed++;
              }
            }
          }
          instance.emit(
            FirebaseActivityKind.snapshot,
            FirebaseActivityPhase.received,
            source: origin,
            documents: metadata.$1,
            fromCache: metadata.$2,
            pendingWrites: metadata.$3,
            added: added,
            modified: modified,
            removed: removed,
          );
          sink.add(event);
        },
        handleError: (Object error, StackTrace stackTrace, sink) {
          instance.emit(
            FirebaseActivityKind.snapshot,
            FirebaseActivityPhase.failed,
            source: origin,
            errorCode: _safeError(error),
          );
          sink.addError(error, stackTrace);
        },
      ),
    );
  }

  static (int?, bool?, bool?) _snapshotMetadata(Object? value) {
    if (value is QuerySnapshot) {
      return (value.docs.length, value.metadata.isFromCache,
          value.metadata.hasPendingWrites);
    }
    if (value is DocumentSnapshot) {
      return (value.exists ? 1 : 0, value.metadata.isFromCache,
          value.metadata.hasPendingWrites);
    }
    return (null, null, null);
  }

  static String _safeSource(String value) {
    final normalized = value.replaceAll(RegExp(r'[^a-zA-Z0-9_./:-]'), '_');
    return normalized.length > 120 ? normalized.substring(0, 120) : normalized;
  }

  static String _safeError(Object error) {
    if (error is FirebaseException) {
      return _safeSource('firebase_${error.code}');
    }
    return _safeSource(error.runtimeType.toString());
  }

  String debugPrintCodeForEvent(FirebaseActivityEvent event) =>
      'debugPrint(${jsonEncode(event.debugLine)});';

  String debugPrintCodeFor(
    Iterable<FirebaseActivityEvent> visible, {
    String? typeFilter,
    String? statusFilter,
  }) {
    final selected = visible.toList(growable: false);
    final cumulativeSummary = summary.replaceAll('\n', ' | ');
    return <String>[
      'debugPrint(${jsonEncode('[FIREBASE_ACTIVITY] $cumulativeSummary')});',
      if (typeFilter != null || statusFilter != null)
        'debugPrint(${jsonEncode('[FIREBASE_ACTIVITY_FILTER] '
            'type=${_safeSource(typeFilter ?? 'all')} '
            'status=${_safeSource(statusFilter ?? 'all')} '
            'recentRows=${selected.length} maxRetained=$maxEvents')});',
      ...selected.map(debugPrintCodeForEvent),
    ].join('\n');
  }

  String get debugPrintCode => debugPrintCodeFor(_events);

  String get summary =>
      '앱 시작 이후 상위 작업 완료 $_topLevelCompletedCount회 · '
      '내부 계측 완료 $_nestedCompletedCount회 · Snapshot $_snapshotReceivedCount회 · '
      '상단 완료·수신 합계 $totalActivityCount회 · '
      '읽기 호출 완료 ${count(FirebaseActivityKind.read)}회 · '
      '조회 결과 문서 수 $_readResultDocumentCount건(캐시 포함) · '
      'set/upsert 성공 $_setCommandCount건 · 생성 분류 성공 $_createCommandCount건 · '
      '수정 명령 성공 $_updateCommandCount건 · 삭제 명령 성공 $_deleteCommandCount건 · '
      '분류 가능 성공 문서 명령 $documentCommandCount건 · '
      '종류 미분류 쓰기 완료 ${count(FirebaseActivityKind.write)}회 · '
      'Batch ${count(FirebaseActivityKind.batch)}회 · '
      'Transaction ${count(FirebaseActivityKind.transaction)}회 · '
      '진행 중 $activeOperationCount건 · 실패 $_failedEventCount회\n'
      '최근 기록 ${_events.length}건 / 최대 $maxEvents건 · '
      'Snapshot에는 캐시 및 로컬 이벤트가 포함될 수 있습니다. '
      '미분류 쓰기 호출은 분류 가능 문서 명령 합계에서 제외됩니다. '
      '완료·수신 합계는 실제 과금 건수나 청구 금액이 아닙니다.';

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _idleTimer?.cancel();
    super.dispose();
  }
}
