import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import '../../features/selector/application/dev_auth.dart';
import '../../shared/notification/work_status_notification_protocol.dart';
import '../utils/status_dialog.dart';
import '../di/routes.dart';
import 'app_navigator.dart';
import '../live_work_diagnostics.dart';
import '../live_work_overdue_notification_service.dart';
import '../live_work_overdue_reminder_coordinator.dart';
import '../live_work_overdue_reminder_policy.dart';
import '../live_work_overdue_reminder_store.dart';
import '../live_work_notification_presenter.dart';
import '../live_work_snapshot_resolver.dart';
import 'foreground_entrypoints.dart';


@immutable
class ForegroundServiceEnsureResult {
  const ForegroundServiceEnsureResult({
    required this.running,
    required this.startedNow,
    required this.source,
  });

  final bool running;
  final bool startedNow;
  final String source;
}

@immutable
class WorkStatusNotificationSnapshot {
  const WorkStatusNotificationSnapshot({
    required this.isWorking,
    required this.title,
    required this.text,
    required this.shortText,
    required this.overdue,
    required this.overdueMinutes,
    required this.serviceRunning,
    required this.notificationPersistent,
    required this.source,
    required this.updatedAt,
  });

  const WorkStatusNotificationSnapshot.initial()
      : isWorking = false,
        title = '업무 대기 중',
        text = '근무 시작을 기다리고 있습니다.',
        shortText = '대기',
        overdue = false,
        overdueMinutes = 0,
        serviceRunning = false,
        notificationPersistent = false,
        source = 'initial',
        updatedAt = null;

  final bool isWorking;
  final String title;
  final String text;
  final String shortText;
  final bool overdue;
  final int overdueMinutes;
  final bool serviceRunning;
  final bool notificationPersistent;
  final String source;
  final DateTime? updatedAt;

  WorkStatusNotificationSnapshot copyWith({
    bool? isWorking,
    String? title,
    String? text,
    String? shortText,
    bool? overdue,
    int? overdueMinutes,
    bool? serviceRunning,
    bool? notificationPersistent,
    String? source,
    DateTime? updatedAt,
  }) {
    return WorkStatusNotificationSnapshot(
      isWorking: isWorking ?? this.isWorking,
      title: title ?? this.title,
      text: text ?? this.text,
      shortText: shortText ?? this.shortText,
      overdue: overdue ?? this.overdue,
      overdueMinutes: overdueMinutes ?? this.overdueMinutes,
      serviceRunning: serviceRunning ?? this.serviceRunning,
      notificationPersistent:
          notificationPersistent ?? this.notificationPersistent,
      source: source ?? this.source,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

class WorkStatusNotificationController {
  WorkStatusNotificationController._();

  static const String initialRoute = AppRoutes.headquarterPage;
  static const int foregroundServiceId = 42101;
  static const String notificationChannelId = 'parkinworkin_work_status_v1';
  static const MethodChannel _notificationControlChannel =
      MethodChannel('com.quintus.dev/work_status_notification');
  static const String notificationChannelName = '근무 상태';
  static const String notificationChannelDescription =
      'ParkinWorkin 근무 상태를 표시합니다.';
  static const int maxDebugLines = 240;
  static const String foregroundServiceTypeLabel = 'specialUse';

  static final ValueNotifier<WorkStatusNotificationSnapshot> status =
      ValueNotifier<WorkStatusNotificationSnapshot>(
    const WorkStatusNotificationSnapshot.initial(),
  );
  static final List<String> _debugLines = <String>[];

  static bool _foregroundTaskInitialized = false;
  static bool _taskEventListenerReady = false;
  static bool _refreshInFlight = false;
  static bool _refreshQueued = false;
  static String _queuedSource = 'queued';
  static int _recoveryAttempts = 0;
  static int _recoverySuccesses = 0;
  static bool _lastEnsureStartedNow = false;
  static String _lastEnsureSource = '-';
  static String _lastLifecycleAction = 'initial';
  static int _taskNotificationRefreshedCount = 0;
  static DateTime? _lastTaskNotificationRefreshedAt;
  static String _lastTaskNotificationRefreshedTimestamp = '-';
  static int _notificationPinAttempts = 0;
  static int _notificationPinSuccesses = 0;
  static int _notificationDismissCount = 0;
  static int _notificationRestoreAttempts = 0;
  static int _notificationRestoreSuccesses = 0;
  static DateTime? _lastNotificationDismissedAt;
  static int? _lastPinnedNotificationId;
  static String _lastPersistenceAction = 'initial';
  static bool _dismissRestoreInFlight = false;
  static bool _pendingWorkScreenNavigation = false;
  static String _lastNavigationRequest = '-';
  static String _lastNavigationHandled = '-';
  static String _lastNavigationRequestSource = '-';
  static String _lastNavigationSuppressedReason = '-';
  static DateTime? _lastNavigationRequestAt;
  static DateTime? _lastNavigationHandledAt;
  static bool _workScreenRequestReceived = false;
  static DateTime? _lastWorkScreenRequestAt;
  static String _lastWorkScreenRequestSource = '-';
  static bool _workScreenNavigationInFlight = false;
  static bool _breakActionReceived = false;
  static DateTime? _lastBreakActionAt;
  static String _lastBreakActionPhase = '-';
  static String _lastBreakPunchResult = '-';
  static String _lastBreakPunchMessage = '-';
  static String _lastBreakRecordedAt = '-';
  static int _notificationRecoveryCount = 0;
  static String _lastNotificationRecoveryReason = '-';
  static DateTime? _lastNotificationRecoveryAt;
  static bool _notificationRecoveryInProgress = false;
  static String _lastNotificationRecoveryStage = '-';
  static String _lastNotificationRecoveryResult = '-';
  static int _forcedNotificationRecoveryCount = 0;
  static DateTime? _lastForcedNotificationRecoveryAt;
  static bool? _lastNotificationFound;

  static List<String> get debugLines =>
      List<String>.unmodifiable(_debugLines);

  static String get debugPrintCode {
    if (_debugLines.isEmpty) {
      return 'debugPrint(${jsonEncode('[WORK_STATUS_NOTIFICATION] 기록된 로그가 없습니다.')});';
    }
    return _debugLines
        .map((line) => 'debugPrint(${jsonEncode(line)});')
        .join('\n');
  }

  static void initializeForegroundTask() {
    if (_foregroundTaskInitialized) return;
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: notificationChannelId,
        channelName: notificationChannelName,
        channelDescription: notificationChannelDescription,
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
        enableVibration: false,
        playSound: false,
        showWhen: false,
        showBadge: false,
        onlyAlertOnce: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: false,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.repeat(60000),
        autoRunOnBoot: false,
        autoRunOnMyPackageReplaced: false,
        allowWakeLock: true,
        allowWifiLock: false,
      ),
    );
    _foregroundTaskInitialized = true;
    _log(
      'foreground_task_initialized channel=$notificationChannelId serviceId=$foregroundServiceId serviceTypes=$foregroundServiceTypeLabel importance=LOW priority=LOW sound=false vibration=false onlyAlertOnce=true',
    );
  }

  static void initializeTaskEventListener() {
    if (_taskEventListenerReady) return;
    _taskEventListenerReady = true;
    FlutterForegroundTask.addTaskDataCallback(_onTaskData);
    LiveWorkOverdueNotificationService.instance.setOpenWorkScreenHandler(
      _handleOverdueOpenWorkScreen,
    );
    unawaited(
      LiveWorkOverdueNotificationService.instance.initializeForMainIsolate(),
    );
    _log('task_event_listener_ready');
  }

  static void flushPendingNavigation() {
    if (!_pendingWorkScreenNavigation) return;
    _navigateToWorkScreen(source: 'pending_flush');
  }

  static Future<ForegroundServiceEnsureResult> ensureServiceState({
    String source = 'ensure_service',
  }) async {
    initializeForegroundTask();
    final presentation = await _loadPresentation();
    final running = await _safeIsRunningService();
    _publish(
      presentation,
      serviceRunning: running,
      source: source,
    );

    if (!presentation.isWorking) {
      await _stopServiceForInactiveWork(
        source: source,
        presentation: presentation,
        runningBefore: running,
      );
      _lastEnsureStartedNow = false;
      _lastEnsureSource = source;
      return ForegroundServiceEnsureResult(
        running: status.value.serviceRunning,
        startedNow: false,
        source: source,
      );
    }

    try {
      if (running) {
        await FlutterForegroundTask.updateService(
          notificationTitle: presentation.title,
          notificationText: presentation.text,
          notificationButtons: _notificationButtons(presentation),
          notificationInitialRoute: initialRoute,
        );
        final persistent = await _pinPersistentNotification(
          source: '${source}_reuse',
          presentation: presentation,
        );
        _publish(
          presentation,
          serviceRunning: true,
          notificationPersistent: persistent,
          source: source,
        );
        _lastEnsureStartedNow = false;
        _lastEnsureSource = source;
        _lastLifecycleAction = 'active_service_reused';
        _log(
          'service_ensure_reused source=$source working=${presentation.isWorking} title=${jsonEncode(presentation.title)} text=${jsonEncode(presentation.text)}',
        );
        return ForegroundServiceEnsureResult(
          running: true,
          startedNow: false,
          source: source,
        );
      }

      await FlutterForegroundTask.startService(
        serviceId: foregroundServiceId,
        serviceTypes: <ForegroundServiceTypes>[
          ForegroundServiceTypes.specialUse,
        ],
        notificationTitle: presentation.title,
        notificationText: presentation.text,
        notificationButtons: _notificationButtons(presentation),
        notificationInitialRoute: initialRoute,
        callback: myForegroundCallback,
      );
      _log(
        'service_start_requested source=$source working=${presentation.isWorking} serviceTypes=$foregroundServiceTypeLabel title=${jsonEncode(presentation.title)} text=${jsonEncode(presentation.text)}',
      );

      for (var attempt = 1; attempt <= 4; attempt++) {
        final started = await _safeIsRunningService();
        _log('service_verify source=$source attempt=$attempt running=$started');
        if (started) {
          final persistent = await _pinPersistentNotification(
            source: '${source}_start',
            presentation: presentation,
          );
          _publish(
            presentation,
            serviceRunning: true,
            notificationPersistent: persistent,
            source: source,
          );
          _lastEnsureStartedNow = true;
          _lastEnsureSource = source;
          _lastLifecycleAction = 'active_service_started';
          _log('service_ensure_started source=$source attempt=$attempt');
          return ForegroundServiceEnsureResult(
            running: true,
            startedNow: true,
            source: source,
          );
        }
        if (attempt < 4) {
          await Future<void>.delayed(const Duration(milliseconds: 120));
        }
      }

      _publish(
        presentation,
        serviceRunning: false,
        source: source,
      );
      _lastEnsureStartedNow = false;
      _lastEnsureSource = source;
      _log('service_start_failed source=$source reason=verify_false');
      return ForegroundServiceEnsureResult(
        running: false,
        startedNow: false,
        source: source,
      );
    } catch (error, stackTrace) {
      final serviceRunning = await _safeIsRunningService();
      _publish(
        presentation,
        serviceRunning: serviceRunning,
        source: source,
      );
      _lastEnsureStartedNow = false;
      _lastEnsureSource = source;
      _log('service_start_error source=$source error=$error');
      _log('service_start_stack source=$source stack=$stackTrace');
      return ForegroundServiceEnsureResult(
        running: serviceRunning,
        startedNow: false,
        source: source,
      );
    }
  }

  static Future<bool> ensureServiceRunning({
    String source = 'ensure_service',
  }) async {
    final result = await ensureServiceState(source: source);
    return result.running;
  }

  static Future<bool> refresh({
    String source = 'refresh',
  }) async {
    initializeForegroundTask();
    if (_refreshInFlight) {
      _refreshQueued = true;
      _queuedSource = source;
      _log('refresh_queued source=$source');
      return true;
    }

    _refreshInFlight = true;
    var result = true;
    try {
      var activeSource = source;
      do {
        _refreshQueued = false;
        final presentation = await _loadPresentation();
        final running = await _safeIsRunningService();
        _publish(
          presentation,
          serviceRunning: running,
          source: activeSource,
        );

        if (!presentation.isWorking) {
          final stopped = await _stopServiceForInactiveWork(
            source: activeSource,
            presentation: presentation,
            runningBefore: running,
          );
          result = result && stopped;
        } else if (!running) {
          _log(
            'refresh_service_missing source=$activeSource working=${presentation.isWorking}',
          );
          final recovered = await _recoverService(
            source: '${activeSource}_missing',
          );
          result = result && recovered;
        } else {
          try {
            await FlutterForegroundTask.updateService(
              notificationTitle: presentation.title,
              notificationText: presentation.text,
              notificationButtons: _notificationButtons(presentation),
              notificationInitialRoute: initialRoute,
            );
            final persistent = await _pinPersistentNotification(
              source: '${activeSource}_refresh',
              presentation: presentation,
            );
            _publish(
              presentation,
              serviceRunning: true,
              notificationPersistent: persistent,
              source: activeSource,
            );
            _lastLifecycleAction = 'active_notification_refreshed';
            _log(
              'refresh_complete source=$activeSource working=${presentation.isWorking} title=${jsonEncode(presentation.title)} text=${jsonEncode(presentation.text)}',
            );
          } catch (error, stackTrace) {
            _log('refresh_update_error source=$activeSource error=$error');
            _log('refresh_update_stack source=$activeSource stack=$stackTrace');
            final stillRunning = await _safeIsRunningService();
            if (stillRunning) {
              result = false;
              _publish(
                presentation,
                serviceRunning: true,
                source: activeSource,
              );
              _log(
                'refresh_update_failed_service_alive source=$activeSource restart_skipped=true',
              );
            } else {
              final recovered = await _recoverService(
                source: '${activeSource}_update_failure',
              );
              result = result && recovered;
            }
          }
        }

        if (_refreshQueued) {
          activeSource = _queuedSource;
        }
      } while (_refreshQueued);
    } finally {
      _refreshInFlight = false;
    }
    return result;
  }

  static void recordLifecycle(AppLifecycleState state) {
    _log('app_lifecycle state=${state.name}');
  }

  static Future<void> reconcileOnResume({
    String source = 'app_lifecycle_resumed',
  }) async {
    initializeForegroundTask();
    final presentation = await _loadPresentation();
    if (!presentation.isWorking) {
      _log('resume_reconcile_skipped source=$source reason=not_working');
      return;
    }
    final running = await _safeIsRunningService();
    if (!running) {
      _log('resume_reconcile_recovery source=$source reason=service_missing');
      await refresh(source: '${source}_service_missing');
      return;
    }
    final persistent = await _pinPersistentNotification(
      source: '${source}_inspect',
      presentation: presentation,
    );
    _lastLifecycleAction =
        persistent ? 'resume_notification_healthy' : 'resume_notification_missing';
    _publish(
      presentation,
      serviceRunning: true,
      notificationPersistent: persistent,
      source: source,
    );
    _log(
      'resume_reconcile_complete source=$source running=true persistent=$persistent',
    );
  }

  static Future<void> showDeveloperStatus(BuildContext context) async {
    final developerMode = await DevAuth.isDevModeEnabled();
    if (!developerMode || !context.mounted) return;

    final current = status.value;
    final serviceRunning = await _safeIsRunningService();
    final liveSnapshot = await LiveWorkSnapshotResolver.resolve();
    final reminderState = await LiveWorkOverdueReminderStore.read();
    final currentReminderSlot =
        LiveWorkOverdueReminderPolicy.currentSlot(liveSnapshot);
    final nextReminderSlot =
        LiveWorkOverdueReminderPolicy.nextSlot(liveSnapshot);
    _log(
      'developer_status_open working=${current.isWorking} serviceRunning=$serviceRunning source=${current.source}',
    );

    await HapticFeedback.mediumImpact();
    if (!context.mounted) return;

    final updatedAt = current.updatedAt?.toIso8601String() ?? '-';
    final description = <String>[
      'working=${current.isWorking}',
      'serviceRunning=$serviceRunning',
      'notificationPersistent=${current.notificationPersistent}',
      'foregroundTaskInitialized=$_foregroundTaskInitialized',
      'channel=$notificationChannelId',
      'serviceTypes=$foregroundServiceTypeLabel',
      'title=${current.title}',
      'text=${current.text}',
      'source=${current.source}',
      'updatedAt=$updatedAt',
      'route=$initialRoute',
      'recoveryAttempts=$_recoveryAttempts',
      'recoverySuccesses=$_recoverySuccesses',
      'lastEnsureStartedNow=$_lastEnsureStartedNow',
      'lastEnsureSource=$_lastEnsureSource',
      'lifecycleAllowed=${current.isWorking}',
      'lifecycleState=${current.isWorking ? 'active' : 'inactive'}',
      'lastLifecycleAction=$_lastLifecycleAction',
      'taskNotificationRefreshedCount=$_taskNotificationRefreshedCount',
      'lastTaskNotificationRefreshedAt=${_lastTaskNotificationRefreshedAt?.toIso8601String() ?? '-'}',
      'lastTaskNotificationRefreshedTimestamp=$_lastTaskNotificationRefreshedTimestamp',
      'taskNotificationRefreshMutation=false',
      'serviceId=$foregroundServiceId',
      'notificationPinAttempts=$_notificationPinAttempts',
      'notificationPinSuccesses=$_notificationPinSuccesses',
      'notificationDismissCount=$_notificationDismissCount',
      'notificationRestoreAttempts=$_notificationRestoreAttempts',
      'notificationRestoreSuccesses=$_notificationRestoreSuccesses',
      'lastNotificationDismissedAt=${_lastNotificationDismissedAt?.toIso8601String() ?? '-'}',
      'lastPinnedNotificationId=${_lastPinnedNotificationId ?? '-'}',
      'lastPersistenceAction=$_lastPersistenceAction',
      'shortText=${current.shortText}',
      'overdue=${liveSnapshot.isOverdue}',
      'overdueMinutes=${liveSnapshot.overdueMinutes}',
      'scheduledEnd=${liveSnapshot.scheduledEnd?.toIso8601String() ?? '-'}',
      'overdueReminderEvent=${reminderState.eventKey ?? '-'}',
      'lastOverdueReminderSlot=${reminderState.lastSlot ?? '-'}',
      'currentOverdueReminderSlot=${currentReminderSlot ?? '-'}',
      'nextOverdueReminderSlot=${nextReminderSlot ?? '-'}',
      'overdueNotificationInitialized=${LiveWorkOverdueNotificationService.instance.isReady}',
      'overdueTapPayload=${LiveWorkOverdueNotificationService.openWorkScreenPayload}',
      'lastOverdueTapSource=${LiveWorkOverdueNotificationService.instance.lastTapSource}',
      'lastOverdueTapPayload=${LiveWorkOverdueNotificationService.instance.lastTapPayload}',
      'workScreenButtonEnabled=false',
      'workScreenEntrySurface=notification_body',
      'workScreenRequestReceived=$_workScreenRequestReceived',
      'lastWorkScreenRequestSource=$_lastWorkScreenRequestSource',
      'lastWorkScreenRequestAt=${_lastWorkScreenRequestAt?.toIso8601String() ?? '-'}',
      'navigationInFlight=$_workScreenNavigationInFlight',
      'currentRoute=${AppNavigator.currentRoute ?? '-'}',
      'lastNavigationRequest=$_lastNavigationRequest',
      'lastNavigationRequestSource=$_lastNavigationRequestSource',
      'lastNavigationRequestAt=${_lastNavigationRequestAt?.toIso8601String() ?? '-'}',
      'lastNavigationHandled=$_lastNavigationHandled',
      'lastNavigationHandledAt=${_lastNavigationHandledAt?.toIso8601String() ?? '-'}',
      'lastNavigationSuppressedReason=$_lastNavigationSuppressedReason',
      'pendingWorkScreenNavigation=$_pendingWorkScreenNavigation',
      'breakActionReceived=$_breakActionReceived',
      'lastBreakActionAt=${_lastBreakActionAt?.toIso8601String() ?? '-'}',
      'lastBreakActionPhase=$_lastBreakActionPhase',
      'lastBreakPunchResult=$_lastBreakPunchResult',
      'lastBreakPunchMessage=$_lastBreakPunchMessage',
      'lastBreakRecordedAt=$_lastBreakRecordedAt',
      'workNotificationExpected=${current.isWorking}',
      'workNotificationFound=${_lastNotificationFound ?? current.notificationPersistent}',
      'notificationRecoveryCount=$_notificationRecoveryCount',
      'notificationRecoveryInProgress=$_notificationRecoveryInProgress',
      'lastNotificationRecoveryStage=$_lastNotificationRecoveryStage',
      'lastNotificationRecoveryResult=$_lastNotificationRecoveryResult',
      'forcedNotificationRecoveryCount=$_forcedNotificationRecoveryCount',
      'lastForcedNotificationRecoveryAt=${_lastForcedNotificationRecoveryAt?.toIso8601String() ?? '-'}',
      'lastNotificationRecoveryReason=$_lastNotificationRecoveryReason',
      'lastNotificationRecoveryAt=${_lastNotificationRecoveryAt?.toIso8601String() ?? '-'}',
      'liveLogs=${LiveWorkDiagnostics.lines.length}',
      'logs=${_debugLines.length}',
    ].join('\n');
    final statusDebugPrintCode = description
        .split('\n')
        .map((line) => 'debugPrint(${jsonEncode('[WORK_STATUS] $line')});')
        .join('\n');

    await StatusDialog.showSuccess(
      context,
      title: '근무 상태 알림 개발자 상태',
      description: description,
      copyText: '$statusDebugPrintCode\n$debugPrintCode\n${LiveWorkDiagnostics.debugPrintCode}',
      copyButtonLabel: 'debugPrint 코드 복사',
      visibleDuration: Duration.zero,
      useCommonUi: true,
      awaitManualClose: true,
    );
  }

  static Future<bool> _recoverService({
    required String source,
  }) async {
    final presentation = await _loadPresentation();
    if (!presentation.isWorking) {
      _lastLifecycleAction = 'recovery_skipped_not_working';
      _log('service_recovery_skipped_not_working source=$source');
      return true;
    }
    _recoveryAttempts++;
    _log(
      'service_recovery_start source=$source attempt=$_recoveryAttempts',
    );
    final recovered = await ensureServiceRunning(
      source: '${source}_recovery',
    );
    if (recovered) {
      _recoverySuccesses++;
      _log(
        'service_recovery_complete source=$source successes=$_recoverySuccesses',
      );
    } else {
      _log('service_recovery_failed source=$source');
    }
    return recovered;
  }


  static Future<bool> _stopServiceForInactiveWork({
    required String source,
    required _WorkStatusPresentation presentation,
    required bool runningBefore,
  }) async {
    await LiveWorkOverdueReminderCoordinator.clear();
    if (!runningBefore) {
      _lastLifecycleAction = 'inactive_already_stopped';
      _publish(
        presentation,
        serviceRunning: false,
        source: source,
      );
      _log('service_already_stopped_not_working source=$source');
      return true;
    }

    try {
      await FlutterForegroundTask.stopService();
      var runningAfter = true;
      for (var attempt = 1; attempt <= 4; attempt++) {
        runningAfter = await _safeIsRunningService();
        _log(
          'service_stop_verify_not_working source=$source attempt=$attempt running=$runningAfter',
        );
        if (!runningAfter) break;
        if (attempt < 4) {
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
      }
      _publish(
        presentation,
        serviceRunning: runningAfter,
        source: source,
      );
      if (runningAfter) {
        _lastLifecycleAction = 'inactive_stop_failed';
        _log('service_stop_failed_not_working source=$source runningAfter=true');
        return false;
      }
      _lastLifecycleAction = 'inactive_stopped';
      _log('service_stopped_not_working source=$source');
      return true;
    } catch (error, stackTrace) {
      final runningAfter = await _safeIsRunningService();
      _publish(
        presentation,
        serviceRunning: runningAfter,
        source: source,
      );
      _lastLifecycleAction =
          runningAfter ? 'inactive_stop_error_running' : 'inactive_stop_error_stopped';
      _log('service_stop_error_not_working source=$source error=$error');
      _log('service_stop_stack_not_working source=$source stack=$stackTrace');
      return !runningAfter;
    }
  }

  static Future<_WorkStatusPresentation> _loadPresentation() async {
    final snapshot = await LiveWorkSnapshotResolver.resolve();
    final live = LiveWorkNotificationPresenter.build(snapshot);
    return _WorkStatusPresentation(
      isWorking: snapshot.isWorking,
      title: live.title,
      text: live.text,
      shortText: live.shortText,
      overdue: snapshot.isOverdue,
      overdueMinutes: snapshot.overdueMinutes,
      showBreakAction: live.showBreakAction,
    );
  }

  static List<NotificationButton> _notificationButtons(
    _WorkStatusPresentation presentation,
  ) {
    return <NotificationButton>[
      if (presentation.showBreakAction)
        const NotificationButton(id: WorkStatusNotificationProtocol.breakPunchAction, text: '휴게 기록'),
    ];
  }


  static Future<bool> _pinPersistentNotification({
    required String source,
    required _WorkStatusPresentation presentation,
  }) async {
    _notificationPinAttempts++;
    for (var attempt = 1; attempt <= 4; attempt++) {
      try {
        final result =
            await _notificationControlChannel.invokeMapMethod<String, dynamic>(
          'pinForegroundNotification',
          <String, dynamic>{
            'serviceId': foregroundServiceId,
            'channelId': notificationChannelId,
          },
        );
        final pinned = result?['pinned'] == true;
        _lastNotificationFound = result?['notificationFound'] == true;
        final pinnedId = result?['notificationId'];
        if (pinnedId is int) {
          _lastPinnedNotificationId = pinnedId;
        }
        _log(
          'notification_pin_result source=$source attempt=$attempt pinned=$pinned found=$_lastNotificationFound id=${pinnedId ?? '-'} reason=${result?['reason'] ?? '-'} flags=${result?['flags'] ?? '-'}',
        );
        if (pinned) {
          _notificationPinSuccesses++;
          _lastPersistenceAction = 'pinned';
          status.value = status.value.copyWith(
            notificationPersistent: true,
            updatedAt: DateTime.now(),
          );
          return true;
        }
      } catch (error, stackTrace) {
        _log(
          'notification_pin_error source=$source attempt=$attempt error=$error',
        );
        _log(
          'notification_pin_stack source=$source attempt=$attempt stack=$stackTrace',
        );
      }
      if (attempt < 4) {
        await Future<void>.delayed(const Duration(milliseconds: 80));
      }
    }
    _lastPersistenceAction = 'pin_failed';
    status.value = status.value.copyWith(
      notificationPersistent: false,
      updatedAt: DateTime.now(),
    );
    return false;
  }

  static Future<void> _restoreDismissedNotification() async {
    if (_dismissRestoreInFlight) {
      _log('notification_restore_ignored reason=already_in_flight');
      return;
    }
    _dismissRestoreInFlight = true;
    try {
      final presentation = await _loadPresentation();
      if (!presentation.isWorking) {
        _lastPersistenceAction = 'restore_skipped_not_working';
        _log('notification_restore_skipped_not_working');
        return;
      }

      _notificationRestoreAttempts++;
      _notificationRecoveryCount++;
      _lastNotificationRecoveryReason = 'notification_dismissed';
      _lastNotificationRecoveryAt = DateTime.now();
      final running = await _safeIsRunningService();
      _log(
        'notification_restore_requested attempt=$_notificationRestoreAttempts serviceRunning=$running',
      );

      if (!running) {
        final recovered = await _recoverService(
          source: 'notification_dismissed',
        );
        if (recovered && status.value.notificationPersistent) {
          _notificationRestoreSuccesses++;
          _lastPersistenceAction = 'restored_by_service_recovery';
          _log(
            'notification_restore_complete mode=service_recovery successes=$_notificationRestoreSuccesses',
          );
        } else {
          _lastPersistenceAction = 'restore_failed_service_recovery';
          _log('notification_restore_failed mode=service_recovery');
        }
        return;
      }

      _notificationRecoveryInProgress = true;
      _lastNotificationRecoveryStage = 'pin_existing';
      var pinned = await _pinPersistentNotification(
        source: 'notification_dismissed_task_restore',
        presentation: presentation,
      );
      if (!pinned) {
        _lastNotificationRecoveryStage = 'update_service';
        await FlutterForegroundTask.updateService(
          notificationTitle: presentation.title,
          notificationText: presentation.text,
          notificationButtons: _notificationButtons(presentation),
          notificationInitialRoute: initialRoute,
        );
        _lastNotificationRecoveryStage = 'verify_after_update';
        pinned = await _pinPersistentNotification(
          source: 'notification_dismissed_main_restore',
          presentation: presentation,
        );
      }
      if (!pinned && _lastNotificationFound == false) {
        _lastNotificationRecoveryStage = 'forced_recreate';
        pinned = await _forceRecreateWorkNotification(
          source: 'notification_dismissed',
        );
      }
      final latestPresentation = await _loadPresentation();
      final runningAfter = await _safeIsRunningService();
      _publish(
        latestPresentation,
        serviceRunning: runningAfter,
        notificationPersistent: pinned,
        source: 'notification_dismissed_restore',
      );
      if (pinned) {
        _notificationRestoreSuccesses++;
        _lastPersistenceAction = 'restored';
        _lastNotificationRecoveryResult = 'success';
        _log(
          'notification_restore_complete stage=$_lastNotificationRecoveryStage successes=$_notificationRestoreSuccesses',
        );
      } else {
        _lastPersistenceAction = 'restore_failed_pin';
        _lastNotificationRecoveryResult = _lastNotificationFound == false
            ? 'notification_still_missing'
            : 'notification_found_pin_failed';
        _log(
          'notification_restore_failed stage=$_lastNotificationRecoveryStage result=$_lastNotificationRecoveryResult',
        );
      }
    } catch (error, stackTrace) {
      _lastPersistenceAction = 'restore_error';
      _log('notification_restore_error error=$error');
      _log('notification_restore_stack stack=$stackTrace');
    } finally {
      _notificationRecoveryInProgress = false;
      _dismissRestoreInFlight = false;
    }
  }

  static Future<bool> _forceRecreateWorkNotification({
    required String source,
  }) async {
    final now = DateTime.now();
    final lastForcedAt = _lastForcedNotificationRecoveryAt;
    if (lastForcedAt != null &&
        now.difference(lastForcedAt) < const Duration(seconds: 10)) {
      _lastNotificationRecoveryResult = 'forced_recreate_cooldown';
      _log('notification_forced_recreate_skipped source=$source reason=cooldown');
      return false;
    }

    final latestPresentation = await _loadPresentation();
    if (!latestPresentation.isWorking) {
      _lastNotificationRecoveryResult = 'forced_recreate_skipped_not_working';
      _log('notification_forced_recreate_skipped source=$source reason=not_working');
      final running = await _safeIsRunningService();
      if (running) {
        await _stopServiceForInactiveWork(
          source: '${source}_forced_recreate_not_working',
          presentation: latestPresentation,
          runningBefore: true,
        );
      }
      return false;
    }

    _forcedNotificationRecoveryCount++;
    _lastForcedNotificationRecoveryAt = now;
    _lastNotificationRecoveryStage = 'forced_recreate_stop';
    _log(
      'notification_forced_recreate_start source=$source count=$_forcedNotificationRecoveryCount',
    );

    try {
      final runningBefore = await _safeIsRunningService();
      if (runningBefore) {
        await FlutterForegroundTask.stopService();
        var stopped = false;
        for (var attempt = 1; attempt <= 5; attempt++) {
          final running = await _safeIsRunningService();
          _log(
            'notification_forced_recreate_stop_verify source=$source attempt=$attempt running=$running',
          );
          if (!running) {
            stopped = true;
            break;
          }
          if (attempt < 5) {
            await Future<void>.delayed(const Duration(milliseconds: 120));
          }
        }
        if (!stopped) {
          _lastNotificationRecoveryResult = 'forced_recreate_stop_failed';
          _log('notification_forced_recreate_failed source=$source reason=stop_failed');
          return false;
        }
      }

      final beforeStart = await _loadPresentation();
      if (!beforeStart.isWorking) {
        _lastNotificationRecoveryResult = 'forced_recreate_cancelled_not_working';
        _log('notification_forced_recreate_cancelled source=$source reason=not_working_before_start');
        return false;
      }

      _lastNotificationRecoveryStage = 'forced_recreate_start';
      final ensureResult = await ensureServiceState(
        source: '${source}_forced_recreate',
      );
      if (!ensureResult.running) {
        _lastNotificationRecoveryResult = 'forced_recreate_service_start_failed';
        return false;
      }

      final afterStart = await _loadPresentation();
      if (!afterStart.isWorking) {
        await _stopServiceForInactiveWork(
          source: '${source}_forced_recreate_post_start_not_working',
          presentation: afterStart,
          runningBefore: true,
        );
        _lastNotificationRecoveryResult = 'forced_recreate_stopped_after_clock_out';
        return false;
      }

      _lastNotificationRecoveryStage = 'forced_recreate_verify';
      final pinned = await _pinPersistentNotification(
        source: '${source}_forced_recreate_verify',
        presentation: afterStart,
      );
      _lastNotificationRecoveryResult = pinned
          ? 'forced_recreate_success'
          : (_lastNotificationFound == false
              ? 'forced_recreate_notification_missing'
              : 'forced_recreate_pin_failed');
      _log(
        'notification_forced_recreate_complete source=$source pinned=$pinned found=${_lastNotificationFound ?? '-'} result=$_lastNotificationRecoveryResult',
      );
      return pinned;
    } catch (error, stackTrace) {
      _lastNotificationRecoveryResult = 'forced_recreate_error';
      _log('notification_forced_recreate_error source=$source error=$error');
      _log('notification_forced_recreate_stack source=$source stack=$stackTrace');
      return false;
    }
  }

  static Future<bool> _safeIsRunningService() async {
    try {
      return await FlutterForegroundTask.isRunningService;
    } catch (error) {
      _log('service_running_check_error error=$error');
      return false;
    }
  }

  static void _publish(
    _WorkStatusPresentation presentation, {
    required bool serviceRunning,
    bool? notificationPersistent,
    required String source,
  }) {
    status.value = WorkStatusNotificationSnapshot(
      isWorking: presentation.isWorking,
      title: presentation.title,
      text: presentation.text,
      shortText: presentation.shortText,
      overdue: presentation.overdue,
      overdueMinutes: presentation.overdueMinutes,
      serviceRunning: serviceRunning,
      notificationPersistent: serviceRunning
          ? notificationPersistent ?? status.value.notificationPersistent
          : false,
      source: source,
      updatedAt: DateTime.now(),
    );
  }


  static void _handleOverdueOpenWorkScreen(String source, String payload) {
    _log('overdue_notification_tap source=$source payload=${jsonEncode(payload)}');
    _requestWorkScreenNavigation(source: 'overdue_notification:$source');
  }

  static void _requestWorkScreenNavigation({required String source}) {
    final now = DateTime.now();
    _lastNavigationRequest = initialRoute;
    _lastNavigationRequestSource = source;
    _lastNavigationRequestAt = now;
    _lastNavigationSuppressedReason = '-';
    _pendingWorkScreenNavigation = true;
    _navigateToWorkScreen(source: source);
  }

  static void _navigateToWorkScreen({required String source}) {
    final navigator = AppNavigator.nav;
    if (navigator == null) {
      _lastNavigationHandled = 'pending';
      _lastNavigationSuppressedReason = 'navigator_unavailable';
      _log('work_screen_navigation_pending route=$initialRoute source=$source reason=navigator_unavailable');
      return;
    }
    if (_workScreenNavigationInFlight) {
      _lastNavigationHandled = 'suppressed';
      _lastNavigationSuppressedReason = 'navigation_in_flight';
      _log('work_screen_navigation_suppressed route=$initialRoute source=$source reason=navigation_in_flight');
      return;
    }
    if (AppNavigator.currentRoute == initialRoute) {
      _pendingWorkScreenNavigation = false;
      _lastNavigationHandled = 'suppressed';
      _lastNavigationSuppressedReason = 'already_on_work_screen';
      _log('work_screen_navigation_suppressed route=$initialRoute source=$source reason=already_on_work_screen');
      return;
    }
    final lastHandledAt = _lastNavigationHandledAt;
    if (lastHandledAt != null &&
        DateTime.now().difference(lastHandledAt) < const Duration(milliseconds: 900)) {
      _pendingWorkScreenNavigation = false;
      _lastNavigationHandled = 'suppressed';
      _lastNavigationSuppressedReason = 'duplicate_request';
      _log('work_screen_navigation_suppressed route=$initialRoute source=$source reason=duplicate_request');
      return;
    }
    _pendingWorkScreenNavigation = false;
    _workScreenNavigationInFlight = true;
    _lastNavigationSuppressedReason = '-';
    try {
      navigator.pushNamedAndRemoveUntil(
        initialRoute,
        (route) => route.isFirst,
      );
      _lastNavigationHandled = 'handled';
      _lastNavigationHandledAt = DateTime.now();
      _log('work_screen_navigation route=$initialRoute source=$source');
      Future<void>.delayed(const Duration(milliseconds: 420), () {
        _workScreenNavigationInFlight = false;
        _log('work_screen_navigation_transition_complete route=$initialRoute source=$source currentRoute=${AppNavigator.currentRoute ?? '-'}');
      });
    } catch (error, stackTrace) {
      _workScreenNavigationInFlight = false;
      _lastNavigationHandled = 'error';
      _lastNavigationSuppressedReason = 'navigation_error';
      _log('work_screen_navigation_error route=$initialRoute source=$source error=$error');
      _log('work_screen_navigation_stack source=$source stack=$stackTrace');
    }
  }

  static void _onTaskData(dynamic data) {
    if (data is! Map) return;
    if (data['kind'] != WorkStatusNotificationProtocol.eventKind) return;
    final event = data['event']?.toString() ?? 'unknown';
    final timestamp = data['ts']?.toString() ?? '-';
    _log('task_event event=$event ts=$timestamp');
    if (event == WorkStatusNotificationProtocol.breakActionEvent) {
      _breakActionReceived = true;
      _lastBreakActionAt = DateTime.now();
      _lastBreakActionPhase = data['phase']?.toString() ?? '-';
      final success = data['success'];
      final alreadyRecorded = data['alreadyRecorded'];
      if (success == true) {
        _lastBreakPunchResult = 'inserted';
      } else if (alreadyRecorded == true) {
        _lastBreakPunchResult = 'already_recorded';
      } else if (_lastBreakActionPhase == 'error') {
        _lastBreakPunchResult = 'error';
      } else if (_lastBreakActionPhase == 'completed') {
        _lastBreakPunchResult = 'rejected';
      } else {
        _lastBreakPunchResult = 'received';
      }
      _lastBreakPunchMessage = data['message']?.toString() ?? '-';
      _lastBreakRecordedAt = data['recordedAt']?.toString() ?? '-';
      _log('break_action phase=$_lastBreakActionPhase result=$_lastBreakPunchResult recordedAt=$_lastBreakRecordedAt message=${jsonEncode(_lastBreakPunchMessage)}');
      if (_lastBreakActionPhase == 'completed') {
        unawaited(refresh(source: 'break_action_completed'));
      }
      return;
    }
    if (event == WorkStatusNotificationProtocol.refreshedEvent) {
      final receivedAt = DateTime.now();
      _taskNotificationRefreshedCount++;
      _lastTaskNotificationRefreshedAt = receivedAt;
      _lastTaskNotificationRefreshedTimestamp = timestamp;
      _lastLifecycleAction = 'task_notification_refreshed_acknowledged';
      _log(
        'task_notification_refreshed '
        'count=$_taskNotificationRefreshedCount '
        'receivedAt=${receivedAt.toIso8601String()} '
        'handlerTimestamp=$timestamp '
        'notificationMutation=false',
      );
      return;
    }
    if (event == WorkStatusNotificationProtocol.workScreenRequestedEvent ||
        event == WorkStatusNotificationProtocol.openWorkScreenEvent ||
        event == WorkStatusNotificationProtocol.pressedEvent) {
      final semanticSource = data['source']?.toString() ?? 'foreground_task:$event';
      _workScreenRequestReceived = true;
      _lastWorkScreenRequestAt = DateTime.now();
      _lastWorkScreenRequestSource = semanticSource;
      _log('work_screen_request_received event=$event source=$semanticSource route=${data['route']?.toString() ?? initialRoute}');
      _requestWorkScreenNavigation(source: semanticSource);
      return;
    }
    if (event == WorkStatusNotificationProtocol.dismissedEvent) {
      _notificationDismissCount++;
      final timestampMillis = int.tryParse(timestamp);
      _lastNotificationDismissedAt = timestampMillis == null
          ? DateTime.tryParse(timestamp) ?? DateTime.now()
          : DateTime.fromMillisecondsSinceEpoch(timestampMillis);
      _lastPersistenceAction = 'dismissed';
      status.value = status.value.copyWith(
        notificationPersistent: false,
        source: event,
        updatedAt: DateTime.now(),
      );
      unawaited(_restoreDismissedNotification());
      return;
    }
    if (event == WorkStatusNotificationProtocol.serviceTimeoutEvent ||
        event == WorkStatusNotificationProtocol.serviceDestroyedEvent ||
        event ==
            WorkStatusNotificationProtocol.serviceStartBlockedNotWorkingEvent) {
      if (event ==
          WorkStatusNotificationProtocol.serviceStartBlockedNotWorkingEvent) {
        _lastLifecycleAction = 'handler_start_blocked_not_working';
      }
      status.value = status.value.copyWith(
        serviceRunning: false,
        notificationPersistent: false,
        source: event,
        updatedAt: DateTime.now(),
      );
      if (event == WorkStatusNotificationProtocol.serviceDestroyedEvent ||
          event == WorkStatusNotificationProtocol.serviceTimeoutEvent) {
        _notificationRecoveryCount++;
        _lastNotificationRecoveryReason = event;
        _lastNotificationRecoveryAt = DateTime.now();
        unawaited(refresh(source: 'task_event_$event'));
      }
    }
  }

  static void _log(String message) {
    final line =
        '[WORK_STATUS_NOTIFICATION][${DateTime.now().toIso8601String()}] $message';
    debugPrint(line);
    _debugLines.add(line);
    if (_debugLines.length > maxDebugLines) {
      _debugLines.removeRange(0, _debugLines.length - maxDebugLines);
    }
  }
}

@immutable
class _WorkStatusPresentation {
  const _WorkStatusPresentation({
    required this.isWorking,
    required this.title,
    required this.text,
    required this.shortText,
    required this.overdue,
    required this.overdueMinutes,
    required this.showBreakAction,
  });

  final bool isWorking;
  final String title;
  final String text;
  final String shortText;
  final bool overdue;
  final int overdueMinutes;
  final bool showBreakAction;
}
