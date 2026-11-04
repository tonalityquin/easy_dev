import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import 'firebase_activity_meter.dart';

class FirebaseActivityBridge {
  FirebaseActivityBridge._();

  static const String eventKind = 'firebase_activity_v1';
  static const String lifecycleKind = 'firebase_activity_lifecycle_v1';
  static bool _receiverAttached = false;

  static void ensureMainReceiver() {
    if (_receiverAttached) return;
    _receiverAttached = true;
    FlutterForegroundTask.addTaskDataCallback(_onTaskData);
  }

  static void startForeground() {
    final meter = FirebaseActivityMeter.instance;
    meter.outbound = _sendEvent;
    _sendLifecycle('started', meter.sessionId);
  }

  static void stopForeground() {
    final meter = FirebaseActivityMeter.instance;
    meter.outbound = null;
    _sendLifecycle('ended', meter.sessionId);
  }

  static void _sendLifecycle(String phase, String sessionId) {
    try {
      FlutterForegroundTask.sendDataToMain(<String, dynamic>{
        'kind': lifecycleKind,
        'phase': phase,
        'sessionId': sessionId,
      });
    } catch (error) {
      debugPrint('[FIREBASE_ACTIVITY] lifecycle_delivery_failed type=${error.runtimeType}');
    }
  }

  static void _sendEvent(FirebaseActivityEvent event) {
    try {
      FlutterForegroundTask.sendDataToMain(<String, dynamic>{
        'kind': eventKind,
        'eventId': event.eventId,
        'sessionId': event.sessionId,
        'timestampMs': event.time.millisecondsSinceEpoch,
        'service': event.service,
        'operation': event.operation,
        'source': event.source,
        'result': event.result,
        'elapsedMs': event.elapsedMs,
        'operationId': event.operationId,
        'documents': event.documents,
        'bytes': event.bytes,
        'fromCache': event.fromCache,
        'committedWrites': event.committedWrites,
        'committedDeletes': event.committedDeletes,
        'detail': event.detail,
      });
    } catch (error) {
      debugPrint('[FIREBASE_ACTIVITY] event_delivery_failed type=${error.runtimeType}');
    }
  }

  static void _onTaskData(dynamic data) {
    if (data is! Map) return;
    final kind = data['kind'];
    if (kind == eventKind) {
      FirebaseActivityMeter.instance.acceptRemote(data);
    } else if (kind == lifecycleKind && data['phase'] == 'ended') {
      FirebaseActivityMeter.instance.remoteSessionEnded(
        (data['sessionId'] ?? '').toString(),
      );
    }
  }
}
