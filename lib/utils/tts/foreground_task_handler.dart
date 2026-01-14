import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';

import 'plate_tts_listener_service.dart';
import 'tts_user_filters.dart';

String _ts() => DateTime.now().toIso8601String();

@pragma('vm:entry-point')
class MyTaskHandler implements TaskHandler {
  String? _listeningArea;
  DateTime? _startedAt;

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
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

    // 초기에는 안전하게 정리만 수행.
    await PlateTtsListenerService.stop();

    // ✅ FG isolate 시작 시에도 prefs 기준으로 필터/마스터를 1회 보정(선택적)
    final f = await _loadFiltersSafe();
    if (f != null) {
      PlateTtsListenerService.updateFilters(f);
      final masterOn = f.parking || f.departure || f.completed;
      await PlateTtsListenerService.setEnabled(masterOn);
      if (!masterOn) {
        await PlateTtsListenerService.stop();
      }
      debugPrint('[HANDLER][${_ts()}] bootstrap filters applied: ${f.toMap()} masterOn=$masterOn');
    }
  }

  @override
  Future<void> onRepeatEvent(DateTime timestamp) async {
    // no-op
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

    // ✅ ttsFilters가 안 넘어오는 케이스(예: area만 전송)에서도 prefs를 로드하여 stale 방지
    incomingFilters ??= await _loadFiltersSafe();

    if (incomingFilters != null) {
      PlateTtsListenerService.updateFilters(incomingFilters);

      final masterOn = incomingFilters.parking || incomingFilters.departure || incomingFilters.completed;
      await PlateTtsListenerService.setEnabled(masterOn);

      if (!masterOn) {
        // ✅ OFF면 수신 자체를 끊음(리스너가 살아있으면 stop)
        await PlateTtsListenerService.stop();
      }

      debugPrint('[HANDLER][${_ts()}] filters applied in FG: ${incomingFilters.toMap()} masterOn=$masterOn');
    }

    // area가 없으면 끝
    if (area == null || area.isEmpty) return;

    if (area == _listeningArea) {
      debugPrint('[HANDLER][${_ts()}] same area="$area" → no-op');
      return;
    }

    // 핸들러는 시작/재구독을 직접 하지 않음(앱에서 start 호출).
    _listeningArea = area;
    debugPrint('[HANDLER][${_ts()}] area updated to "$area" (handler no-op)');
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
