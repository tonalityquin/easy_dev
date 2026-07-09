import 'package:cloud_firestore/cloud_firestore.dart';

import '../../application/chat_area_key.dart';
import '../../domain/models/chat_channel.dart';
import '../../domain/repositories/chat_channel_repository.dart';

class FirestoreChatChannelRepository implements ChatChannelRepository {
  FirestoreChatChannelRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _channels =>
      _firestore.collection('chat_channels');

  @override
  ChatChannel channelForArea(String areaName) {
    final area = areaName.trim();
    final areaKey = normalizeChatAreaKey(area);
    return ChatChannel.empty(id: areaKey, areaName: area, areaKey: areaKey);
  }

  @override
  Future<ChatChannel> ensureForArea(String areaName) async {
    final area = areaName.trim();
    final areaKey = normalizeChatAreaKey(area);
    final doc = _channels.doc(areaKey);
    await doc.set(
      <String, dynamic>{
        'areaKey': areaKey,
        'areaName': area,
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
    return ChatChannel.empty(id: areaKey, areaName: area, areaKey: areaKey);
  }

  @override
  Stream<ChatChannelChangeBatch> watchChannelBatchByAreaKeys(
    List<String> areaKeys,
  ) {
    final keys = areaKeys
        .map((key) => key.trim())
        .where((key) => key.isNotEmpty)
        .toSet()
        .toList(growable: false)
      ..sort();
    if (keys.isEmpty) {
      return const Stream<ChatChannelChangeBatch>.empty();
    }

    final query = keys.length == 1
        ? _channels.where(FieldPath.documentId, isEqualTo: keys.first)
        : _channels.where(FieldPath.documentId, whereIn: keys);

    return query.snapshots().map((snapshot) {
      final channels = snapshot.docs
          .map((doc) => ChatChannel.fromMap(doc.id, doc.data()))
          .toList(growable: false);
      final changes = snapshot.docChanges
          .map((change) {
            final data = change.doc.data();
            if (data == null) {
              return null;
            }
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
}
