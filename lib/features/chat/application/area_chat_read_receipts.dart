import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';

import 'chat_area_key.dart';

class AreaChatReadReceiptEvent {
  const AreaChatReadReceiptEvent({
    required this.areaName,
    required this.areaKey,
    required this.readAtMs,
  });

  final String areaName;
  final String areaKey;
  final int readAtMs;
}

class AreaChatReadReceipts {
  AreaChatReadReceipts._();

  static final StreamController<AreaChatReadReceiptEvent> _controller =
      StreamController<AreaChatReadReceiptEvent>.broadcast();

  static Stream<AreaChatReadReceiptEvent> get stream => _controller.stream;

  static String _keyOf(String areaName) {
    return 'area_chat_read_at_${normalizeChatAreaKey(areaName)}';
  }

  static Future<int> readAtMs(String areaName) async {
    final area = areaName.trim();
    if (area.isEmpty) return 0;
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_keyOf(area)) ?? 0;
  }

  static Future<void> markRead(String areaName, {DateTime? at}) async {
    final area = areaName.trim();
    if (area.isEmpty) return;
    final areaKey = normalizeChatAreaKey(area);
    final readAt = at ?? DateTime.now();
    final readAtMs = readAt.millisecondsSinceEpoch;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_keyOf(area), readAtMs);
    _controller.add(
      AreaChatReadReceiptEvent(
        areaName: area,
        areaKey: areaKey,
        readAtMs: readAtMs,
      ),
    );
  }
}
