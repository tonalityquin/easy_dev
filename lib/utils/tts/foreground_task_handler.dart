import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'plate_local_notification_service.dart';
import 'plate_tts_listener_service.dart';
import 'tts_user_filters.dart';
import 'tts_ownership.dart';

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
        debugPrint('[HANDLER][${_ts()}] Firebase.initializeApp() done in FG isolate');
      } else {
        debugPrint('[HANDLER][${_ts()}] Firebase already initialized in FG isolate');
      }
    } catch (e, st) {
      debugPrint('[HANDLER][${_ts()}] Firebase init error: $e\n$st');
    }


    await PlateLocalNotificationService.instance.ensureInitialized();


    await PlateTtsListenerService.stop();


    final f = await _loadFiltersSafe();
    if (f != null) {
      PlateTtsListenerService.updateFilters(f);
      String mode = '';
      try {
        final prefs = await SharedPreferences.getInstance();
        mode = (prefs.getString('mode') ?? '').trim();
      } catch (e) {
        debugPrint('[HANDLER][${_ts()}] mode load failed: $e');
      }

      final isTablet = mode == 'tablet';
      final completedOk = f.completed && isTablet;
      final masterOn = (isTablet ? f.departure : (f.parking || f.departure)) || completedOk;
      _listeningMode = mode;

      await PlateTtsListenerService.setEnabled(masterOn);
      if (!masterOn) {
        await PlateTtsListenerService.stop();
      }
      debugPrint('[HANDLER][${_ts()}] bootstrap filters applied: ${f.toMap()} masterOn=$masterOn');
    }
  }

  @override
  Future<void> onRepeatEvent(DateTime timestamp) async {

  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isServiceDetached) async {
    debugPrint('[HANDLER][${_ts()}] onDestroy: detached=$isServiceDetached → stop listener (area=$_listeningArea)');
    await PlateTtsListenerService.stop();
    _listeningArea = null;
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
    debugPrint('[HANDLER][${_ts()}] onReceiveData: $data (current=$_listeningArea)');

    String? area;
    TtsUserFilters? incomingFilters;

    if (data is Map) {
      final vArea = data['area'];
      if (vArea is String && vArea.trim().isNotEmpty) {
        area = vArea.trim();
      }
      final vFilters = data['ttsFilters'];
      if (vFilters is Map) {
        incomingFilters = TtsUserFilters.fromMap(vFilters);
      }
    } else if (data is String && data.trim().isNotEmpty) {
      area = data.trim();
    } else {
      debugPrint('[HANDLER][${_ts()}] unsupported data type=${data.runtimeType}');
    }


    incomingFilters ??= await _loadFiltersSafe();

    bool masterOn = true;
    if (incomingFilters != null) {
      PlateTtsListenerService.updateFilters(incomingFilters);

      String mode = '';
      try {
        final prefs = await SharedPreferences.getInstance();
        mode = (prefs.getString('mode') ?? '').trim();
      } catch (e) {
        debugPrint('[HANDLER][${_ts()}] mode load failed: $e');
      }

      final isTablet = mode == 'tablet';
      final completedOk = incomingFilters.completed && isTablet;
      masterOn = (isTablet ? incomingFilters.departure : (incomingFilters.parking || incomingFilters.departure)) || completedOk;

      await PlateTtsListenerService.setEnabled(masterOn);

      if (!masterOn) {

        await PlateTtsListenerService.stop();
      }

      debugPrint('[HANDLER][${_ts()}] filters applied in FG: ${incomingFilters.toMap()} masterOn=$masterOn');
    }


    if (!masterOn) return;


    if (area == null || area.isEmpty) return;


    String modeForListen = '';
    try {
      final prefs = await SharedPreferences.getInstance();
      modeForListen = (prefs.getString('mode') ?? '').trim();
    } catch (e) {
      debugPrint('[HANDLER][${_ts()}] mode load failed: $e');
    }

    final modeChanged = (_listeningMode ?? '') != modeForListen;

    if (_listeningArea != area || modeChanged) {
      final prevArea = _listeningArea;
      final prevMode = _listeningMode;
      _listeningArea = area;
      _listeningMode = modeForListen;
      debugPrint('[HANDLER][${_ts()}] start listening in FG isolate: area="$area" mode="$modeForListen" (prevArea=$prevArea prevMode=$prevMode)');
      PlateTtsListenerService.start(area, force: true);
      return;
    }

    debugPrint('[HANDLER][${_ts()}] same area="$area" mode="$modeForListen" → no-op');
  }

  Future<TtsUserFilters?> _loadFiltersSafe() async {
    try {
      return await TtsUserFilters.load();
    } catch (e) {
      debugPrint('[HANDLER][${_ts()}] TtsUserFilters.load() failed: $e');
      return null;
    }
  }
}
