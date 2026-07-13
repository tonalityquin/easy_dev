import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../account/domain/models/session_account.dart';
import '../../application/chat_account_scope.dart';
import '../../application/chat_area_key.dart';
import '../../domain/models/chat_channel.dart';
import '../../domain/models/chat_message.dart';
import '../../domain/repositories/chat_channel_repository.dart';

class FirestoreChatChannelRepository implements ChatChannelRepository {
  FirestoreChatChannelRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _channels =>
      _firestore.collection('chat_channels');

  @override
  ChatChannel channelForArea({
    required String division,
    required String areaName,
    required bool isHeadquarter,
  }) {
    final cleanDivision = division.trim();
    final cleanArea = isHeadquarter ? headquarterChatAreaName : areaName.trim();
    final companyKey = normalizeChatCompanyKey(cleanDivision);
    final areaKey = isHeadquarter
        ? headquarterChatAreaKey
        : normalizeChatAreaKey(cleanArea);
    final channelType = isHeadquarter
        ? chatChannelTypeHeadquarter
        : chatChannelTypeArea;
    final id = buildChatChannelId(
      division: cleanDivision,
      areaName: cleanArea,
      isHeadquarter: isHeadquarter,
    );
    if (id.isEmpty) {
      throw ArgumentError('채팅 회사 또는 지역 정보가 올바르지 않습니다.');
    }
    return ChatChannel.empty(
      id: id,
      division: cleanDivision,
      companyKey: companyKey,
      channelType: channelType,
      areaName: cleanArea,
      areaKey: areaKey,
    );
  }

  @override
  Future<ChatChannel> ensureForArea({
    required String division,
    required String areaName,
    required bool isHeadquarter,
  }) async {
    final channel = channelForArea(
      division: division,
      areaName: areaName,
      isHeadquarter: isHeadquarter,
    );
    await _channels.doc(channel.id).set(
      <String, dynamic>{
        'division': channel.division,
        'companyKey': channel.companyKey,
        'channelType': channel.channelType,
        'areaKey': channel.areaKey,
        'areaName': channel.areaName,
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
    return channel;
  }

  @override
  Stream<ChatChannel> watchChannel(ChatChannel channel) {
    return _channels.doc(channel.id).snapshots().map((snapshot) {
      final data = snapshot.data();
      if (data == null) return channel;
      final resolved = ChatChannel.fromMap(snapshot.id, data);
      final sameScope = resolved.division == channel.division &&
          resolved.companyKey == channel.companyKey &&
          resolved.channelType == channel.channelType;
      return ChatChannel(
        id: channel.id,
        division: channel.division,
        companyKey: channel.companyKey,
        channelType: channel.channelType,
        areaName: sameScope && resolved.areaName.isNotEmpty
            ? resolved.areaName
            : channel.areaName,
        areaKey: channel.areaKey,
        lastMessageId: resolved.lastMessageId,
        lastMessageText: resolved.lastMessageText,
        lastSenderId: resolved.lastSenderId,
        lastSenderName: resolved.lastSenderName,
        lastSenderIdentity: resolved.lastSenderIdentity,
        lastMessageCreatedAt: resolved.lastMessageCreatedAt,
        messageSeq: resolved.messageSeq,
        messageCount: resolved.messageCount,
        updatedAt: resolved.updatedAt,
        pinnedNotice: resolved.pinnedNotice,
      );
    });
  }

  @override
  Stream<ChatChannelChangeBatch> watchChannelBatchByChannelIds(
    List<String> channelIds,
  ) {
    final ids = channelIds
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList(growable: false)
      ..sort();
    if (ids.isEmpty) {
      return const Stream<ChatChannelChangeBatch>.empty();
    }
    final query = ids.length == 1
        ? _channels.where(FieldPath.documentId, isEqualTo: ids.first)
        : _channels.where(FieldPath.documentId, whereIn: ids);
    return query.snapshots().map((snapshot) {
      final channels = snapshot.docs
          .map((doc) => ChatChannel.fromMap(doc.id, doc.data()))
          .toList(growable: false);
      final changes = snapshot.docChanges
          .map((change) {
            final data = change.doc.data();
            if (data == null) return null;
            return ChatChannelChange(
              type: change.type,
              channel: ChatChannel.fromMap(change.doc.id, data),
            );
          })
          .whereType<ChatChannelChange>()
          .toList(growable: false);
      return ChatChannelChangeBatch(
        isFromCache: snapshot.metadata.isFromCache,
        hasPendingWrites: snapshot.metadata.hasPendingWrites,
        channels: channels,
        changes: changes,
      );
    });
  }

  @override
  Future<void> pinNotice({
    required ChatChannel channel,
    required ChatMessage message,
    required SessionAccount session,
  }) async {
    final accountScope = ChatAccountScope.fromSession(session);
    final sameCompany = accountScope.division == channel.division;
    final canAccess = accountScope.canAccessChannel(
      areaName: channel.areaName,
      isHeadquarterChannel: channel.isHeadquarter,
    );
    final expectedChannelId = buildChatChannelId(
      division: channel.division,
      areaName: channel.areaName,
      isHeadquarter: channel.isHeadquarter,
    );
    if (!sameCompany || !canAccess || channel.id != expectedChannelId) {
      throw StateError('현재 계정은 이 채팅 공지를 변경할 수 없습니다.');
    }
    await _channels.doc(channel.id).set(
      <String, dynamic>{
        'division': channel.division,
        'companyKey': channel.companyKey,
        'channelType': channel.channelType,
        'areaKey': channel.areaKey,
        'areaName': channel.areaName,
        'pinnedNotice': <String, dynamic>{
          'messageId': message.id,
          'seq': message.seq,
          'text': message.text,
          'senderId': message.senderId,
          'senderName': message.senderName,
          'senderIdentity': message.senderIdentity,
          'pinnedBy': session.id,
          'pinnedAt': FieldValue.serverTimestamp(),
        },
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  @override
  Future<void> clearPinnedNotice({
    required ChatChannel channel,
    required SessionAccount session,
  }) async {
    final accountScope = ChatAccountScope.fromSession(session);
    final sameCompany = accountScope.division == channel.division;
    final canAccess = accountScope.canAccessChannel(
      areaName: channel.areaName,
      isHeadquarterChannel: channel.isHeadquarter,
    );
    final expectedChannelId = buildChatChannelId(
      division: channel.division,
      areaName: channel.areaName,
      isHeadquarter: channel.isHeadquarter,
    );
    if (!sameCompany || !canAccess || channel.id != expectedChannelId) {
      throw StateError('현재 계정은 이 채팅 공지를 변경할 수 없습니다.');
    }
    await _channels.doc(channel.id).set(
      <String, dynamic>{
        'pinnedNotice': FieldValue.delete(),
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }
}
