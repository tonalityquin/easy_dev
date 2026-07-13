import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:uuid/uuid.dart';

import '../../../account/domain/models/session_account.dart';
import '../../application/chat_account_scope.dart';
import '../../application/chat_area_key.dart';
import '../../application/chat_search_tokens.dart';
import '../../domain/models/chat_channel.dart';
import '../../domain/models/chat_message.dart';
import '../../domain/models/chat_message_page.dart';
import '../../domain/models/chat_search_index_batch.dart';
import '../../domain/models/chat_search_page.dart';
import '../../domain/repositories/chat_message_repository.dart';

class FirestoreChatMessageRepository implements ChatMessageRepository {
  FirestoreChatMessageRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  static const int searchTokenVersion = 1;

  final FirebaseFirestore _firestore;
  final Uuid _uuid = const Uuid();

  CollectionReference<Map<String, dynamic>> _messagesRef(String channelId) {
    return _firestore
        .collection('chat_channels')
        .doc(channelId)
        .collection('messages');
  }

  DocumentReference<Map<String, dynamic>> _channelRef(String channelId) {
    return _firestore.collection('chat_channels').doc(channelId);
  }

  @override
  Stream<List<ChatMessage>> watchLatestMessages(
    String channelId, {
    int limit = 10,
  }) {
    final id = channelId.trim();
    if (id.isEmpty) {
      return const Stream<List<ChatMessage>>.empty();
    }
    final safeLimit = limit <= 0 ? 10 : limit;
    return _messagesRef(id)
        .orderBy('seq', descending: true)
        .limit(safeLimit)
        .snapshots()
        .map((snapshot) {
      final messages = snapshot.docs
          .map((doc) => ChatMessage.fromMap(doc.id, doc.data()))
          .toList(growable: false);
      return messages.reversed.toList(growable: false);
    });
  }

  @override
  Future<ChatMessagePage> fetchOlderMessages(
    String channelId, {
    required int beforeSeq,
    int limit = 10,
  }) async {
    final id = channelId.trim();
    if (id.isEmpty || beforeSeq <= 1) {
      return const ChatMessagePage(
        messages: <ChatMessage>[],
        hasMore: false,
      );
    }

    final safeLimit = limit <= 0 ? 10 : limit;
    final snapshot = await _messagesRef(id)
        .where('seq', isLessThan: beforeSeq)
        .orderBy('seq', descending: true)
        .limit(safeLimit + 1)
        .get();
    final hasMore = snapshot.docs.length > safeLimit;
    final messages = snapshot.docs
        .take(safeLimit)
        .map((doc) => ChatMessage.fromMap(doc.id, doc.data()))
        .toList()
        .reversed
        .toList(growable: false);

    return ChatMessagePage(
      messages: messages,
      hasMore: hasMore,
    );
  }

  @override
  Future<ChatSearchPage> searchMessages(
    String channelId, {
    required String query,
    int? beforeSeq,
    int limit = 10,
  }) async {
    final id = channelId.trim();
    final terms = chatSearchTerms(query);
    final token = chatServerSearchToken(query);
    if (id.isEmpty || terms.isEmpty || token.isEmpty) {
      return const ChatSearchPage(
        messages: <ChatMessage>[],
        nextBeforeSeq: null,
        hasMore: false,
        scannedCount: 0,
      );
    }

    final safeLimit = limit <= 0 ? 10 : limit;
    Query<Map<String, dynamic>> firestoreQuery = _messagesRef(id)
        .where('searchTokens', arrayContains: token)
        .orderBy('seq', descending: true);

    if (beforeSeq != null && beforeSeq > 0) {
      firestoreQuery = firestoreQuery.where('seq', isLessThan: beforeSeq);
    }

    final snapshot = await firestoreQuery.limit(safeLimit + 1).get();
    final selected = snapshot.docs.take(safeLimit).toList(growable: false);
    final messages = selected
        .map((doc) => ChatMessage.fromMap(doc.id, doc.data()))
        .where((message) {
          final source = normalizeChatSearchText(
            '${message.senderName} ${message.senderIdentity} ${message.text}',
          );
          return terms.every(source.contains);
        })
        .toList(growable: false)
      ..sort((a, b) => a.seq.compareTo(b.seq));

    final nextBeforeSeq = selected.isEmpty
        ? null
        : _readInt(selected.last.data()['seq']);

    return ChatSearchPage(
      messages: messages,
      nextBeforeSeq: nextBeforeSeq,
      hasMore: snapshot.docs.length > safeLimit && nextBeforeSeq != null,
      scannedCount: selected.length,
    );
  }

  @override
  Future<ChatSearchIndexBatch> indexSearchHistory(
    String channelId, {
    int? beforeSeq,
    int limit = 50,
  }) async {
    final id = channelId.trim();
    if (id.isEmpty) {
      return const ChatSearchIndexBatch(
        nextBeforeSeq: null,
        hasMore: false,
        scannedCount: 0,
        updatedCount: 0,
      );
    }

    final safeLimit = limit <= 0 ? 50 : limit;
    Query<Map<String, dynamic>> query =
        _messagesRef(id).orderBy('seq', descending: true);
    if (beforeSeq != null && beforeSeq > 0) {
      query = query.where('seq', isLessThan: beforeSeq);
    }

    final snapshot = await query.limit(safeLimit + 1).get();
    final selected = snapshot.docs.take(safeLimit).toList(growable: false);
    final batch = _firestore.batch();
    var updatedCount = 0;

    for (final doc in selected) {
      final data = doc.data();
      final currentVersion = _readInt(data['searchTokenVersion']);
      final currentTokens = data['searchTokens'];
      if (currentVersion >= searchTokenVersion && currentTokens is List) {
        continue;
      }

      final tokens = buildCompactChatSearchTokens(
        text: _readString(data['text']),
        senderName: _readString(data['senderName']),
        senderIdentity: _readString(data['senderIdentity']),
      );
      batch.update(doc.reference, <String, dynamic>{
        'searchTokens': tokens,
        'searchTokenVersion': searchTokenVersion,
      });
      updatedCount += 1;
    }

    if (updatedCount > 0) {
      await batch.commit();
    }

    final nextBeforeSeq = selected.isEmpty
        ? null
        : _readInt(selected.last.data()['seq']);

    return ChatSearchIndexBatch(
      nextBeforeSeq: nextBeforeSeq,
      hasMore: snapshot.docs.length > safeLimit && nextBeforeSeq != null,
      scannedCount: selected.length,
      updatedCount: updatedCount,
    );
  }

  @override
  Stream<ChatMessageChangeBatch> watchRecentChanges(
    String channelId, {
    int limit = 20,
  }) {
    final id = channelId.trim();
    if (id.isEmpty) {
      return const Stream<ChatMessageChangeBatch>.empty();
    }
    final safeLimit = limit <= 0 ? 20 : limit;
    return _messagesRef(id)
        .orderBy('createdAt', descending: true)
        .limit(safeLimit)
        .snapshots()
        .map((snapshot) {
      final changes = snapshot.docChanges
          .map((change) {
            final data = change.doc.data();
            if (data == null) {
              return null;
            }
            return ChatMessageChange(
              type: change.type,
              message: ChatMessage.fromMap(change.doc.id, data),
            );
          })
          .whereType<ChatMessageChange>()
          .toList(growable: false);
      return ChatMessageChangeBatch(
        isFromCache: snapshot.metadata.isFromCache,
        hasPendingWrites: snapshot.metadata.hasPendingWrites,
        changes: changes,
      );
    });
  }

  @override
  Future<void> sendMessage({
    required ChatChannel channel,
    required SessionAccount session,
    required String text,
  }) async {
    final clean = text.trim();
    if (clean.isEmpty) return;

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
      throw StateError('현재 계정은 이 채팅 채널에 메시지를 보낼 수 없습니다.');
    }

    final messageId = _uuid.v4();
    final identity = _identityOf(session);
    final searchTokens = buildCompactChatSearchTokens(
      text: clean,
      senderName: session.displayName,
      senderIdentity: identity,
    );
    final channelDoc = _channelRef(channel.id);
    final messageDoc = _messagesRef(channel.id).doc(messageId);

    await _firestore.runTransaction((transaction) async {
      final channelSnapshot = await transaction.get(channelDoc);
      final currentSeq = _readInt(channelSnapshot.data()?['messageSeq']);
      final nextSeq = currentSeq + 1;
      final messageData = <String, dynamic>{
        'id': messageId,
        'channelId': channel.id,
        'division': channel.division,
        'companyKey': channel.companyKey,
        'channelType': channel.channelType,
        'areaKey': channel.areaKey,
        'areaName': channel.areaName,
        'seq': nextSeq,
        'senderId': session.id,
        'senderName': session.displayName,
        'senderIdentity': identity,
        'text': clean,
        'searchTokens': searchTokens,
        'searchTokenVersion': searchTokenVersion,
        'createdAt': FieldValue.serverTimestamp(),
      };
      final channelData = <String, dynamic>{
        'division': channel.division,
        'companyKey': channel.companyKey,
        'channelType': channel.channelType,
        'areaKey': channel.areaKey,
        'areaName': channel.areaName,
        'lastMessageId': messageId,
        'lastMessageText': clean,
        'lastSenderId': session.id,
        'lastSenderName': session.displayName,
        'lastSenderIdentity': identity,
        'lastMessageCreatedAt': FieldValue.serverTimestamp(),
        'messageSeq': nextSeq,
        'messageCount': nextSeq,
        'updatedAt': FieldValue.serverTimestamp(),
      };
      transaction.set(messageDoc, messageData);
      transaction.set(channelDoc, channelData, SetOptions(merge: true));
    });
  }

  int _readInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value.trim()) ?? 0;
    return 0;
  }

  String _readString(dynamic value) {
    return value is String ? value.trim() : '';
  }

  String _identityOf(SessionAccount session) {
    final position = session.position?.trim() ?? '';
    final role = session.role.trim();
    if (position.isNotEmpty && role.isNotEmpty) {
      return '$position · $role';
    }
    if (position.isNotEmpty) return position;
    if (role.isNotEmpty) return role;
    return session.isTablet ? '태블릿' : '사용자';
  }
}
