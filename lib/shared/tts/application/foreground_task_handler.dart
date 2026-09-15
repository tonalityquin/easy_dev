import 'dart:async';
import 'dart:ui';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../notification/work_status_notification_protocol.dart';
import '../services/plate/plate_local_notification_service.dart';
import '../services/plate/plate_tts_listener_service.dart';
import 'plate_tts_session_protocol.dart';
import 'plate_tts_session_recovery_store.dart';
import 'tts_ownership.dart';
import 'tts_user_filters.dart';

String _ts() => DateTime.now().toIso8601String();

@pragma('vm:entry-point')
class MyTaskHandler implements TaskHandler {
  String? _listeningArea;
  String? _listeningMode;
  DateTime? _startedAt;

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    WidgetsFlutterBinding.ensureInitialized();
    DartPluginRegistrant.ensureInitialized();
    PlateTtsListenerService.setLocalRole(TtsOwner.foreground);
    _startedAt = DateTime.now();
    debugPrint('[HANDLER][${_ts()}] onStart starter=$starter at=$_startedAt');

    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp();
        debugPrint('[HANDLER][${_ts()}] Firebase.initializeApp done');
      } else {
        debugPrint('[HANDLER][${_ts()}] Firebase already initialized');
      }
    } catch (error, stackTrace) {
      debugPrint('[HANDLER][${_ts()}] Firebase init error=$error\n$stackTrace');
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final isWorking = prefs.getBool('isWorking') ?? false;
    if (!isWorking) {
      await PlateTtsSessionRecoveryStore.clear(
        source: 'handler_start_not_working',
      );
      await PlateTtsListenerService.stop();
      await TtsOwnership.setOwner(TtsOwner.app);
      PlateTtsListenerService.setLocalRole(TtsOwner.app);
      _listeningArea = null;
      _listeningMode = null;
      _sendStatus(
        event: 'handler_start_blocked',
        listening: false,
        masterOn: false,
        reason: 'not_working',
        source: 'foreground_service_start',
      );
      _sendWorkStatusNotificationEvent(
        WorkStatusNotificationProtocol.serviceStartBlockedNotWorkingEvent,
      );
      debugPrint(
        '[HANDLER][${_ts()}] start blocked isWorking=false starter=$starter',
      );
      await FlutterForegroundTask.stopService();
      return;
    }

    await PlateLocalNotificationService.instance.ensureInitialized();
    await PlateTtsListenerService.stop();
    _listeningArea = null;
    _listeningMode = null;

    final recovery = await PlateTtsSessionRecoveryStore.load();
    if (recovery == null) {
      await TtsOwnership.setOwner(TtsOwner.app);
      _sendStatus(
        event: 'handler_started',
        listening: false,
        masterOn: false,
        reason: 'awaiting_session_payload',
        source: 'foreground_service_start',
      );
      debugPrint('[HANDLER][${_ts()}] recovery snapshot unavailable');
      return;
    }

    final recoverySource = recovery.source.isEmpty
        ? 'foreground_service_recovery'
        : 'foreground_service_recovery:${recovery.source}';
    debugPrint(
      '[HANDLER][${_ts()}] recovery apply area=${recovery.area} mode=${recovery.mode} clearMode=${recovery.clearMode} source=$recoverySource',
    );
    await _applySessionCommand(
      recovery.toTaskPayload(
        source: recoverySource,
        forceRestart: true,
      ),
      fallbackSource: recoverySource,
    );
  }

  @override
  Future<void> onRepeatEvent(DateTime timestamp) async {}

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    debugPrint(
      '[HANDLER][${_ts()}] onDestroy isTimeout=$isTimeout area=$_listeningArea mode=$_listeningMode',
    );
    await PlateTtsListenerService.stop();
    await TtsOwnership.setOwner(TtsOwner.app);
    _listeningArea = null;
    _listeningMode = null;
    _sendStatus(
      event: isTimeout ? 'handler_timeout' : 'handler_destroyed',
      listening: false,
      masterOn: false,
      reason: isTimeout ? 'service_timeout' : 'service_destroyed',
      source: 'foreground_service_destroy',
    );
    _sendWorkStatusNotificationEvent(
      isTimeout
          ? WorkStatusNotificationProtocol.serviceTimeoutEvent
          : WorkStatusNotificationProtocol.serviceDestroyedEvent,
    );
  }

  @override
  void onNotificationPressed() {
    debugPrint('[HANDLER][${_ts()}] onNotificationPressed');
    _sendWorkStatusNotificationEvent(
      WorkStatusNotificationProtocol.pressedEvent,
    );
  }

  @override
  void onNotificationButtonPressed(String id) {
    debugPrint('[HANDLER][${_ts()}] onNotificationButtonPressed id=$id');
  }

  @override
  void onNotificationDismissed() {
    debugPrint('[HANDLER][${_ts()}] onNotificationDismissed');
    unawaited(_restoreWorkStatusNotificationAfterDismiss());
  }

  Future<void> _restoreWorkStatusNotificationAfterDismiss() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      final isWorking = prefs.getBool('isWorking') ?? false;
      if (!isWorking) {
        debugPrint(
          '[HANDLER][${_ts()}] notification restore skipped isWorking=false',
        );
        return;
      }

      await FlutterForegroundTask.updateService(
        notificationTitle: '근무 중',
        notificationText: '현재 근무 세션이 진행 중입니다.',
        notificationInitialRoute: '/',
      );
      debugPrint(
        '[HANDLER][${_ts()}] notification restored after dismissal',
      );
    } catch (error, stackTrace) {
      debugPrint(
        '[HANDLER][${_ts()}] notification restore error=$error\n$stackTrace',
      );
    } finally {
      _sendWorkStatusNotificationEvent(
        WorkStatusNotificationProtocol.dismissedEvent,
      );
    }
  }

  @override
  void onReceiveData(Object data) async {
    await _applySessionCommand(
      data,
      fallbackSource: 'receive_data',
    );
  }

  Future<void> _applySessionCommand(
    Object data, {
    required String fallbackSource,
  }) async {
    debugPrint(
      '[HANDLER][${_ts()}] applySessionCommand data=$data currentArea=$_listeningArea currentMode=$_listeningMode',
    );

    String? area;
    String? incomingMode;
    TtsUserFilters? incomingFilters;
    var forceRestart = false;
    var clearMode = false;
    var source = fallbackSource;

    if (data is Map) {
      final kind = data['kind'];
      if (kind != null && kind.toString() != PlateTtsSessionProtocol.commandKind) {
        debugPrint(
          '[HANDLER][${_ts()}] unsupported command kind=${kind.toString()}',
        );
        return;
      }
      final vArea = data['area'];
      if (vArea is String) {
        area = vArea.trim();
      }
      final vMode = data['mode'];
      if (vMode is String && vMode.trim().isNotEmpty) {
        incomingMode = vMode.trim();
      }
      final vFilters = data['ttsFilters'];
      if (vFilters is Map) {
        incomingFilters = TtsUserFilters.fromMap(vFilters);
      }
      forceRestart = data['forceRestart'] == true;
      clearMode = data['clearMode'] == true;
      final vSource = data['source'];
      if (vSource is String && vSource.trim().isNotEmpty) {
        source = vSource.trim();
      }
    } else if (data is String && data.trim().isNotEmpty) {
      area = data.trim();
    } else {
      debugPrint('[HANDLER][${_ts()}] unsupported data type=${data.runtimeType}');
      return;
    }

    if (clearMode) {
      await PlateTtsListenerService.stop();
      await TtsOwnership.setOwner(TtsOwner.app);
      _listeningArea = null;
      _listeningMode = null;
      _sendStatus(
        event: 'session_waiting_mode',
        listening: false,
        masterOn: false,
        area: area,
        mode: '',
        reason: 'mode_cleared',
        source: source,
      );
      debugPrint(
        '[HANDLER][${_ts()}] session mode cleared area=${area ?? ''} source=$source',
      );
      return;
    }

    final filters = incomingFilters ?? await _loadFiltersSafe();
    if (filters == null) {
      _sendStatus(
        event: 'session_rejected',
        listening: PlateTtsListenerService.isListening,
        masterOn: false,
        area: area,
        mode: incomingMode,
        reason: 'filters_unavailable',
        source: source,
      );
      return;
    }

    final mode = await _resolveMode(incomingMode);
    if (mode.isEmpty) {
      await PlateTtsListenerService.stop();
      await TtsOwnership.setOwner(TtsOwner.app);
      _listeningArea = null;
      _listeningMode = null;
      _sendStatus(
        event: 'session_waiting_mode',
        listening: false,
        masterOn: false,
        area: area,
        mode: mode,
        reason: 'mode_not_selected',
        source: source,
      );
      return;
    }

    await TtsOwnership.setOwner(TtsOwner.foreground);
    final isTablet = mode == 'tablet';
    final completedOk = filters.completed && isTablet;
    final masterOn =
        (isTablet ? filters.departure : (filters.parking || filters.departure)) ||
            completedOk;

    if (!masterOn) {
      await PlateTtsListenerService.stop();
      _listeningArea = null;
      _listeningMode = mode;
      debugPrint(
        '[HANDLER][${_ts()}] session disabled mode=$mode filters=${filters.toMap()}',
      );
      _sendStatus(
        event: 'session_disabled',
        listening: false,
        masterOn: false,
        area: area,
        mode: mode,
        reason: 'effective_master_off',
        source: source,
      );
      return;
    }

    if (area == null || area.isEmpty) {
      await PlateTtsListenerService.stop();
      _listeningArea = null;
      _listeningMode = mode;
      _sendStatus(
        event: 'session_waiting_area',
        listening: false,
        masterOn: true,
        area: area,
        mode: mode,
        reason: 'empty_area',
        source: source,
      );
      return;
    }

    final changed = _listeningArea != area || _listeningMode != mode;
    if (!forceRestart &&
        !changed &&
        PlateTtsListenerService.isListening &&
        PlateTtsListenerService.currentArea == area &&
        PlateTtsListenerService.currentMode == mode) {
      debugPrint(
        '[HANDLER][${_ts()}] session noop area=$area mode=$mode source=$source',
      );
      _sendStatus(
        event: 'session_noop',
        listening: true,
        masterOn: true,
        area: area,
        mode: mode,
        reason: 'already_listening',
        source: source,
      );
      return;
    }

    try {
      final started = await PlateTtsListenerService.start(
        area,
        force: forceRestart || changed || !PlateTtsListenerService.isListening,
        mode: mode,
        filters: filters,
      );
      if (started) {
        final prevArea = _listeningArea;
        final prevMode = _listeningMode;
        _listeningArea = area;
        _listeningMode = mode;
        debugPrint(
          '[HANDLER][${_ts()}] listener started area=$area mode=$mode prevArea=$prevArea prevMode=$prevMode source=$source',
        );
      } else {
        _listeningArea = null;
        _listeningMode = mode;
        debugPrint(
          '[HANDLER][${_ts()}] listener start rejected area=$area mode=$mode source=$source',
        );
      }
      _sendStatus(
        event: started ? 'listener_started' : 'listener_rejected',
        listening: started,
        masterOn: true,
        area: area,
        mode: mode,
        reason: started ? 'subscription_active' : 'start_returned_false',
        source: source,
      );
    } catch (error, stackTrace) {
      _listeningArea = null;
      _listeningMode = mode;
      debugPrint(
        '[HANDLER][${_ts()}] listener start error area=$area mode=$mode error=$error\n$stackTrace',
      );
      _sendStatus(
        event: 'listener_error',
        listening: false,
        masterOn: true,
        area: area,
        mode: mode,
        reason: error.toString(),
        source: source,
      );
    }
  }

  void _sendWorkStatusNotificationEvent(String event) {
    try {
      FlutterForegroundTask.sendDataToMain(<String, dynamic>{
        'kind': WorkStatusNotificationProtocol.eventKind,
        'event': event,
        'ts': DateTime.now().millisecondsSinceEpoch,
      });
    } catch (error) {
      debugPrint(
        '[HANDLER][${_ts()}] work status notification event send failed error=$error',
      );
    }
  }

  Future<String> _resolveMode(String? incomingMode) async {
    final normalized = (incomingMode ?? '').trim();
    if (normalized.isNotEmpty) return normalized;
    final current = (_listeningMode ?? '').trim();
    if (current.isNotEmpty) return current;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      return (prefs.getString('mode') ?? '').trim();
    } catch (error) {
      debugPrint('[HANDLER][${_ts()}] mode load failed error=$error');
      return '';
    }
  }

  Future<TtsUserFilters?> _loadFiltersSafe() async {
    try {
      return await TtsUserFilters.load();
    } catch (error) {
      debugPrint('[HANDLER][${_ts()}] TtsUserFilters.load failed error=$error');
      return null;
    }
  }

  void _sendStatus({
    required String event,
    required bool listening,
    required bool masterOn,
    String? area,
    String? mode,
    required String reason,
    String source = '',
  }) {
    try {
      FlutterForegroundTask.sendDataToMain(<String, dynamic>{
        'kind': PlateTtsSessionProtocol.statusKind,
        'event': event,
        'area': (area ?? _listeningArea ?? '').trim(),
        'mode': (mode ?? _listeningMode ?? '').trim(),
        'listening': listening,
        'masterOn': masterOn,
        'reason': reason,
        'source': source,
        'ts': DateTime.now().millisecondsSinceEpoch,
      });
    } catch (error) {
      debugPrint('[HANDLER][${_ts()}] send status failed error=$error');
    }
  }
}
