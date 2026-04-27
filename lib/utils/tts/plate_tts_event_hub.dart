import 'dart:async';

import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import 'parking_requests_dirty_hub.dart';

class PlateTtsEvent {
  PlateTtsEvent({
    required this.area,
    required this.type,
    required this.docId,
    required this.plateNumber,
    required this.location,
    required this.timestampMs,
  });

  final String area;
  final String type;
  final String docId;
  final String plateNumber;
  final String location;
  final int timestampMs;

  static const String kind = 'plate_tts_event_v1';

  static PlateTtsEvent? tryParse(dynamic data) {
    if (data is! Map) return null;

    final k = data['kind'];
    if (k is! String || k != kind) return null;

    final area = data['area'];
    final type = data['type'];
    final docId = data['docId'];
    final plateNumber = data['plateNumber'];
    final location = data['location'];
    final ts = data['ts'];

    if (area is! String || area.trim().isEmpty) return null;
    if (type is! String || type.trim().isEmpty) return null;
    if (docId is! String || docId.trim().isEmpty) return null;

    return PlateTtsEvent(
      area: area.trim(),
      type: type.trim(),
      docId: docId.trim(),
      plateNumber: (plateNumber is String) ? plateNumber.trim() : '',
      location: (location is String) ? location.trim() : '',
      timestampMs: (ts is int) ? ts : DateTime.now().millisecondsSinceEpoch,
    );
  }
}

class PlateTtsEventHub {
  static bool _started = false;
  static final StreamController<PlateTtsEvent> _controller =
      StreamController<PlateTtsEvent>.broadcast();

  static Stream<PlateTtsEvent> get stream => _controller.stream;

  static void ensureStarted() {
    if (_started) return;
    _started = true;
    FlutterForegroundTask.addTaskDataCallback(_onTaskData);
  }

  static void emit(PlateTtsEvent event) {
    _controller.add(event);
  }

  static void emitLocal({
    required String area,
    required String type,
    required String docId,
    required String plateNumber,
    required String location,
    int? timestampMs,
  }) {
    final a = area.trim();
    final t = type.trim();
    final id = docId.trim();
    if (a.isEmpty || t.isEmpty || id.isEmpty) return;
    emit(
      PlateTtsEvent(
        area: a,
        type: t,
        docId: id,
        plateNumber: plateNumber.trim(),
        location: location.trim(),
        timestampMs: timestampMs ?? DateTime.now().millisecondsSinceEpoch,
      ),
    );
  }

  static void _onTaskData(dynamic data) {
    ParkingRequestsDirtyHub.handleTaskData(data);
    final e = PlateTtsEvent.tryParse(data);
    if (e == null) return;
    _controller.add(e);
  }
}
