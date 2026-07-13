import 'package:cloud_firestore/cloud_firestore.dart';

import '../../application/chat_area_key.dart';
import 'chat_pinned_notice.dart';

class ChatChannel {
  const ChatChannel({
    required this.id,
    required this.division,
    required this.companyKey,
    required this.channelType,
    required this.areaName,
    required this.areaKey,
    required this.lastMessageId,
    required this.lastMessageText,
    required this.lastSenderId,
    required this.lastSenderName,
    required this.lastSenderIdentity,
    required this.lastMessageCreatedAt,
    required this.messageSeq,
    required this.messageCount,
    required this.updatedAt,
    required this.pinnedNotice,
  });

  final String id;
  final String division;
  final String companyKey;
  final String channelType;
  final String areaName;
  final String areaKey;
  final String lastMessageId;
  final String lastMessageText;
  final String lastSenderId;
  final String lastSenderName;
  final String lastSenderIdentity;
  final DateTime? lastMessageCreatedAt;
  final int messageSeq;
  final int messageCount;
  final DateTime? updatedAt;
  final ChatPinnedNotice? pinnedNotice;

  bool get isHeadquarter => channelType == chatChannelTypeHeadquarter;

  bool get hasMessage => lastMessageId.trim().isNotEmpty && messageSeq > 0;

  factory ChatChannel.empty({
    required String id,
    required String division,
    required String companyKey,
    required String channelType,
    required String areaName,
    required String areaKey,
  }) {
    return ChatChannel(
      id: id,
      division: division,
      companyKey: companyKey,
      channelType: channelType,
      areaName: areaName,
      areaKey: areaKey,
      lastMessageId: '',
      lastMessageText: '',
      lastSenderId: '',
      lastSenderName: '',
      lastSenderIdentity: '',
      lastMessageCreatedAt: null,
      messageSeq: 0,
      messageCount: 0,
      updatedAt: null,
      pinnedNotice: null,
    );
  }

  factory ChatChannel.fromMap(String id, Map<String, dynamic> data) {
    final division = _readString(data['division']);
    final areaName = _readString(data['areaName']);
    final storedAreaKey = _readString(data['areaKey']);
    final storedChannelType = _readString(data['channelType']);
    final channelType = storedChannelType == chatChannelTypeHeadquarter ||
            id.endsWith('|$chatChannelTypeHeadquarter') ||
            storedAreaKey == headquarterChatAreaKey
        ? chatChannelTypeHeadquarter
        : chatChannelTypeArea;
    final areaKey = storedAreaKey.isNotEmpty
        ? storedAreaKey
        : channelType == chatChannelTypeHeadquarter
            ? headquarterChatAreaKey
            : normalizeChatAreaKey(areaName);
    final companyKey = _readString(data['companyKey']).isNotEmpty
        ? _readString(data['companyKey'])
        : normalizeChatCompanyKey(division);
    final rawPinnedNotice = data['pinnedNotice'];
    final seq = _readInt(data['messageSeq']);
    final count = _readInt(data['messageCount']);

    return ChatChannel(
      id: id.trim(),
      division: division,
      companyKey: companyKey,
      channelType: channelType,
      areaName: areaName,
      areaKey: areaKey,
      lastMessageId: _readString(data['lastMessageId']),
      lastMessageText: _readString(data['lastMessageText']),
      lastSenderId: _readString(data['lastSenderId']),
      lastSenderName: _readString(data['lastSenderName']),
      lastSenderIdentity: _readString(data['lastSenderIdentity']),
      lastMessageCreatedAt: _readDateOrNull(data['lastMessageCreatedAt']) ??
          _readDateOrNull(data['updatedAt']),
      messageSeq: seq,
      messageCount: count > 0 ? count : seq,
      updatedAt: _readDateOrNull(data['updatedAt']),
      pinnedNotice: rawPinnedNotice is Map
          ? ChatPinnedNotice.fromMap(
              Map<String, dynamic>.from(rawPinnedNotice),
            )
          : null,
    );
  }

  static String _readString(dynamic value) {
    return value is String ? value.trim() : '';
  }

  static int _readInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value.trim()) ?? 0;
    return 0;
  }

  static DateTime? _readDateOrNull(dynamic value) {
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
    return null;
  }
}

class ChatChannelChange {
  const ChatChannelChange({
    required this.type,
    required this.channel,
  });

  final DocumentChangeType type;
  final ChatChannel channel;
}

class ChatChannelChangeBatch {
  const ChatChannelChangeBatch({
    required this.isFromCache,
    required this.hasPendingWrites,
    required this.channels,
    required this.changes,
  });

  final bool isFromCache;
  final bool hasPendingWrites;
  final List<ChatChannel> channels;
  final List<ChatChannelChange> changes;
}
