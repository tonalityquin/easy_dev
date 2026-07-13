import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';

class AreaChatReadReceiptEvent {
  const AreaChatReadReceiptEvent({
    required this.channelId,
    required this.areaName,
    required this.userId,
    required this.readAtMs,
    required this.readSeq,
  });

  final String channelId;
  final String areaName;
  final String userId;
  final int readAtMs;
  final int readSeq;
}

class AreaChatReadReceipts {
  AreaChatReadReceipts._();

  static final StreamController<AreaChatReadReceiptEvent> _controller =
      StreamController<AreaChatReadReceiptEvent>.broadcast();

  static Stream<AreaChatReadReceiptEvent> get stream => _controller.stream;

  static String _safeKey(String value, String fallback) {
    final clean = value.trim();
    if (clean.isEmpty) return fallback;
    return Uri.encodeComponent(clean);
  }

  static String _readAtKeyOf(String channelId, String userId) {
    return 'area_chat_read_at_v3_${_safeKey(userId, 'anonymous')}_${_safeKey(channelId, 'unknown')}';
  }

  static String _readSeqKeyOf(String channelId, String userId) {
    return 'area_chat_read_seq_v3_${_safeKey(userId, 'anonymous')}_${_safeKey(channelId, 'unknown')}';
  }

  static Future<int> readAtMs(
    String channelId, {
    String userId = '',
  }) async {
    final id = channelId.trim();
    if (id.isEmpty) return 0;
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_readAtKeyOf(id, userId)) ?? 0;
  }

  static Future<int> readSeq(
    String channelId, {
    String userId = '',
  }) async {
    final id = channelId.trim();
    if (id.isEmpty) return 0;
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_readSeqKeyOf(id, userId)) ?? 0;
  }

  static Future<void> markRead({
    required String channelId,
    required String areaName,
    required String userId,
    DateTime? at,
    int? seq,
  }) async {
    final id = channelId.trim();
    final area = areaName.trim();
    final cleanUserId = userId.trim();
    if (id.isEmpty || area.isEmpty || cleanUserId.isEmpty) return;

    final prefs = await SharedPreferences.getInstance();
    final nextSeq = seq == null ? null : seq < 0 ? 0 : seq;
    final currentSeq = prefs.getInt(_readSeqKeyOf(id, cleanUserId)) ?? 0;
    if (nextSeq != null && nextSeq <= currentSeq) return;

    final readAt = at ?? DateTime.now();
    final readAtMs = readAt.millisecondsSinceEpoch;
    await prefs.setInt(_readAtKeyOf(id, cleanUserId), readAtMs);
    if (nextSeq != null) {
      await prefs.setInt(_readSeqKeyOf(id, cleanUserId), nextSeq);
    }

    _controller.add(
      AreaChatReadReceiptEvent(
        channelId: id,
        areaName: area,
        userId: cleanUserId,
        readAtMs: readAtMs,
        readSeq: nextSeq ?? currentSeq,
      ),
    );
  }
}
