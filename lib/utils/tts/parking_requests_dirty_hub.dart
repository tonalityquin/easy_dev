import 'dart:async';

import 'package:flutter/foundation.dart';

class ParkingRequestsDirtyEvent {
  ParkingRequestsDirtyEvent({required this.area, required this.timestampMs});

  final String area;
  final int timestampMs;

  static const String kind = 'parking_requests_dirty_v1';
  static const String prefsKeyPrefix = 'parking_requests_dirty_v1_';

  static ParkingRequestsDirtyEvent? tryParse(dynamic data) {
    if (data is! Map) return null;
    final k = data['kind'];
    if (k is! String || k != kind) return null;

    final area = data['area'];
    final ts = data['ts'];
    if (area is! String || area.trim().isEmpty) return null;

    return ParkingRequestsDirtyEvent(
      area: area.trim(),
      timestampMs: (ts is int) ? ts : DateTime.now().millisecondsSinceEpoch,
    );
  }
}

class ParkingRequestsDirtyHub {
  static bool _started = false;
  static final StreamController<ParkingRequestsDirtyEvent> _controller =
      StreamController<ParkingRequestsDirtyEvent>.broadcast();

  static Stream<ParkingRequestsDirtyEvent> get stream => _controller.stream;

  static void ensureStarted() {
    if (_started) return;
    _started = true;
    debugPrint('[ParkingRequestsDirtyHub] started');
  }

  static void emitLocal({required String area, int? timestampMs}) {
    final a = area.trim();
    if (a.isEmpty) return;
    _controller.add(
      ParkingRequestsDirtyEvent(
        area: a,
        timestampMs: timestampMs ?? DateTime.now().millisecondsSinceEpoch,
      ),
    );
  }

  static void handleTaskData(dynamic data) {
    final e = ParkingRequestsDirtyEvent.tryParse(data);
    if (e == null) return;
    _controller.add(e);
  }
}
