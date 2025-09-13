// lib/utils/foreground_task_handler.dart
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart'; // ✅ FG 이솔레이트에서도 Firebase 초기화

import '../screens/dev_package/debug_package/tts_local_log.dart';
import 'plate_tts_listener_service.dart';
String _ts() => DateTime.now().toIso8601String();

@pragma('vm:entry-point')
class MyTaskHandler implements TaskHandler {
  String? _listeningArea;
  DateTime? _startedAt;

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    _startedAt = DateTime.now();
    debugPrint('[HANDLER][${_ts()}] onStart: starter=$starter at=$_startedAt');

    // ✅ 이 이솔레이트(FG)에서 Firebase 초기화 보장
    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp();
        debugPrint('[HANDLER][${_ts()}] Firebase.initializeApp() done in FG isolate');
      } else {
        debugPrint('[HANDLER][${_ts()}] Firebase already initialized in FG isolate');
      }
    } catch (e, st) {
      debugPrint('[HANDLER][${_ts()}] Firebase init error: $e\n$st');
      // ❗ 중요: FG Firebase 초기화 실패
      await TtsLocalLog.error(
        'FG.firebaseInit',
        'Firebase initialize failed in FG isolate',
        data: {'error': '$e', 'stack': '$st'},
      );
    }

    // 기존 리스너 정리
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

    if (data is Map) {
      final dynamic v = data['area'];
      if (v is String && v.trim().isNotEmpty) {
        area = v.trim();
      } else {
        debugPrint('[HANDLER][${_ts()}] data map has no valid "area": $v → ignore');
        // ❗ 중요: 잘못된 페이로드
        await TtsLocalLog.error(
          'FG.onReceiveData',
          'data map has no valid "area"',
          data: {'payload': '$data'},
        );
      }
    } else if (data is String && data.trim().isNotEmpty) {
      area = data.trim();
    } else {
      debugPrint('[HANDLER][${_ts()}] unsupported data type=${data.runtimeType} → ignore');
      // ❗ 중요: 지원하지 않는 타입
      await TtsLocalLog.error(
        'FG.onReceiveData',
        'unsupported data type',
        data: {'runtimeType': '${data.runtimeType}'},
      );
    }

    if (area == null || area.isEmpty) return;

    if (area == _listeningArea) {
      debugPrint('[HANDLER][${_ts()}] same area="$area" → no-op');
      return;
    }

    debugPrint('[HANDLER][${_ts()}] RESUBSCRIBE: $_listeningArea → $area');
    PlateTtsListenerService.stop();

    try {
      // ✅ FG 강제 시작
      PlateTtsListenerService.start(area, force: true);
      _listeningArea = area;
    } catch (e, st) {
      // ❗ 중요: 리스너 시작 실패
      await TtsLocalLog.error(
        'FG.subscribe',
        'failed to start TTS listener in FG',
        data: {'area': area, 'error': '$e', 'stack': '$st'},
      );
    }
  }
}
