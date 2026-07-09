import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';

import 'chat_area_key.dart';

class AreaChatReadReceiptEvent {
  const AreaChatReadReceiptEvent({
    required this.areaName,
    required this.areaKey,
    required this.readAtMs,
    required this.readSeq,
  });

  final String areaName;
  final String areaKey;
  final int readAtMs;
  final int readSeq;
}

class AreaChatReadReceipts {
  AreaChatReadReceipts._();

  static final StreamController<AreaChatReadReceiptEvent> _controller =
      StreamController<AreaChatReadReceiptEvent>.broadcast();

  static Stream<AreaChatReadReceiptEvent> get stream => _controller.stream;

  static String _readAtKeyOf(String areaName) {
    return 'area_chat_read_at_${normalizeChatAreaKey(areaName)}';
  }

  static String _readSeqKeyOf(String areaName) {
    return 'area_chat_read_seq_${normalizeChatAreaKey(areaName)}';
  }

  static Future<int> readAtMs(String areaName) async {
    final area = areaName.trim();
    if (area.isEmpty) return 0;
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_readAtKeyOf(area)) ?? 0;
  }

  static Future<int> readSeq(String areaName) async {
    final area = areaName.trim();
    if (area.isEmpty) return 0;
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_readSeqKeyOf(area)) ?? 0;
  }

  static Future<void> markRead(
    String areaName, {
    DateTime? at,
    int? seq,
  }) async {
    final area = areaName.trim();
    if (area.isEmpty) return;
    final areaKey = normalizeChatAreaKey(area);
    final readAt = at ?? DateTime.now();
    final readAtMs = readAt.millisecondsSinceEpoch;
    final nextSeq = seq == null ? null : seq < 0 ? 0 : seq;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_readAtKeyOf(area), readAtMs);
    if (nextSeq != null) {
      final currentSeq = prefs.getInt(_readSeqKeyOf(area)) ?? 0;
      if (nextSeq >= currentSeq) {
        await prefs.setInt(_readSeqKeyOf(area), nextSeq);
      }
    }
    _controller.add(
      AreaChatReadReceiptEvent(
        areaName: area,
        areaKey: areaKey,
        readAtMs: readAtMs,
        readSeq: prefs.getInt(_readSeqKeyOf(area)) ?? 0,
      ),
    );
  }
}
