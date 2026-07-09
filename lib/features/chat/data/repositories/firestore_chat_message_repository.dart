import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:uuid/uuid.dart';

import '../../../account/domain/models/session_account.dart';
import '../../domain/models/chat_channel.dart';
import '../../domain/models/chat_message.dart';
import '../../domain/repositories/chat_message_repository.dart';

class FirestoreChatMessageRepository implements ChatMessageRepository {
  FirestoreChatMessageRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

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
  Stream<List<ChatMessage>> watchMessages(String channelId, {int limit = 100}) {
    final id = channelId.trim();
    if (id.isEmpty) {
      return const Stream<List<ChatMessage>>.empty();
    }
    return _messagesRef(id)
        .orderBy('createdAt', descending: true)
        .limit(limit)
        .snapshots()
        .map((snapshot) {
      final messages = snapshot.docs
          .map((doc) => ChatMessage.fromMap(doc.id, doc.data()))
          .toList(growable: false);
      return messages.reversed.toList(growable: false);
    });
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
    return _messagesRef(id)
        .orderBy('createdAt', descending: true)
        .limit(limit)
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
    final messageId = _uuid.v4();
    final identity = _identityOf(session);
    final data = <String, dynamic>{
      'id': messageId,
      'areaKey': channel.areaKey,
      'areaName': channel.areaName,
      'senderId': session.id,
      'senderName': session.displayName,
      'senderIdentity': identity,
      'text': clean,
      'createdAt': FieldValue.serverTimestamp(),
    };
    await _messagesRef(channel.id).doc(messageId).set(data);
    await _channelRef(channel.id).set(
      <String, dynamic>{
        'areaKey': channel.areaKey,
        'areaName': channel.areaName,
        'lastMessageId': messageId,
        'lastMessageText': clean,
        'lastSenderId': session.id,
        'lastSenderName': session.displayName,
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
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
