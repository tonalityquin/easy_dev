import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../../../../../features/account/domain/models/session_account.dart';
import '../../domain/models/voice_channel.dart';
import '../../domain/models/voice_message.dart';
import '../../domain/repositories/voice_message_repository.dart';

class FirestoreVoiceMessageRepository implements VoiceMessageRepository {
  FirestoreVoiceMessageRepository({
    FirebaseFirestore? firestore,
    FirebaseStorage? storage,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _storage = storage ?? FirebaseStorage.instance;

  final FirebaseFirestore _firestore;
  final FirebaseStorage _storage;
  final Uuid _uuid = const Uuid();

  static const int retainedMessageCount = 2;

  CollectionReference<Map<String, dynamic>> _messagesRef(String channelId) {
    return _firestore
        .collection('voice_channels')
        .doc(channelId)
        .collection('messages');
  }

  @override
  Stream<List<voice_message>> watchMessages(String channelId) {
    return _messagesRef(channelId)
        .orderBy('createdAt', descending: true)
        .limit(retainedMessageCount)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map(
                (doc) => voice_message.fromMap(
                  id: doc.id,
                  data: doc.data(),
                ),
              )
              .toList(growable: false),
        );
  }

  @override
  Future<void> sendMessage({
    required VoiceChannel channel,
    required SessionAccount session,
    required File audioFile,
    required int durationMs,
  }) async {
    final messageId = _uuid.v4();
    final extension = p.extension(audioFile.path).isEmpty
        ? '.m4a'
        : p.extension(audioFile.path);
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final storagePath =
        'voice_messages/${channel.areaKey}/${timestamp}_$messageId$extension';
    final ref = _storage.ref(storagePath);
    await ref.putFile(
      audioFile,
      SettableMetadata(contentType: 'audio/mp4'),
    );
    final audioUrl = await ref.getDownloadURL();
    final message = voice_message(
      id: messageId,
      areaKey: channel.areaKey,
      areaName: channel.areaName,
      senderId: session.id,
      senderName: session.displayName,
      senderIdentity: _identityOf(session),
      audioUrl: audioUrl,
      storagePath: storagePath,
      durationMs: durationMs,
      createdAt: DateTime.now(),
    );
    await _messagesRef(channel.id).doc(messageId).set(message.toMap());
    await _firestore.collection('voice_channels').doc(channel.id).set(
      <String, dynamic>{
        'areaKey': channel.areaKey,
        'areaName': channel.areaName,
        'lastMessageAt': FieldValue.serverTimestamp(),
        'lastSenderName': session.displayName,
      },
      SetOptions(merge: true),
    );
    await pruneOldMessages(channel.id);
  }

  @override
  Future<void> deleteMessage(
    String channelId,
    voice_message message,
  ) async {
    await _messagesRef(channelId).doc(message.id).delete();
    if (message.storagePath.isNotEmpty) {
      await _storage.ref(message.storagePath).delete();
    }
  }

  @override
  Future<void> pruneOldMessages(String channelId) async {
    final snapshot = await _messagesRef(channelId)
        .orderBy('createdAt', descending: true)
        .limit(32)
        .get();
    if (snapshot.docs.length <= retainedMessageCount) {
      return;
    }
    for (final doc in snapshot.docs.skip(retainedMessageCount)) {
      final message = voice_message.fromMap(
        id: doc.id,
        data: doc.data(),
      );
      await doc.reference.delete();
      if (message.storagePath.isNotEmpty) {
        try {
          await _storage.ref(message.storagePath).delete();
        } catch (_) {}
      }
    }
  }

  String _identityOf(SessionAccount session) {
    final email = session.email.trim();
    if (email.isNotEmpty) {
      return email;
    }
    return session.displayName.trim().isEmpty
        ? session.id
        : session.displayName.trim();
  }
}
