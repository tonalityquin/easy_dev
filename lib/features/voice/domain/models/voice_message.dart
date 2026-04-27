class voice_message {
  const voice_message({
    required this.id,
    required this.areaKey,
    required this.areaName,
    required this.senderId,
    required this.senderName,
    required this.senderIdentity,
    required this.audioUrl,
    required this.storagePath,
    required this.durationMs,
    required this.createdAt,
  });

  final String id;
  final String areaKey;
  final String areaName;
  final String senderId;
  final String senderName;
  final String senderIdentity;
  final String audioUrl;
  final String storagePath;
  final int durationMs;
  final DateTime createdAt;

  Duration get duration => Duration(milliseconds: durationMs);

  factory voice_message.fromMap({
    required String id,
    required Map<String, dynamic> data,
  }) {
    return voice_message(
      id: id,
      areaKey: (data['areaKey'] ?? '').toString(),
      areaName: (data['areaName'] ?? '').toString(),
      senderId: (data['senderId'] ?? '').toString(),
      senderName: (data['senderName'] ?? '').toString(),
      senderIdentity: (data['senderIdentity'] ?? '').toString(),
      audioUrl: (data['audioUrl'] ?? '').toString(),
      storagePath: (data['storagePath'] ?? '').toString(),
      durationMs: _parseDurationMs(data['durationMs']),
      createdAt: _parseCreatedAt(data['createdAt']),
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'areaKey': areaKey,
      'areaName': areaName,
      'senderId': senderId,
      'senderName': senderName,
      'senderIdentity': senderIdentity,
      'audioUrl': audioUrl,
      'storagePath': storagePath,
      'durationMs': durationMs,
      'createdAt': createdAt,
    };
  }

  static int _parseDurationMs(dynamic raw) {
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    return int.tryParse('${raw ?? 0}') ?? 0;
  }

  static DateTime _parseCreatedAt(dynamic raw) {
    if (raw == null) {
      return DateTime.now();
    }
    if (raw is DateTime) {
      return raw;
    }
    if (raw is String) {
      return DateTime.tryParse(raw) ?? DateTime.now();
    }
    if (raw is int) {
      return DateTime.fromMillisecondsSinceEpoch(raw);
    }
    try {
      final converted = (raw as dynamic).toDate();
      if (converted is DateTime) {
        return converted;
      }
    } catch (_) {}
    return DateTime.now();
  }
}
