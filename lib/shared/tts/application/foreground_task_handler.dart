import 'dart:ui';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/plate/plate_local_notification_service.dart';
import '../services/plate/plate_tts_listener_service.dart';
import 'plate_tts_session_protocol.dart';
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
    debugPrint('[HANDLER][${_ts()}] onStart: starter=$starter at=$_startedAt');

    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp();
        debugPrint(
            '[HANDLER][${_ts()}] Firebase.initializeApp() done in FG isolate');
      } else {
        debugPrint(
            '[HANDLER][${_ts()}] Firebase already initialized in FG isolate');
      }
    } catch (e, st) {
      debugPrint('[HANDLER][${_ts()}] Firebase init error: $e\n$st');
    }

    await PlateLocalNotificationService.instance.ensureInitialized();
    await PlateTtsListenerService.stop();
    _listeningArea = null;
    _listeningMode = null;
    _sendStatus(
      event: 'handler_started',
      listening: false,
      masterOn: false,
      reason: 'awaiting_session_payload',
    );
  }

  @override
  Future<void> onRepeatEvent(DateTime timestamp) async {}

  @override
  Future<void> onDestroy(DateTime timestamp, bool isServiceDetached) async {
    debugPrint(
        '[HANDLER][${_ts()}] onDestroy: detached=$isServiceDetached → stop listener (area=$_listeningArea)');
    await PlateTtsListenerService.stop();
    _listeningArea = null;
    _listeningMode = null;
    _sendStatus(
      event: 'handler_destroyed',
      listening: false,
      masterOn: false,
      reason: 'service_destroyed',
    );
  }

  @override
  void onNotificationPressed() {
    debugPrint('[HANDLER][${_ts()}] onNotificationPressed');
  }

  @override
  void onNotificationButtonPressed(String id) {
    debugPrint('[HANDLER][${_ts()}] onNotificationButtonPressed id=$id');
  }

  @override
  void onNotificationDismissed() {
    debugPrint('[HANDLER][${_ts()}] onNotificationDismissed');
  }

  @override
  void onReceiveData(dynamic data) async {
    debugPrint(
        '[HANDLER][${_ts()}] onReceiveData: $data (current=$_listeningArea)');

    String? area;
    String? incomingMode;
    TtsUserFilters? incomingFilters;
    var forceRestart = false;
    var clearMode = false;
    var source = 'legacy';

    if (data is Map) {
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
      debugPrint(
          '[HANDLER][${_ts()}] unsupported data type=${data.runtimeType}');
    }

    if (clearMode) {
      await PlateTtsListenerService.stop();
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
        "[HANDLER][${_ts()}] session mode cleared area=${area ?? ''} source=$source",
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
          '[HANDLER][${_ts()}] session disabled: mode="$mode" filters=${filters.toMap()}');
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
          '[HANDLER][${_ts()}] same area="$area" mode="$mode" and listener active → no-op');
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
            '[HANDLER][${_ts()}] listener started: area="$area" mode="$mode" prevArea=$prevArea prevMode=$prevMode source=$source');
      } else {
        _listeningArea = null;
        _listeningMode = mode;
        debugPrint(
            '[HANDLER][${_ts()}] listener start rejected: area="$area" mode="$mode" source=$source');
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
    } catch (e, st) {
      _listeningArea = null;
      _listeningMode = mode;
      debugPrint(
          '[HANDLER][${_ts()}] listener start error: area="$area" mode="$mode" error=$e\n$st');
      _sendStatus(
        event: 'listener_error',
        listening: false,
        masterOn: true,
        area: area,
        mode: mode,
        reason: e.toString(),
        source: source,
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
    } catch (e) {
      debugPrint('[HANDLER][${_ts()}] mode load failed: $e');
      return '';
    }
  }

  Future<TtsUserFilters?> _loadFiltersSafe() async {
    try {
      return await TtsUserFilters.load();
    } catch (e) {
      debugPrint('[HANDLER][${_ts()}] TtsUserFilters.load() failed: $e');
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
    } catch (e) {
      debugPrint('[HANDLER][${_ts()}] send status failed: $e');
    }
  }
}
