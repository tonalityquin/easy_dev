import '../utils/status_dialog.dart';
import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../../features/selector/application/dev_auth.dart';
import 'firebase_activity_write_scope.dart';
import 'firebase_activity_cost_estimator.dart';
import 'firebase_activity_listener_state.dart';
import 'firebase_activity_billing_config.dart';
import 'firestore_document_sizer.dart';

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

enum FirebaseActivityPhase {
  started,
  received,
  completed,
  failed,
  cancelled,
  outcomeUnknown,
}

enum FirebaseActivityStage {
  preparing,
  submitting,
  attempting,
  retrying,
  callerTimedOut,
  stalePreparation,
}

enum FirebaseActionOutcome {
  running,
  completed,
  completedWithWarnings,
  partial,
  failed,
  skipped,
  cancelled,
}

enum FirebaseActivityCallState { notInvoked, sdkFutureReturned }

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
    this.actionId,
    this.actionName,
    this.counterBefore,
    this.counterAfter,
    this.stage,
    this.durationMs,
    this.documents,
    this.fromCache,
    this.pendingWrites,
    this.errorCode,
    this.callState,
    this.outcomeBasis,
    this.setCommands = 0,
    this.createCommands = 0,
    this.updateCommands = 0,
    this.deleteCommands = 0,
    this.attempts = 0,
    this.added = 0,
    this.modified = 0,
    this.removed = 0,
    this.dataBytes = 0,
    this.fieldCount = 0,
    this.estimatedWon = 0,
    this.estimatedUnits = 0,
    this.costUncertain = false,
    this.listenerId,
    this.costReason,
    this.metadataOnly = false,
    this.reconnectCandidate = false,
    this.possibleExtraReads = 0,
    this.readStrategy = FirestoreReadStrategy.unknown,
  });

  final int sequence;
  final DateTime timestamp;
  final FirebaseActivityKind kind;
  final FirebaseActivityPhase phase;
  final String source;
  final int? operationId;
  final int? parentOperationId;
  final int? actionId;
  final String? actionName;
  final int? counterBefore;
  final int? counterAfter;
  bool get increasedCounter =>
      counterBefore != null && counterAfter != null && counterAfter! > counterBefore!;
  final FirebaseActivityStage? stage;
  final int? durationMs;
  final int? documents;
  final bool? fromCache;
  final bool? pendingWrites;
  final String? errorCode;
  final FirebaseActivityCallState? callState;
  final String? outcomeBasis;
  final int setCommands;
  final int createCommands;
  final int updateCommands;
  final int deleteCommands;
  final int attempts;
  final int added;
  final int modified;
  final int removed;
  final int dataBytes;
  final int fieldCount;
  final double estimatedWon;
  final int estimatedUnits;
  final bool costUncertain;
  final int? listenerId;
  final String? costReason;
  final bool metadataOnly;
  final bool reconnectCandidate;
  final int possibleExtraReads;
  final FirestoreReadStrategy readStrategy;

  int get documentCommands =>
      setCommands + createCommands + updateCommands + deleteCommands;

  FirebaseActivityEvent withCallState(FirebaseActivityCallState value) =>
      FirebaseActivityEvent(
        sequence: sequence,
        timestamp: timestamp,
        kind: kind,
        phase: phase,
        source: source,
        operationId: operationId,
        parentOperationId: parentOperationId,
        actionId: actionId,
        actionName: actionName,
        counterBefore: counterBefore,
        counterAfter: counterAfter,
        stage: stage,
        durationMs: durationMs,
        documents: documents,
        fromCache: fromCache,
        pendingWrites: pendingWrites,
        errorCode: errorCode,
        callState: value,
        outcomeBasis: outcomeBasis,
        setCommands: setCommands,
        createCommands: createCommands,
        updateCommands: updateCommands,
        deleteCommands: deleteCommands,
        attempts: attempts,
        added: added,
        modified: modified,
        removed: removed,
        dataBytes: dataBytes,
        fieldCount: fieldCount,
        estimatedWon: estimatedWon,
        estimatedUnits: estimatedUnits,
        costUncertain: costUncertain,
        listenerId: listenerId,
        costReason: costReason,
        metadataOnly: metadataOnly,
        reconnectCandidate: reconnectCandidate,
        possibleExtraReads: possibleExtraReads,
        readStrategy: readStrategy,
      );

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
      case 'cancelled':
        return phase == FirebaseActivityPhase.cancelled;
      case 'unknown':
        return phase == FirebaseActivityPhase.outcomeUnknown;
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
        'sequence=$sequence',
        if (actionId != null) 'actionId=$actionId',
        if (actionName != null) 'action=$actionName',
        if (increasedCounter) 'counter=$counterBefore->$counterAfter',
        if (operationId != null) 'operationId=$operationId',
        if (parentOperationId != null) 'parentId=$parentOperationId',
        if (stage != null) 'stage=${stage!.name}',
        if (durationMs != null) 'elapsedMs=$durationMs',
        if (documents != null) 'resultDocuments=$documents',
        if (dataBytes > 0) 'dataBytes=$dataBytes fields=$fieldCount',
        if (estimatedUnits > 0) 'estimatedUnits=$estimatedUnits',
        if (estimatedWon > 0) 'estimatedWon=${estimatedWon.toStringAsFixed(8)}',
        if (costUncertain) 'costEstimateUncertain=true',
        if (listenerId != null) 'listenerId=$listenerId',
        if (metadataOnly) 'metadataOnly=true',
        if (reconnectCandidate) 'reconnectCandidate=true',
        if (possibleExtraReads > 0) 'possibleExtraReads=$possibleExtraReads',
        if (costReason != null) 'costReason=$costReason',
        if (readStrategy != FirestoreReadStrategy.unknown) 'readStrategy=${readStrategy.name}',
        if (documentCommands > 0)
          'commands=set:$setCommands,create:$createCommands,update:$updateCommands,delete:$deleteCommands',
        if (attempts > 0) 'attempts=$attempts',
        if (kind == FirebaseActivityKind.snapshot)
          'changes=added:$added,modified:$modified,removed:$removed',
        if (fromCache != null) 'fromCache=$fromCache',
        if (pendingWrites != null) 'pendingWrites=$pendingWrites',
        if (callState != null) 'sdkCall=${callState!.name}',
        if (outcomeBasis != null) 'outcomeBasis=$outcomeBasis',
        if (errorCode != null) 'error=$errorCode',
      ].join(' ');
}

@immutable
class FirebaseActivityAction {
  const FirebaseActivityAction({
    required this.id,
    required this.name,
    required this.startedAt,
    this.finishedAt,
    this.outcome = FirebaseActionOutcome.running,
    this.errorCode,
    this.issueCodes = const <String>[],
  });

  final int id;
  final String name;
  final DateTime startedAt;
  final DateTime? finishedAt;
  final FirebaseActionOutcome outcome;
  final String? errorCode;
  final List<String> issueCodes;

  bool get running => outcome == FirebaseActionOutcome.running;

  bool? get succeeded => running
      ? null
      : outcome == FirebaseActionOutcome.completed ||
          outcome == FirebaseActionOutcome.completedWithWarnings;

  String get outcomeLabel => switch (outcome) {
        FirebaseActionOutcome.running => '진행 중',
        FirebaseActionOutcome.completed => '완료',
        FirebaseActionOutcome.completedWithWarnings => '완료·주의',
        FirebaseActionOutcome.partial => '부분 성공',
        FirebaseActionOutcome.failed => '실패',
        FirebaseActionOutcome.skipped => '실행 생략',
        FirebaseActionOutcome.cancelled => '취소',
      };

  String get debugLine => <String>[
        '[FIREBASE_ACTION]',
        'actionId=$id',
        'action=$name',
        'startedAt=${startedAt.toIso8601String()}',
        if (finishedAt != null) 'finishedAt=${finishedAt!.toIso8601String()}',
        'state=${outcome.name}',
        if (errorCode != null) 'error=$errorCode',
        if (issueCodes.isNotEmpty) 'issues=${issueCodes.join(',')}',
      ].join(' ');
}

class FirebaseActivityMonitor extends ChangeNotifier {
  FirebaseActivityMonitor._();

  static final FirebaseActivityMonitor instance = FirebaseActivityMonitor._();
  static final Object _parentOperationKey = Object();
  static final Object _actionKey = Object();
  static const int maxCounterIncrements = 1000;
  static const int maxActions = 200;
  static final Object _transactionScopeKey = Object();
  static final Object _transactionOperationKey = Object();
  static const int maxEvents = 200;
  static const Duration idleDelay = Duration(milliseconds: 1500);

  final FirebaseActivityCostEstimator cost = FirebaseActivityCostEstimator();
  final Queue<FirebaseActivityEvent> _events = Queue<FirebaseActivityEvent>();
  final Queue<FirebaseActivityEvent> _counterIncrements =
      Queue<FirebaseActivityEvent>();
  final Queue<FirebaseActivityAction> _actions = Queue<FirebaseActivityAction>();
  final Map<int, FirebaseActivityAction> _activeActions =
      <int, FirebaseActivityAction>{};
  final Map<int, int> _operationActionIds = <int, int>{};
  final Map<int, FirebaseActionOutcome> _actionOutcomes =
      <int, FirebaseActionOutcome>{};
  final Map<int, List<String>> _actionIssues = <int, List<String>>{};
  final Map<int, FirebaseActivityEvent> _running =
      <int, FirebaseActivityEvent>{};
  final Set<int> _finished = <int>{};
  final Queue<int> _finishedOrder = Queue<int>();
  final Map<int, Timer> _preparationTimers = <int, Timer>{};
  final Map<FirebaseActivityKind, int> _completed =
      <FirebaseActivityKind, int>{};
  FirebaseActivityEvent? _latest;
  Timer? _refreshTimer;
  Timer? _idleTimer;
  int _sequence = 0;
  int _actionSequence = 0;
  int _operationSequence = 0;
  static int _listenerSequence = 0;
  int _snapshotReceivedCount = 0;
  int _cachedSnapshotCount = 0;
  int _localSnapshotCount = 0;
  int _snapshotAddedCount = 0;
  int _snapshotModifiedCount = 0;
  int _snapshotRemovedCount = 0;
  int _failedEventCount = 0;
  int _unknownOutcomeCount = 0;
  int _abandonedBatchCount = 0;
  int _stalePreparationCount = 0;
  int _setCommandCount = 0;
  int _createCommandCount = 0;
  int _updateCommandCount = 0;
  int _deleteCommandCount = 0;
  int _topLevelCompletedCount = 0;
  int _nestedCompletedCount = 0;
  int _firestoreOperationCount = 0;
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
  FirebaseActivityEvent? runningEventFor(int? operationId) =>
      operationId == null ? null : _running[operationId];
  int get snapshotCount => _snapshotReceivedCount;
  int get failureCount => _failedEventCount;
  int get unknownOutcomeCount => _unknownOutcomeCount;
  int get abandonedBatchCount => _abandonedBatchCount;
  int get stalePreparationCount => _stalePreparationCount;
  List<FirebaseActivityEvent> get topLevelRunningOperations =>
      List<FirebaseActivityEvent>.unmodifiable(
        _running.values.where((event) => event.parentOperationId == null),
      );
  List<FirebaseActivityEvent> get nestedRunningOperations =>
      List<FirebaseActivityEvent>.unmodifiable(
        _running.values.where((event) => event.parentOperationId != null),
      );
  int get topLevelActiveOperationCount => topLevelRunningOperations.length;
  int get nestedActiveOperationCount => nestedRunningOperations.length;
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
  int get firestoreOperationCount => _firestoreOperationCount;
  int get snapshotAddedCount => _snapshotAddedCount;
  int get snapshotModifiedCount => _snapshotModifiedCount;
  int get snapshotRemovedCount => _snapshotRemovedCount;
  List<FirebaseActivityEvent> get events =>
      List<FirebaseActivityEvent>.unmodifiable(_events);
  List<FirebaseActivityEvent> get counterIncrements =>
      List<FirebaseActivityEvent>.unmodifiable(_counterIncrements);
  List<FirebaseActivityAction> get actions =>
      List<FirebaseActivityAction>.unmodifiable(_actions);
  int get omittedCounterIncrements =>
      firestoreOperationCount - _counterIncrements.length;
  List<FirebaseActivityEvent> get runningOperations =>
      List<FirebaseActivityEvent>.unmodifiable(_running.values);

  static Future<T> runAction<T>(
    String name,
    Future<T> Function() execute,
  ) async {
    final monitor = instance;
    final safeName = _safeActionName(name);
    final id = ++monitor._actionSequence;
    final startedAt = DateTime.now();
    final action = FirebaseActivityAction(
      id: id,
      name: safeName,
      startedAt: startedAt,
    );
    monitor._activeActions[id] = action;
    monitor._actions.addLast(action);
    while (monitor._actions.length > maxActions) {
      monitor._actions.removeFirst();
    }
    monitor._printAction(action);
    monitor._requestRefresh();
    try {
      final result = await runZoned<Future<T>>(
        execute,
        zoneValues: <Object, Object>{_actionKey: id},
      );
      final marked = monitor._actionOutcomes.remove(id);
      final issues = monitor._actionIssues.remove(id) ?? <String>[];
      final outcome = marked ??
          (result is bool && result == false
              ? FirebaseActionOutcome.failed
              : FirebaseActionOutcome.completed);
      final normalized = result is bool && result == false &&
              outcome == FirebaseActionOutcome.completed
          ? FirebaseActionOutcome.failed
          : outcome;
      if (normalized == FirebaseActionOutcome.failed && issues.isEmpty) {
        issues.add('action_rejected');
      }
      monitor._finishAction(
        id,
        safeName,
        startedAt,
        normalized,
        issues,
      );
      return result;
    } catch (error) {
      final issues = monitor._actionIssues.remove(id) ?? <String>[];
      monitor._actionOutcomes.remove(id);
      final code = _safeError(error);
      if (!issues.contains(code)) issues.add(code);
      monitor._finishAction(
        id,
        safeName,
        startedAt,
        FirebaseActionOutcome.failed,
        issues,
      );
      rethrow;
    }
  }

  static void noteCurrentActionFailure(String errorCode) {
    noteCurrentActionOutcome(FirebaseActionOutcome.failed, code: errorCode);
  }

  static void noteCurrentActionOutcome(
    FirebaseActionOutcome outcome, {
    String? code,
  }) {
    final id = Zone.current[_actionKey] as int?;
    final monitor = instance;
    if (id == null || !monitor._activeActions.containsKey(id)) return;
    final previous = monitor._actionOutcomes[id];
    const priority = <FirebaseActionOutcome, int>{
      FirebaseActionOutcome.running: 0,
      FirebaseActionOutcome.completed: 1,
      FirebaseActionOutcome.skipped: 2,
      FirebaseActionOutcome.cancelled: 3,
      FirebaseActionOutcome.completedWithWarnings: 4,
      FirebaseActionOutcome.partial: 5,
      FirebaseActionOutcome.failed: 6,
    };
    if (previous == null || priority[outcome]! >= priority[previous]!) {
      monitor._actionOutcomes[id] = outcome;
    }
    if (code != null && code.isNotEmpty) {
      final safeCode = _safeSource(code);
      final issues = monitor._actionIssues.putIfAbsent(id, () => <String>[]);
      if (!issues.contains(safeCode) && issues.length < 20) {
        issues.add(safeCode);
      }
    }
  }

  void _printAction(FirebaseActivityAction action) {
    if (!DevAuth.devModeEnabled.value) return;
    try {
      debugPrint(action.debugLine);
    } catch (_) {}
  }

  void _finishAction(
    int id,
    String name,
    DateTime startedAt,
    FirebaseActionOutcome outcome,
    List<String> issues,
  ) {
    _activeActions.remove(id);
    final safeIssues = List<String>.unmodifiable(issues);
    final action = FirebaseActivityAction(
      id: id,
      name: name,
      startedAt: startedAt,
      finishedAt: DateTime.now(),
      outcome: outcome,
      errorCode: safeIssues.isEmpty ? null : safeIssues.first,
      issueCodes: safeIssues,
    );
    final index = _actions.toList().indexWhere((item) => item.id == id);
    if (index >= 0) {
      final items = _actions.toList();
      items[index] = action;
      _actions
        ..clear()
        ..addAll(items);
    }
    _printAction(action);
    _requestRefresh();
  }

  void start() {
    if (_started) return;
    _started = true;
    FirebaseActivityWriteScope.onBatchChanged = _batchChanged;
    FirebaseActivityWriteScope.onBatchCancelled = _batchCancelled;
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

  FirebaseActivityEvent _progressEvent(
    FirebaseActivityEvent previous,
    FirebaseActivityWriteCounts counts,
    FirebaseActivityStage stage, {
    String? source,
  }) =>
      FirebaseActivityEvent(
        sequence: previous.sequence,
        timestamp: previous.timestamp,
        kind: previous.kind,
        phase: FirebaseActivityPhase.started,
        source: source == null ? previous.source : _safeSource(source),
        operationId: previous.operationId,
        parentOperationId: previous.parentOperationId,
        actionId: previous.actionId,
        actionName: previous.actionName,
        counterBefore: previous.counterBefore,
        counterAfter: previous.counterAfter,
        stage: stage,
        callState: previous.callState,
        outcomeBasis: previous.outcomeBasis,
        setCommands: counts.sets,
        createCommands: counts.creates,
        updateCommands: counts.updates,
        deleteCommands: counts.deletes,
        attempts: counts.attempts,
      );

  void _publishProgress(
    int? operationId,
    FirebaseActivityWriteCounts counts,
    FirebaseActivityStage stage, {
    String? source,
  }) {
    if (operationId == null) return;
    final previous = _running[operationId];
    if (previous == null) return;
    final updated = _progressEvent(previous, counts, stage, source: source);
    _running[operationId] = updated;
    _latest = updated;
    _isIdle = false;
    _idleTimer?.cancel();
    _idleTimer = null;
    _requestRefresh();
  }

  void _markSdkFutureReturned(int operationId) {
    final previous = _running[operationId];
    if (previous == null) return;
    final updated = previous.withCallState(
      FirebaseActivityCallState.sdkFutureReturned,
    );
    _running[operationId] = updated;
    _latest = updated;
    _requestRefresh();
  }

  void _schedulePreparationExpiry(FirebaseActivityWriteCounts counts) {
    final operationId = counts.operationId;
    if (operationId == null) return;
    _preparationTimers.remove(operationId)?.cancel();
    _preparationTimers[operationId] = Timer(
      const Duration(minutes: 2),
      () {
        _preparationTimers.remove(operationId);
        if (counts.operationId != operationId ||
            !_running.containsKey(operationId)) return;
        counts.operationId = null;
        emit(
          FirebaseActivityKind.batch,
          FirebaseActivityPhase.cancelled,
          source: 'firestore.batch.preparation_stale',
          operationId: operationId,
          parentOperationId: counts.parentOperationId,
          stage: FirebaseActivityStage.stalePreparation,
          callState: FirebaseActivityCallState.notInvoked,
          commands: counts,
        );
      },
    );
  }

  void _batchChanged(FirebaseActivityWriteCounts counts) {
    if (!counts.parentCaptured) {
      counts.parentOperationId = Zone.current[_parentOperationKey] as int?;
      counts.parentCaptured = true;
    }
    var operationId = counts.operationId;
    if (operationId == null || !_running.containsKey(operationId)) {
      operationId = ++_operationSequence;
      counts.operationId = operationId;
      emit(
        FirebaseActivityKind.batch,
        FirebaseActivityPhase.started,
        source: 'firestore.batch.prepare',
        operationId: operationId,
        parentOperationId: counts.parentOperationId,
        callState: FirebaseActivityCallState.notInvoked,
        commands: counts,
        stage: FirebaseActivityStage.preparing,
      );
    }
    _publishProgress(
      operationId,
      counts,
      FirebaseActivityStage.preparing,
    );
    _schedulePreparationExpiry(counts);
  }

  void noteCallerTimeout(Object batch) {
    final counts = FirebaseActivityWriteScope.inspectBatch(batch);
    final operationId = counts?.operationId;
    if (operationId == null || counts == null) return;
    final current = _running[operationId];
    if (current == null || current.stage == FirebaseActivityStage.callerTimedOut) {
      return;
    }
    _publishProgress(
      operationId,
      counts,
      FirebaseActivityStage.callerTimedOut,
      source: 'firestore.batch.caller_timeout',
    );
  }

  static Future<T> observeCallerTimeout<T>(
    Future<T> original, {
    required Object batch,
    required Duration timeout,
  }) async {
    try {
      return await original.timeout(timeout);
    } on TimeoutException {
      instance.noteCallerTimeout(batch);
      rethrow;
    }
  }

  void _batchCancelled(FirebaseActivityWriteCounts counts) {
    final operationId = counts.operationId;
    if (operationId == null) return;
    _preparationTimers.remove(operationId)?.cancel();
    if (_running.containsKey(operationId)) {
      emit(
        FirebaseActivityKind.batch,
        FirebaseActivityPhase.cancelled,
        source: 'firestore.batch.unsubmitted',
        operationId: operationId,
        parentOperationId: counts.parentOperationId,
        callState: FirebaseActivityCallState.notInvoked,
        commands: counts,
      );
    }
    counts.operationId = null;
  }

  void emit(
    FirebaseActivityKind kind,
    FirebaseActivityPhase phase, {
    required String source,
    int? operationId,
    int? parentOperationId,
    FirebaseActivityStage? stage,
    int? durationMs,
    int? documents,
    bool? fromCache,
    bool? pendingWrites,
    String? errorCode,
    FirebaseActivityCallState? callState,
    String? outcomeBasis,
    FirebaseActivityWriteCounts? commands,
    int added = 0,
    int modified = 0,
    int removed = 0,
    int dataBytes = 0,
    int fieldCount = 0,
    int? estimatedDocuments,
    bool snapshotInitial = false,
    bool costUncertain = false,
    FirestoreReadStrategy readStrategy = FirestoreReadStrategy.unknown,
    int pointReadUnits = 0,
    int indexBytes = 0,
    int? listenerId,
    bool metadataOnly = false,
    bool reconnectCandidate = false,
    int possibleExtraReads = 0,
    String? costReason,
  }) {
    if (!_started) start();
    if (operationId != null &&
        (_finished.contains(operationId) ||
            (phase == FirebaseActivityPhase.started
                ? _running.containsKey(operationId)
                : !_running.containsKey(operationId)))) {
      return;
    }
    final zoneActionId = Zone.current[_actionKey] as int?;
    final currentActionId = zoneActionId != null &&
            _activeActions.containsKey(zoneActionId)
        ? zoneActionId
        : null;
    final actionId = currentActionId ??
        (operationId == null ? null : _operationActionIds[operationId]);
    final actionName = actionId == null
        ? null
        : _activeActions[actionId]?.name ??
            _actions.where((item) => item.id == actionId)
                .map((item) => item.name)
                .firstOrNull;
    if (operationId != null && actionId != null &&
        phase == FirebaseActivityPhase.started) {
      _operationActionIds[operationId] = actionId;
    }
    final counterBefore = firestoreOperationCount;
    final increasesCounter =
        phase == FirebaseActivityPhase.completed &&
        parentOperationId == null &&
        _isFirestoreKind(kind);
    final costBefore = cost.totalWon;
    final costUnitsBefore = cost.totalUnits;
    final uncertainBefore = cost.uncertainOperations;
    if (phase == FirebaseActivityPhase.completed) {
      if (kind == FirebaseActivityKind.read && fromCache != true) {
        cost.record(
          parentOperationId == null ? 'read' : 'transactionRead',
          count: documents ?? 1,
          bytes: dataBytes,
          fields: fieldCount,
          uncertain: costUncertain || documents == null,
          isRead: true,
          readStrategy: readStrategy,
          pointReadUnits: pointReadUnits,
          indexBytes: indexBytes,
          reason: costReason ?? 'sdk_read_result',
        );
      } else if (kind == FirebaseActivityKind.set ||
          kind == FirebaseActivityKind.create ||
          kind == FirebaseActivityKind.update ||
          kind == FirebaseActivityKind.delete ||
          kind == FirebaseActivityKind.write) {
        cost.record(kind.name, count: 1, bytes: dataBytes,
          fields: fieldCount, uncertain: costUncertain || dataBytes == 0,
          reason: dataBytes == 0 ? 'write_size_unobserved' : 'write_payload_size');
      } else if (kind == FirebaseActivityKind.batch ||
          kind == FirebaseActivityKind.transaction) {
        final prefix = kind == FirebaseActivityKind.batch
            ? 'batch'
            : 'transaction';
        final count = (commands?.sets ?? 0) + (commands?.creates ?? 0) +
            (commands?.updates ?? 0);
        final deletes = commands?.deletes ?? 0;
        final estimatedBytes = commands?.dataBytes ?? 0;
        final estimatedFields = commands?.dataFields ?? 0;
        final allMetrics = commands?.metrics ?? const <FirestoreWriteMetric>[];
        final writes = allMetrics.where((metric) =>
            metric.kind != FirebaseActivityDocumentCommand.delete).toList();
        final deletionMetrics = allMetrics.where((metric) =>
            metric.kind == FirebaseActivityDocumentCommand.delete).toList();
        if (count > 0) {
          cost.record('${prefix}Write', count: count,
            bytes: estimatedBytes, fields: estimatedFields,
            writeMetrics: writes.length == count ? writes : null,
            uncertain: writes.length != count ||
                writes.any((metric) => !metric.sizeKnown) ||
                kind == FirebaseActivityKind.transaction,
            reason: 'command_level_write_estimate');
        }
        if (deletes > 0) {
          cost.record('${prefix}Delete', count: deletes,
            writeMetrics: deletionMetrics.length == deletes ? deletionMetrics : null,
            uncertain: deletionMetrics.any((metric) => !metric.sizeKnown) ||
                deletionMetrics.length != deletes,
            reason: 'command_level_delete_estimate');
        }
      }
    } else if (kind == FirebaseActivityKind.snapshot &&
        phase == FirebaseActivityPhase.received &&
        fromCache == false && pendingWrites != true &&
        estimatedDocuments != null) {
      cost.record('snapshot', count: estimatedDocuments,
        bytes: dataBytes, fields: fieldCount,
        initialSnapshot: snapshotInitial,
        uncertain: costUncertain,
        readStrategy: readStrategy,
        pointReadUnits: pointReadUnits,
        possibleExtraReads: possibleExtraReads,
        unknownRemoved: possibleExtraReads,
        reconnectCandidate: reconnectCandidate,
        metadataOnly: metadataOnly,
        reason: costReason ?? 'listener_server_event');
    }
    final event = FirebaseActivityEvent(
      sequence: ++_sequence,
      timestamp: DateTime.now(),
      kind: kind,
      phase: phase,
      source: _safeSource(source),
      operationId: operationId,
      parentOperationId: parentOperationId,
      actionId: actionId,
      actionName: actionName,
      counterBefore: increasesCounter ? counterBefore : null,
      counterAfter: increasesCounter ? counterBefore + 1 : null,
      stage: stage,
      durationMs: durationMs,
      documents: documents,
      fromCache: fromCache,
      pendingWrites: pendingWrites,
      errorCode: errorCode,
      callState: callState,
      outcomeBasis: outcomeBasis,
      setCommands: commands?.sets ?? 0,
      createCommands: commands?.creates ?? 0,
      updateCommands: commands?.updates ?? 0,
      deleteCommands: commands?.deletes ?? 0,
      attempts: commands?.attempts ?? 0,
      added: added,
      modified: modified,
      removed: removed,
      dataBytes: dataBytes,
      fieldCount: fieldCount,
      estimatedWon: cost.totalWon - costBefore,
      estimatedUnits: cost.totalUnits - costUnitsBefore,
      costUncertain: costUncertain || cost.uncertainOperations > uncertainBefore,
      listenerId: listenerId,
      costReason: costReason,
      metadataOnly: metadataOnly,
      reconnectCandidate: reconnectCandidate,
      possibleExtraReads: possibleExtraReads,
      readStrategy: readStrategy,
    );
    if (operationId != null) {
      if (phase != FirebaseActivityPhase.started) {
        _preparationTimers.remove(operationId)?.cancel();
      }
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
      if (increasesCounter) {
        _firestoreOperationCount++;
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
    if (phase == FirebaseActivityPhase.outcomeUnknown) _unknownOutcomeCount++;
    if (phase == FirebaseActivityPhase.cancelled) {
      if (stage == FirebaseActivityStage.stalePreparation) {
        _stalePreparationCount++;
      } else {
        _abandonedBatchCount++;
      }
    }
    if (operationId != null && phase != FirebaseActivityPhase.started) {
      _operationActionIds.remove(operationId);
    }
    if (increasesCounter) {
      assert(firestoreOperationCount == counterBefore + 1);
      _counterIncrements.addLast(event);
      while (_counterIncrements.length > maxCounterIncrements) {
        _counterIncrements.removeFirst();
      }
    }
    _events.addLast(event);
    while (_events.length > maxEvents) {
      _events.removeFirst();
    }
    _latest = event;
    _isIdle = false;
    _scheduleIdle();
    if (DevAuth.devModeEnabled.value) {
      try {
        debugPrint(event.debugLine);
      } catch (_) {}
    }
    _requestRefresh();
  }

  static void beginTransactionAttempt() {
    final scope = Zone.current[_transactionScopeKey];
    if (scope is! FirebaseActivityWriteCounts) return;
    scope.resetAttempt();
    final operationId = Zone.current[_transactionOperationKey] as int?;
    instance._publishProgress(
      operationId,
      scope,
      scope.attempts > 1
          ? FirebaseActivityStage.retrying
          : FirebaseActivityStage.attempting,
    );
  }

  static void transactionCommand(
    FirebaseActivityDocumentCommand kind,
    void Function() execute, {
    int documentBytes = 0,
    int fieldCount = 0,
    Object? documentData,
    String? documentPath,
    int indexWriteUnits = 0,
  }) {
    execute();
    final scope = Zone.current[_transactionScopeKey];
    if (scope is! FirebaseActivityWriteCounts) return;
    final size = documentData == null ? null
        : FirestoreDocumentSizer.document(documentPath ?? '', documentData);
    scope.add(kind,
        bytes: size?.bytes ?? documentBytes,
        fields: size?.fieldCount ?? fieldCount,
        sizeKnown: size != null || documentBytes > 0,
        documentPath: documentPath,
        indexWriteUnits: indexWriteUnits);
    final operationId = Zone.current[_transactionOperationKey] as int?;
    instance._publishProgress(
      operationId,
      scope,
      scope.attempts > 1
          ? FirebaseActivityStage.retrying
          : FirebaseActivityStage.attempting,
    );
  }

  static Future<T> track<T>(
    FirebaseActivityKind kind,
    Future<T> Function() execute, {
    required String source,
    Object? batch,
    Object? writeData,
    String? writeDocumentPath,
    FirestoreReadStrategy readStrategy = FirestoreReadStrategy.unknown,
    int indexBytes = 0,
  }) async {
    final monitor = instance;
    final batchCounts = kind == FirebaseActivityKind.batch
        ? FirebaseActivityWriteScope.inspectBatch(batch)
        : null;
    final preparedId = batchCounts?.operationId;
    final prepared = preparedId != null && monitor._running.containsKey(preparedId);
    final operationId = prepared ? preparedId : ++monitor._operationSequence;
    final parentOperationId = kind == FirebaseActivityKind.batch &&
            batchCounts != null && batchCounts.parentCaptured
        ? batchCounts.parentOperationId
        : Zone.current[_parentOperationKey] as int?;
    final transactionScope = kind == FirebaseActivityKind.transaction
        ? FirebaseActivityWriteCounts()
        : null;
    if (prepared && batchCounts != null) {
      monitor._preparationTimers.remove(operationId)?.cancel();
    } else {
      monitor.emit(kind, FirebaseActivityPhase.started,
          source: source,
          operationId: operationId,
          parentOperationId: parentOperationId,
          callState: FirebaseActivityCallState.notInvoked,
          commands: batchCounts,
          stage: kind == FirebaseActivityKind.batch
              ? FirebaseActivityStage.preparing
              : kind == FirebaseActivityKind.transaction
                  ? FirebaseActivityStage.attempting
                  : null);
    }
    final stopwatch = Stopwatch()..start();
    var sdkFutureReturned = false;
    late T result;
    try {
      final original = runZoned<Future<T>>(
        execute,
        zoneValues: <Object, Object>{
          _parentOperationKey: operationId,
          if (transactionScope != null) _transactionScopeKey: transactionScope,
          if (transactionScope != null) _transactionOperationKey: operationId,
        },
      );
      sdkFutureReturned = true;
      if (kind == FirebaseActivityKind.batch) {
        FirebaseActivityWriteScope.markSubmitted(batch);
        if (batchCounts != null) {
          try {
            monitor._publishProgress(
              operationId,
              batchCounts,
              FirebaseActivityStage.submitting,
              source: source,
            );
          } catch (error) {
            _diagnoseTelemetryFailure(error);
          }
        }
      }
      try {
        monitor._markSdkFutureReturned(operationId);
      } catch (error) {
        _diagnoseTelemetryFailure(error);
      }
      result = await original;
    } catch (error) {
      StatusDialog.recordFirestoreIndexError(error);
      stopwatch.stop();
      try {
        final commands = kind == FirebaseActivityKind.batch
            ? FirebaseActivityWriteScope.takeBatch(batch)
            : transactionScope?.copy();
        final phase = _classifyError(kind, error, sdkFutureReturned);
        monitor.emit(kind, phase,
            source: source,
            operationId: operationId,
            parentOperationId: parentOperationId,
            durationMs: stopwatch.elapsedMilliseconds,
            commands: commands,
            callState: sdkFutureReturned
                ? FirebaseActivityCallState.sdkFutureReturned
                : FirebaseActivityCallState.notInvoked,
            outcomeBasis: _outcomeBasis(kind, error, sdkFutureReturned, phase),
            errorCode: _safeError(error));
      } catch (observationError) {
        _diagnoseTelemetryFailure(observationError);
      }
      rethrow;
    }
    stopwatch.stop();
    try {
      final metadata = _snapshotMetadata(result);
      final size = kind == FirebaseActivityKind.read
          ? FirestoreDocumentSizer.fromSnapshot(result)
          : writeData == null
              ? const FirestoreSizeEstimate(bytes: 0, fieldCount: 0, documents: 0)
              : FirestoreDocumentSizer.document(writeDocumentPath ?? '', writeData);
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
          dataBytes: size.bytes,
          fieldCount: size.fieldCount,
          pointReadUnits: size.pointReadUnits,
          readStrategy: result is DocumentSnapshot ? FirestoreReadStrategy.pointRead : readStrategy,
          indexBytes: indexBytes,
          costUncertain: kind == FirebaseActivityKind.read &&
              (metadata.$1 == null || result is QuerySnapshot ||
                  (FirebaseActivityCostEstimator.enterprise &&
                      readStrategy == FirestoreReadStrategy.unknown)),
          callState: FirebaseActivityCallState.sdkFutureReturned,
          commands: commands);
    } catch (observationError) {
      _diagnoseTelemetryFailure(observationError);
    }
    return result;
  }

  static bool _isWriteKind(FirebaseActivityKind kind) =>
      kind == FirebaseActivityKind.write ||
      kind == FirebaseActivityKind.set ||
      kind == FirebaseActivityKind.create ||
      kind == FirebaseActivityKind.update ||
      kind == FirebaseActivityKind.delete ||
      kind == FirebaseActivityKind.batch ||
      kind == FirebaseActivityKind.transaction;

  static const Set<String> _confirmedRejectionCodes = <String>{
    'permission-denied',
    'unauthenticated',
    'invalid-argument',
    'failed-precondition',
    'already-exists',
    'not-found',
  };

  static FirebaseActivityPhase _classifyError(
    FirebaseActivityKind kind,
    Object error,
    bool sdkFutureReturned,
  ) {
    if (!_isWriteKind(kind)) return FirebaseActivityPhase.failed;
    if (error is FirebaseException &&
        _confirmedRejectionCodes.contains(error.code)) {
      return FirebaseActivityPhase.failed;
    }
    if (!sdkFutureReturned && error is StateError) {
      return FirebaseActivityPhase.failed;
    }
    return FirebaseActivityPhase.outcomeUnknown;
  }

  static String _outcomeBasis(
    FirebaseActivityKind kind,
    Object error,
    bool sdkFutureReturned,
    FirebaseActivityPhase phase,
  ) {
    if (!_isWriteKind(kind)) return 'non_write_error';
    if (phase == FirebaseActivityPhase.failed) {
      return sdkFutureReturned
          ? 'sdk_confirmed_rejection'
          : 'local_invocation_rejection';
    }
    if (!sdkFutureReturned) return 'sdk_future_not_returned';
    if (error is TimeoutException) return 'sdk_timeout_unverified';
    if (error is FirebaseException) return 'sdk_error_unverified';
    return 'async_error_unverified';
  }

  static void _diagnoseTelemetryFailure(Object error) {
    if (!DevAuth.devModeEnabled.value) return;
    try {
      debugPrint('[FIREBASE_ACTIVITY] telemetryFailure=${_safeSource(error.runtimeType.toString())}');
    } catch (_) {}
  }

  static Stream<T> observe<T>(Stream<T> source, {required String origin}) {
    return source.transform(StreamTransformer<T, T>.fromBind((stream) {
      final listener = FirebaseActivityListenerState(
        ++_listenerSequence, _safeSource(origin));
      return stream.transform(StreamTransformer<T, T>.fromHandlers(
        handleData: (event, sink) {
          try {
            final metadata = _snapshotMetadata(event);
            final assessment = listener.examine(event);
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
              dataBytes: assessment.server && !assessment.metadataOnly ? assessment.size.bytes : 0,
              fieldCount: assessment.server && !assessment.metadataOnly ? assessment.size.fieldCount : 0,
              pointReadUnits: assessment.size.pointReadUnits,
              estimatedDocuments: assessment.server
                  ? assessment.billableDocuments : null,
              snapshotInitial: assessment.initial || assessment.reconnectCandidate,
              costUncertain: assessment.unknownRemoved > 0 ||
                  assessment.reconnectCandidate ||
                  (assessment.server && assessment.billableDocuments > 0),
              readStrategy: event is DocumentSnapshot
                  ? FirestoreReadStrategy.pointRead
                  : FirestoreReadStrategy.unknown,
              listenerId: listener.id,
              metadataOnly: assessment.metadataOnly,
              reconnectCandidate: assessment.reconnectCandidate,
              possibleExtraReads: assessment.unknownRemoved,
              costReason: assessment.reason,
            );
          } catch (error) {
            _diagnoseTelemetryFailure(error);
          }
          sink.add(event);
        },
        handleError: (Object error, StackTrace stackTrace, sink) {
          StatusDialog.recordFirestoreIndexError(error);
          instance.emit(
            FirebaseActivityKind.snapshot,
            FirebaseActivityPhase.failed,
            source: origin,
            errorCode: _safeError(error),
            listenerId: listener.id,
          );
          sink.addError(error, stackTrace);
        },
      ));
    }));
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

  static String _safeActionName(String value) {
    final safe = value.replaceAll(RegExp(r'[\r\n\t]'), ' ').trim();
    return safe.length > 80 ? safe.substring(0, 80) : safe;
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

  static bool _isFirestoreKind(FirebaseActivityKind kind) => switch (kind) {
        FirebaseActivityKind.read ||
        FirebaseActivityKind.write ||
        FirebaseActivityKind.set ||
        FirebaseActivityKind.create ||
        FirebaseActivityKind.update ||
        FirebaseActivityKind.delete ||
        FirebaseActivityKind.batch ||
        FirebaseActivityKind.transaction => true,
        _ => false,
      };

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

  String debugPrintCodeForCounterIncrements(
    Iterable<FirebaseActivityEvent> selected,
  ) => <String>[
        'debugPrint(${jsonEncode('[FIREBASE_COUNTER] scope=firestore current=$firestoreOperationCount '
            'retained=${_counterIncrements.length} omitted=$omittedCounterIncrements')});',
        ...selected.map(debugPrintCodeForEvent),
      ].join('\n');

  String debugPrintCodeForActions(Iterable<FirebaseActivityAction> selected) {
    final actions = selected.toList(growable: false);
    final ids = actions.map((item) => item.id).toSet();
    final related = _events.where((event) => ids.contains(event.actionId)).toList()
      ..sort((a, b) => a.sequence.compareTo(b.sequence));
    return <String>[
      ...actions.map((action) => 'debugPrint(${jsonEncode(action.debugLine)});'),
      ...related.map(debugPrintCodeForEvent),
    ].join('\n');
  }

  String get costDebugPrintCode => <String>[
        'debugPrint(${jsonEncode('[FIREBASE_COST] estimatedWon=${cost.totalWon.toStringAsFixed(8)} '
            'edition=${FirebaseActivityBillingConfig.editionLabel} '
            'region=${FirebaseActivityBillingConfig.region} '
            'reference=${FirebaseActivityBillingConfig.priceReference} '
            'krwPerUsd=${FirebaseActivityBillingConfig.krwPerUsd} '
            'rateDate=${FirebaseActivityBillingConfig.exchangeRateReference} '
            'unknown=${cost.uncertainOperations} '
            'knownBytes=${cost.knownBytes} knownFields=${cost.knownFields} '
            'freeQuotaApplied=false billingAmount=false '
            'settings=${FirebaseActivityBillingConfig.confidenceLabel} '
            'pricingDate=${FirebaseActivityBillingConfig.pricingDate} '
            'possibleExtraWon=${cost.possibleExtraWon.toStringAsFixed(8)} '
            'unknownRemoved=${cost.unknownRemoved} '
            'reconnectCandidates=${cost.reconnectCandidates} '
            'metadataOnlyEvents=${cost.metadataOnlyEvents}')});',
        ...cost.summaries.map((row) =>
            'debugPrint(${jsonEncode('[FIREBASE_COST_KIND] type=${row.label} '
                'units=${row.units} estimatedWon=${row.won.toStringAsFixed(8)}')});'),
        ...cost.recent.map((entry) =>
            'debugPrint(${jsonEncode('[FIREBASE_COST_ENTRY] type=${entry.kind} '
                'units=${entry.units} bytes=${entry.bytes} fields=${entry.fields} '
                'estimatedWon=${entry.won.toStringAsFixed(8)} '
                'possibleExtraUnits=${entry.possibleExtraUnits} '
                'possibleExtraWon=${entry.possibleExtraWon.toStringAsFixed(8)} '
                'uncertain=${entry.uncertain} reason=${entry.reason}')});'),
      ].join('\n');

  String get debugPrintCode => <String>[
        costDebugPrintCode,
        debugPrintCodeFor(_events),
      ].join('\n');

  String get summary =>
      '앱 시작 이후 상위 작업 완료 $_topLevelCompletedCount회 · '
      '내부 계측 완료 $_nestedCompletedCount회 · Snapshot $_snapshotReceivedCount회 · '
      '상단 Firestore 완료 $firestoreOperationCount회 · '
      '전체 상위 완료·Snapshot 수신 합계 $totalActivityCount회 · '
      '초기화 완료 ${count(FirebaseActivityKind.initialization)}회 · '
      '인증 완료 ${count(FirebaseActivityKind.authentication)}회 · '
      'Storage 완료 ${count(FirebaseActivityKind.storage)}회 · '
      '읽기 호출 완료 ${count(FirebaseActivityKind.read)}회 · '
      '조회 결과 문서 수 $_readResultDocumentCount건(캐시 포함) · '
      'set/upsert 성공 $_setCommandCount건 · 생성 분류 성공 $_createCommandCount건 · '
      '수정 명령 성공 $_updateCommandCount건 · 삭제 명령 성공 $_deleteCommandCount건 · '
      '분류 가능 성공 문서 명령 $documentCommandCount건 · '
      '종류 미분류 쓰기 완료 ${count(FirebaseActivityKind.write)}회 · '
      'Batch ${count(FirebaseActivityKind.batch)}회 · '
      'Transaction ${count(FirebaseActivityKind.transaction)}회 · '
      '진행 중 $activeOperationCount건(상위 $topLevelActiveOperationCount, 내부 $nestedActiveOperationCount) · '
      '실패 $_failedEventCount회 · 결과 미확정 $_unknownOutcomeCount회 · '
      '미제출 중단 $_abandonedBatchCount회 · 준비 표시 만료 $_stalePreparationCount회\n'
      '최근 기록 ${_events.length}건 / 최대 $maxEvents건 · '
      'Snapshot에는 캐시 및 로컬 이벤트가 포함될 수 있습니다. '
      '미분류 쓰기 호출은 분류 가능 문서 명령 합계에서 제외됩니다. '
      '커밋 응답이 불명확하면 결과 미확정으로 별도 집계합니다. '
      'Firestore 완료 작업 수는 실제 과금 건수가 아닙니다. '
      '앱 관측 예상 사용요금 ${FirebaseActivityCostEstimator.formatWon(cost.totalWon)}(무료할당량 미적용, 청구액 아님).';

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _idleTimer?.cancel();
    for (final timer in _preparationTimers.values) {
      timer.cancel();
    }
    _preparationTimers.clear();
    FirebaseActivityWriteScope.onBatchChanged = null;
    FirebaseActivityWriteScope.onBatchCancelled = null;
    super.dispose();
  }
}
