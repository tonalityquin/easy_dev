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

    // 핸들러는 PlateTTS를 직접 시작하지 않습니다. (앱에서 시작)
    // 초기에는 안전하게 정리만 수행.
    PlateTtsListenerService.stop();
  }

  @override
  Future<void> onRepeatEvent(DateTime timestamp) async {
    // no-op: 반복 이벤트에서도 PlateTTS 구독/시작을 건드리지 않습니다.
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isServiceDetached) async {
    debugPrint('[HANDLER][${_ts()}] onDestroy: detached=$isServiceDetached → stop listener (area=$_listeningArea)');
    // 서비스 종료 시에는 안전하게 정리
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

    // 필터 들어오면 즉시 반영(구독 자체는 앱이 관리)
    if (incomingFilters != null) {
      PlateTtsListenerService.updateFilters(incomingFilters);
    }

    // area가 없으면 끝
    if (area == null || area.isEmpty) return;

    if (area == _listeningArea) {
      debugPrint('[HANDLER][${_ts()}] same area="$area" → no-op (filters may have updated)');
      return;
    }

    // 🔁 기존: stop → start(area, force:true)
    // ✅ 변경: 핸들러는 시작/재구독을 하지 않음. 앱(UserState)에서만 시작하도록 위임.
    _listeningArea = area;
    debugPrint('[HANDLER][${_ts()}] area updated to "$area" (app-driven start only; handler no-op)');
  }
}
