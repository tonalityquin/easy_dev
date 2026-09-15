import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../../../app/models/capability.dart';
import '../../../../../shared/area_remote_settings/application/area_snapshot_persistence.dart';
import '../../../domain/repositories/area_repo_package/area_repository.dart';

class FirestoreAreaRepository implements AreaRepository {
  FirestoreAreaRepository({
    FirebaseFirestore? firestore,
  }) : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  Object? _normalizeRawValue(Object? value) {
    if (value == null ||
        value is String ||
        value is num ||
        value is bool) {
      return value;
    }
    if (value is Timestamp) {
      return <String, Object?>{
        '__type': 'timestamp',
        'value': value.toDate().toUtc().toIso8601String(),
      };
    }
    if (value is GeoPoint) {
      return <String, Object?>{
        '__type': 'geo_point',
        'latitude': value.latitude,
        'longitude': value.longitude,
      };
    }
    if (value is DocumentReference) {
      return <String, Object?>{
        '__type': 'document_reference',
        'path': value.path,
      };
    }
    if (value is DateTime) {
      return <String, Object?>{
        '__type': 'date_time',
        'value': value.toUtc().toIso8601String(),
      };
    }
    if (value is Map) {
      final result = <String, Object?>{};
      for (final entry in value.entries) {
        result[entry.key.toString()] = _normalizeRawValue(entry.value);
      }
      return result;
    }
    if (value is Iterable) {
      return value.map(_normalizeRawValue).toList(growable: false);
    }
    return value.toString();
  }

  String _encodeRawData(Map<String, dynamic> data) {
    return jsonEncode(_normalizeRawValue(data));
  }

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
    final rawWorkRules = data['workRules'];
    final workRules = rawWorkRules is List
        ? rawWorkRules
            .whereType<String>()
            .map((value) => value.trim())
            .where((value) => value.isNotEmpty)
            .toList(growable: false)
        : const <String>[];
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
      workRules: workRules,
      capabilities: capabilities,
      modes: modes,
      isHeadquarter: data['isHeadquarter'] == true,
      rawJson: _encodeRawData(data),
    );
  }

  GetOptions? _getOptions(bool serverOnly) {
    if (!serverOnly) return null;
    return const GetOptions(source: Source.server);
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
    if (!doc.exists) return false;
    final record = _toAreaRecord(doc.data());
    if (record == null ||
        record.name != trimmedArea ||
        record.division != trimmedDivision) {
      return false;
    }
    await AreaSnapshotPersistence.persistRecord(
      record,
      source: 'firestore_area_is_headquarter',
    );
    return record.isHeadquarter;
  }

  @override
  Future<AreaRecord?> getAreaByName(
    String areaName, {
    String? division,
    bool serverOnly = false,
  }) async {
    final trimmedArea = areaName.trim();
    final trimmedDivision = division?.trim() ?? '';
    if (trimmedArea.isEmpty) return null;

    final options = _getOptions(serverOnly);

    if (trimmedDivision.isNotEmpty) {
      final docId = '$trimmedDivision-$trimmedArea';
      final ref = _firestore.collection('areas').doc(docId);
      final doc = options == null ? await ref.get() : await ref.get(options);
      if (!doc.exists) return null;

      final record = _toAreaRecord(doc.data());
      if (record == null) return null;
      if (record.name != trimmedArea || record.division != trimmedDivision) {
        return null;
      }
      await AreaSnapshotPersistence.persistRecord(
        record,
        source: serverOnly
            ? 'firestore_area_by_name_server'
            : 'firestore_area_by_name',
      );
      return record;
    }

    final query = _firestore
        .collection('areas')
        .where('name', isEqualTo: trimmedArea)
        .limit(1);
    final qs = options == null ? await query.get() : await query.get(options);

    if (qs.docs.isEmpty) return null;
    final record = _toAreaRecord(qs.docs.first.data());
    if (record == null) return null;
    await AreaSnapshotPersistence.persistRecord(
      record,
      source: serverOnly
          ? 'firestore_area_query_server'
          : 'firestore_area_query',
    );
    return record;
  }

  @override
  Future<List<AreaRecord>> getAreasByDivision(
    String division, {
    bool serverOnly = false,
  }) async {
    final trimmedDivision = division.trim();

    if (trimmedDivision.isEmpty) {
      return const <AreaRecord>[];
    }

    final query = _firestore
        .collection('areas')
        .where('division', isEqualTo: trimmedDivision);
    final options = _getOptions(serverOnly);
    final qs = options == null ? await query.get() : await query.get(options);

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
