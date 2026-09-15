import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../features/selector/application/dev_auth.dart';
import '../../shared/notification/work_status_notification_protocol.dart';
import '../utils/status_dialog.dart';
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
    required this.serviceRunning,
    required this.notificationPersistent,
    required this.source,
    required this.updatedAt,
  });

  const WorkStatusNotificationSnapshot.initial()
      : isWorking = false,
        title = '업무 대기 중',
        text = '근무 시작을 기다리고 있습니다.',
        serviceRunning = false,
        notificationPersistent = false,
        source = 'initial',
        updatedAt = null;

  final bool isWorking;
  final String title;
  final String text;
  final bool serviceRunning;
  final bool notificationPersistent;
  final String source;
  final DateTime? updatedAt;

  WorkStatusNotificationSnapshot copyWith({
    bool? isWorking,
    String? title,
    String? text,
    bool? serviceRunning,
    bool? notificationPersistent,
    String? source,
    DateTime? updatedAt,
  }) {
    return WorkStatusNotificationSnapshot(
      isWorking: isWorking ?? this.isWorking,
      title: title ?? this.title,
      text: text ?? this.text,
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

  static const String initialRoute = '/';
  static const int foregroundServiceId = 42101;
  static const String notificationChannelId = 'parkinworkin_work_status_v1';
  static const MethodChannel _notificationControlChannel =
      MethodChannel('com.quintus.dev/work_status_notification');
  static const String notificationChannelName = '근무 상태';
  static const String notificationChannelDescription =
      'ParkinWorkin 근무 상태를 표시합니다.';
  static const int maxDebugLines = 240;
  static const String foregroundServiceTypeLabel = 'specialUse|mediaPlayback';

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
  static int _notificationPinAttempts = 0;
  static int _notificationPinSuccesses = 0;
  static int _notificationDismissCount = 0;
  static int _notificationRestoreAttempts = 0;
  static int _notificationRestoreSuccesses = 0;
  static DateTime? _lastNotificationDismissedAt;
  static int? _lastPinnedNotificationId;
  static String _lastPersistenceAction = 'initial';
  static bool _dismissRestoreInFlight = false;

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
        eventAction: ForegroundTaskEventAction.nothing(),
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
    _log('task_event_listener_ready');
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
          notificationInitialRoute: initialRoute,
        );
        final persistent = await _pinPersistentNotification(
          source: '${source}_reuse',
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
          ForegroundServiceTypes.mediaPlayback,
        ],
        notificationTitle: presentation.title,
        notificationText: presentation.text,
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
              notificationInitialRoute: initialRoute,
            );
            final persistent = await _pinPersistentNotification(
              source: '${activeSource}_refresh',
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

  static Future<void> showDeveloperStatus(BuildContext context) async {
    final developerMode = await DevAuth.isDevModeEnabled();
    if (!developerMode || !context.mounted) return;

    final current = status.value;
    final serviceRunning = await _safeIsRunningService();
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
      'serviceId=$foregroundServiceId',
      'notificationPinAttempts=$_notificationPinAttempts',
      'notificationPinSuccesses=$_notificationPinSuccesses',
      'notificationDismissCount=$_notificationDismissCount',
      'notificationRestoreAttempts=$_notificationRestoreAttempts',
      'notificationRestoreSuccesses=$_notificationRestoreSuccesses',
      'lastNotificationDismissedAt=${_lastNotificationDismissedAt?.toIso8601String() ?? '-'}',
      'lastPinnedNotificationId=${_lastPinnedNotificationId ?? '-'}',
      'lastPersistenceAction=$_lastPersistenceAction',
      'logs=${_debugLines.length}',
    ].join('\n');

    await StatusDialog.showSuccess(
      context,
      title: '근무 상태 알림 개발자 상태',
      description: description,
      copyText: debugPrintCode,
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
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final isWorking = prefs.getBool('isWorking') ?? false;
    if (isWorking) {
      return const _WorkStatusPresentation(
        isWorking: true,
        title: '근무 중',
        text: '현재 근무 세션이 진행 중입니다.',
      );
    }
    return const _WorkStatusPresentation(
      isWorking: false,
      title: '업무 대기 중',
      text: '근무 시작을 기다리고 있습니다.',
    );
  }

  static Future<bool> _pinPersistentNotification({
    required String source,
  }) async {
    _notificationPinAttempts++;
    for (var attempt = 1; attempt <= 4; attempt++) {
      try {
        final result = await _notificationControlChannel.invokeMapMethod<String, dynamic>(
          'pinForegroundNotification',
          <String, dynamic>{
            'serviceId': foregroundServiceId,
            'channelId': notificationChannelId,
          },
        );
        final pinned = result?['pinned'] == true;
        final pinnedId = result?['notificationId'];
        if (pinnedId is int) {
          _lastPinnedNotificationId = pinnedId;
        }
        _log(
          'notification_pin_result source=$source attempt=$attempt pinned=$pinned id=${pinnedId ?? '-'} reason=${result?['reason'] ?? '-'} flags=${result?['flags'] ?? '-'}',
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

      var pinned = await _pinPersistentNotification(
        source: 'notification_dismissed_task_restore',
      );
      if (!pinned) {
        await FlutterForegroundTask.updateService(
          notificationTitle: presentation.title,
          notificationText: presentation.text,
          notificationInitialRoute: initialRoute,
        );
        pinned = await _pinPersistentNotification(
          source: 'notification_dismissed_main_restore',
        );
      }
      _publish(
        presentation,
        serviceRunning: true,
        notificationPersistent: pinned,
        source: 'notification_dismissed_restore',
      );
      if (pinned) {
        _notificationRestoreSuccesses++;
        _lastPersistenceAction = 'restored';
        _log(
          'notification_restore_complete mode=pin successes=$_notificationRestoreSuccesses',
        );
      } else {
        _lastPersistenceAction = 'restore_failed_pin';
        _log('notification_restore_failed mode=pin');
      }
    } catch (error, stackTrace) {
      _lastPersistenceAction = 'restore_error';
      _log('notification_restore_error error=$error');
      _log('notification_restore_stack stack=$stackTrace');
    } finally {
      _dismissRestoreInFlight = false;
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
      serviceRunning: serviceRunning,
      notificationPersistent: serviceRunning
          ? notificationPersistent ?? status.value.notificationPersistent
          : false,
      source: source,
      updatedAt: DateTime.now(),
    );
  }

  static void _onTaskData(dynamic data) {
    if (data is! Map) return;
    if (data['kind'] != WorkStatusNotificationProtocol.eventKind) return;
    final event = data['event']?.toString() ?? 'unknown';
    final timestamp = data['ts']?.toString() ?? '-';
    _log('task_event event=$event ts=$timestamp');
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
  });

  final bool isWorking;
  final String title;
  final String text;
}
