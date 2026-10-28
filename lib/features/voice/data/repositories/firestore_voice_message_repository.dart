import '../../../../app/firebase_activity/firebase_activity_monitor.dart';
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
    return FirebaseActivityMonitor.observe(
      _messagesRef(channelId)
        .orderBy('createdAt', descending: true)
        .limit(retainedMessageCount)
        .snapshots(),
      origin: 'voice.messages.snapshots',
    ).map(
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
    await FirebaseActivityMonitor.track(FirebaseActivityKind.storage, () => ref.putFile(
      audioFile,
      SettableMetadata(contentType: 'audio/mp4'),
    ), source: 'firestore_voice_message_repository.putFile');
    final audioUrl = await FirebaseActivityMonitor.track(FirebaseActivityKind.storage, () => ref.getDownloadURL(), source: 'firestore_voice_message_repository.getDownloadURL');
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
    await FirebaseActivityMonitor.track(FirebaseActivityKind.set, () => _messagesRef(channel.id).doc(messageId).set(<String, dynamic>{
      ...message.toMap(),
      'companyId': session.companyId,
      'area': channel.areaName,
    }), source: 'firestore_voice_message_repository.set');
    await FirebaseActivityMonitor.track(FirebaseActivityKind.set, () => _firestore.collection('voice_channels').doc(channel.id).set(
      <String, dynamic>{
        'companyId': session.companyId,
        'area': channel.areaName,
        'areaKey': channel.areaKey,
        'areaName': channel.areaName,
        'lastMessageAt': FieldValue.serverTimestamp(),
        'lastSenderName': session.displayName,
      },
      SetOptions(merge: true),
    ), source: 'firestore_voice_message_repository.set');
    await pruneOldMessages(channel.id);
  }

  @override
  Future<void> deleteMessage(
    String channelId,
    voice_message message,
  ) async {
    await FirebaseActivityMonitor.track(FirebaseActivityKind.delete, () => _messagesRef(channelId).doc(message.id).delete(), source: 'firestore_voice_message_repository.delete');
    if (message.storagePath.isNotEmpty) {
      await FirebaseActivityMonitor.track(FirebaseActivityKind.storage, () => _storage.ref(message.storagePath).delete(), source: 'firestore_voice_message_repository.delete');
    }
  }

  @override
  Future<void> pruneOldMessages(String channelId) async {
    final snapshot = await FirebaseActivityMonitor.track(FirebaseActivityKind.read, () => _messagesRef(channelId)
        .orderBy('createdAt', descending: true)
        .limit(32)
        .get(), source: 'firestore_voice_message_repository.get');
    if (snapshot.docs.length <= retainedMessageCount) {
      return;
    }
    for (final doc in snapshot.docs.skip(retainedMessageCount)) {
      final message = voice_message.fromMap(
        id: doc.id,
        data: doc.data(),
      );
      try {
        await FirebaseActivityMonitor.track(FirebaseActivityKind.delete, () => doc.reference.delete(), source: 'firestore_voice_message_repository.delete');
      } on FirebaseException catch (error) {
        if (error.code == 'permission-denied') {
          continue;
        }
        rethrow;
      }
      if (message.storagePath.isNotEmpty) {
        try {
          await FirebaseActivityMonitor.track(FirebaseActivityKind.storage, () => _storage.ref(message.storagePath).delete(), source: 'firestore_voice_message_repository.delete');
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
