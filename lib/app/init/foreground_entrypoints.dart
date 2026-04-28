import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import '../../shared/tts/application/foreground_task_handler.dart';

@pragma('vm:entry-point')
void myForegroundCallback() {
  debugPrint('[FOREGROUND] setTaskHandler(MyTaskHandler)');
  FlutterForegroundTask.setTaskHandler(MyTaskHandler());
}
