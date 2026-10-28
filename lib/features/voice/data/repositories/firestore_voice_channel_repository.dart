import '../../../../app/firebase_activity/firebase_activity_monitor.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
    final preferences = await SharedPreferences.getInstance();
    final company = (preferences.getString('division') ?? '').trim();
    if (company.isEmpty) throw StateError('VOICE_COMPANY_REQUIRED');
    final doc = _channels.doc(areaKey);
    await FirebaseActivityMonitor.track(FirebaseActivityKind.set, () => doc.set(
      <String, dynamic>{
        'companyId': company,
        'area': areaName,
        'areaKey': areaKey,
        'areaName': areaName,
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    ), source: 'firestore_voice_channel_repository.set');
    return VoiceChannel(
      id: areaKey,
      areaName: areaName,
      areaKey: areaKey,
    );
  }
}
