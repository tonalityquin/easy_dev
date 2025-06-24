import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import '../services/plate_tts_listener_service.dart';

@pragma('vm:entry-point')
class MyTaskHandler implements TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    PlateTtsListenerService.start('someArea');
  }

  @override
  Future<void> onRepeatEvent(DateTime timestamp) async {
    // repeat 호출마다 실행
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isServiceDetached) async {
    PlateTtsListenerService.stop();
  }

  @override
  void onNotificationPressed() {
    // optional
  }

  @override
  void onNotificationButtonPressed(String id) {
    // optional
  }

  @override
  void onNotificationDismissed() {
    // optional
  }

  @override
  void onReceiveData(dynamic data) {
    // optional
  }
}
