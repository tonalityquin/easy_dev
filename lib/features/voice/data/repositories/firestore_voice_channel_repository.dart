import 'package:cloud_firestore/cloud_firestore.dart';

import '../../application/voice_area_key.dart';
import '../../domain/models/voice_channel.dart';
import '../../domain/repositories/voice_channel_repository.dart';

class FirestoreVoiceChannelRepository
    implements VoiceChannelRepository {
  FirestoreVoiceChannelRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _channels =>
      _firestore.collection('voice_channels');

  @override
  Future<VoiceChannel> ensureForArea(String areaName) async {
    final areaKey = normalizeVoiceAreaKey(areaName);
    final doc = _channels.doc(areaKey);
    await doc.set(
      <String, dynamic>{
        'areaKey': areaKey,
        'areaName': areaName,
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
    return VoiceChannel(
      id: areaKey,
      areaName: areaName,
      areaKey: areaKey,
    );
  }
}
