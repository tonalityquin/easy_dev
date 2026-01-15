import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:firebase_core/firebase_core.dart';

import 'plate_local_notification_service.dart';
import 'plate_tts_listener_service.dart';
import 'tts_user_filters.dart';

String _ts() => DateTime.now().toIso8601String();

/// ✅ 포그라운드 서비스 isolate(TaskHandler)에서 Plate Firestore listen + TTS + 로컬 알림까지
/// 직접 수행하도록 리팩터링된 핸들러.
///
/// 요구사항:
/// - 앱 최소화/절전(화면 꺼짐) 상태에서도 이벤트 감지/알림이 유지되어야 함
/// - DashboardSetting의 스위치(입차/출차/완료) ON인 타입만 알림/음성 발생
@pragma('vm:entry-point')
class MyTaskHandler implements TaskHandler {
  String? _listeningArea;
  DateTime? _startedAt;

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    // ✅ 백그라운드 isolate에서 플러그인 사용을 위해 필요
    WidgetsFlutterBinding.ensureInitialized();
    DartPluginRegistrant.ensureInitialized();

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

    // ✅ 로컬 알림 초기화(베스트 에포트). 권한 요청은 UI isolate에서 수행.
    await PlateLocalNotificationService.instance.ensureInitialized();

    // 초기에는 안전하게 정리만 수행.
    await PlateTtsListenerService.stop();

    // ✅ FG isolate 시작 시에도 prefs 기준으로 필터/마스터를 1회 보정
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
    // no-op (Firestore snapshot listener가 이벤트 기반으로 동작)
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

    bool masterOn = true;
    if (incomingFilters != null) {
      PlateTtsListenerService.updateFilters(incomingFilters);

      masterOn = incomingFilters.parking || incomingFilters.departure || incomingFilters.completed;
      await PlateTtsListenerService.setEnabled(masterOn);

      if (!masterOn) {
        // ✅ OFF면 수신 자체를 끊음(리스너가 살아있으면 stop)
        await PlateTtsListenerService.stop();
      }

      debugPrint('[HANDLER][${_ts()}] filters applied in FG: ${incomingFilters.toMap()} masterOn=$masterOn');
    }

    // 마스터 OFF면 area가 와도 구독하지 않음
    if (!masterOn) return;

    // area가 없으면(또는 비면) 시작 조건이 성립하지 않음
    if (area == null || area.isEmpty) return;

    // area 변경(또는 최초) 시: FG isolate에서 직접 listen 시작
    if (_listeningArea != area) {
      _listeningArea = area;
      debugPrint('[HANDLER][${_ts()}] start listening in FG isolate: area="$area"');
      PlateTtsListenerService.start(area, force: true);
      return;
    }

    // 동일 area는 no-op
    debugPrint('[HANDLER][${_ts()}] same area="$area" → no-op');
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
