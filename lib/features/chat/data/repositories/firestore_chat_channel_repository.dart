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
    return ChatChannel(id: areaKey, areaName: area, areaKey: areaKey);
  }
}
