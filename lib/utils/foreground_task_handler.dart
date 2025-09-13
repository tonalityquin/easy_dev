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

    PlateTtsListenerService.stop();
  }

  @override
  Future<void> onRepeatEvent(DateTime timestamp) async {}

  @override
  Future<void> onDestroy(DateTime timestamp, bool isServiceDetached) async {
    debugPrint('[HANDLER][${_ts()}] onDestroy: detached=$isServiceDetached → stop listener (area=$_listeningArea)');
    PlateTtsListenerService.stop();
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

    // 필터 들어오면 즉시 반영(리스타트 불필요)
    if (incomingFilters != null) {
      PlateTtsListenerService.updateFilters(incomingFilters);
    }

    // area가 없으면 끝
    if (area == null || area.isEmpty) return;

    if (area == _listeningArea) {
      debugPrint('[HANDLER][${_ts()}] same area="$area" → no-op (filters may have updated)');
      return;
    }

    debugPrint('[HANDLER][${_ts()}] RESUBSCRIBE: $_listeningArea → $area');
    PlateTtsListenerService.stop();
    try {
      PlateTtsListenerService.start(area, force: true);
      _listeningArea = area;
    } catch (e, st) {
      debugPrint('[HANDLER][${_ts()}] start error: $e\n$st');
    }
  }
}
