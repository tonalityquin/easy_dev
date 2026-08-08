import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../../../app/models/capability.dart';
import '../../../domain/repositories/area_repo_package/area_repository.dart';

class FirestoreAreaRepository implements AreaRepository {
  FirestoreAreaRepository({
    FirebaseFirestore? firestore,
  }) : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  AreaRecord? _toAreaRecord(Map<String, dynamic>? data) {
    if (data == null) return null;

    final name = (data['name'] ?? '').toString().trim();
    if (name.isEmpty) return null;

    final division = (data['division'] ?? 'default').toString().trim();
    final rawEmail = data['email'];
    final email = rawEmail is String ? rawEmail.trim() : '';
    final rawInvite = data['invite'];
    final invite = rawInvite is String ? rawInvite.trim() : '';
    final rawCommunication = data['communication'];
    final communication =
        rawCommunication is String ? rawCommunication.trim() : '';
    final capabilities = Cap.fromDynamic(data['capabilities']);
    final rawModes = data['modes'];
    final modes = rawModes is List
        ? rawModes
            .whereType<String>()
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toSet()
            .toList(growable: false)
        : const <String>[];

    return AreaRecord(
      name: name,
      division: division.isEmpty ? 'default' : division,
      email: email,
      invite: invite,
      communication: communication,
      capabilities: capabilities,
      modes: modes,
      isHeadquarter: data['isHeadquarter'] == true,
    );
  }

  @override
  Future<bool> isHeadquarter({
    required String division,
    required String area,
  }) async {
    final trimmedDivision = division.trim();
    final trimmedArea = area.trim();

    if (trimmedDivision.isEmpty || trimmedArea.isEmpty) {
      return false;
    }

    final docId = '$trimmedDivision-$trimmedArea';
    final doc = await _firestore.collection('areas').doc(docId).get();

    return doc.exists && (doc.data()?['isHeadquarter'] == true);
  }

  @override
  Future<AreaRecord?> getAreaByName(
    String areaName, {
    String? division,
  }) async {
    final trimmedArea = areaName.trim();
    final trimmedDivision = division?.trim() ?? '';
    if (trimmedArea.isEmpty) return null;

    if (trimmedDivision.isNotEmpty && trimmedDivision != 'default') {
      final docId = '$trimmedDivision-$trimmedArea';
      final doc = await _firestore.collection('areas').doc(docId).get();
      if (!doc.exists) return null;

      final record = _toAreaRecord(doc.data());
      if (record == null) return null;
      if (record.name != trimmedArea || record.division != trimmedDivision) {
        return null;
      }
      return record;
    }

    final qs = await _firestore
        .collection('areas')
        .where('name', isEqualTo: trimmedArea)
        .limit(1)
        .get();

    if (qs.docs.isEmpty) return null;
    return _toAreaRecord(qs.docs.first.data());
  }

  @override
  Future<List<AreaRecord>> getAreasByDivision(String division) async {
    final trimmedDivision = division.trim();

    if (trimmedDivision.isEmpty) {
      return const <AreaRecord>[];
    }

    final qs = await _firestore
        .collection('areas')
        .where('division', isEqualTo: trimmedDivision)
        .get();

    final records = qs.docs
        .map((doc) => _toAreaRecord(doc.data()))
        .whereType<AreaRecord>()
        .toList();

    records.sort((a, b) => a.name.compareTo(b.name));
    return records;
  }

  @override
  Future<List<String>> getAreaNamesByDivision(String division) async {
    final records = await getAreasByDivision(division);
    return records.map((e) => e.name).toList(growable: false);
  }
}
