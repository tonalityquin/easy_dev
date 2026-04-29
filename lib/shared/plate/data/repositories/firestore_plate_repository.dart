import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../application/common/view_doc_rows_store.dart';
import '../../domain/enums/plate_type.dart';
import '../../domain/models/plate_log_model.dart';
import '../../domain/models/plate_model.dart';
import '../../domain/models/plate_out_log_search_result.dart';
import '../../domain/repositories/plate_repository.dart';
import '../../domain/services/plate_creation_service.dart';
import '../../domain/services/plate_query_service.dart';
import '../../domain/services/plate_status_record.dart';
import '../../domain/services/plate_status_service.dart';
import '../../domain/services/plate_write_service.dart';
const String _kLocSep = ' - ';
const String _kLocUnknown = '미지정';

Map<String, dynamic> _locationToMap(String display) {
  final raw = display.trim();

  if (raw.isEmpty || raw == _kLocUnknown) {
    return <String, dynamic>{
      'parent': '',
      'child': '',
      'slot': '',
      'full': _kLocUnknown,
      'leaf': _kLocUnknown,
    };
  }

  final parts = raw
      .split(_kLocSep)
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .toList();

  String parent = '';
  String child = '';
  String slot = '';

  if (parts.isEmpty) {
    return <String, dynamic>{
      'parent': '',
      'child': '',
      'slot': '',
      'full': _kLocUnknown,
      'leaf': _kLocUnknown,
    };
  }

  if (parts.length == 1) {
    parent = parts[0];
  } else if (parts.length == 2) {
    parent = parts[0];
    child = parts[1];
  } else {
    parent = parts[0];
    child = parts[1];
    slot = parts.sublist(2).join(_kLocSep);
  }

  final fullSegs =
      <String>[parent, child, slot].where((e) => e.trim().isNotEmpty).toList();
  final full = fullSegs.isEmpty ? _kLocUnknown : fullSegs.join(_kLocSep);

  final leafSegs =
      <String>[child, slot].where((e) => e.trim().isNotEmpty).toList();
  final leaf = leafSegs.isNotEmpty
      ? leafSegs.join(_kLocSep)
      : (parent.trim().isEmpty ? _kLocUnknown : parent);

  return <String, dynamic>{
    'parent': parent,
    'child': child,
    'slot': slot,
    'full': full,
    'leaf': leaf,
  };
}

DateTime? _viewRowToDate(dynamic v) {
  if (v is Timestamp) return v.toDate();
  if (v is DateTime) return v;
  if (v is String) return DateTime.tryParse(v);
  return null;
}

String _normalizeViewRowLocation(String? raw) {
  final v = (raw ?? '').trim();
  return v.isEmpty ? _kLocUnknown : v;
}

String _fallbackPlateNumberFromDocId(String docId) {
  final idx = docId.lastIndexOf('_');
  if (idx > 0) return docId.substring(0, idx);
  return docId;
}

Query<Map<String, dynamic>> _platesByTypeAreaQuery(
  FirebaseFirestore firestore, {
  required PlateType type,
  required String area,
  required bool descending,
}) {
  Query<Map<String, dynamic>> q = firestore
      .collection('plates')
      .where(PlateFields.type, isEqualTo: type.firestoreValue)
      .where(PlateFields.area, isEqualTo: area);

  if (type == PlateType.departureCompleted) {
    q = q.where(PlateFields.isLockedFee, isEqualTo: false);
  }

  return q.orderBy(PlateFields.requestTime, descending: descending);
}

List<PlateModel> _plateModelsFromSnapshot(
  QuerySnapshot<Map<String, dynamic>> snap,
  PlateType type,
) {
  final results = <PlateModel>[];
  for (final doc in snap.docs) {
    try {
      results.add(PlateModel.fromDocument(doc));
    } catch (_) {}
  }
  return results;
}

List<ViewRowData> _viewRowsFromSnapshot(
  DocumentSnapshot<Map<String, dynamic>> snap, {
  required String primaryAtField,
}) {
  if (!snap.exists) return const <ViewRowData>[];

  final data = snap.data() ?? <String, dynamic>{};
  final items = data['items'];
  if (items is! Map) return const <ViewRowData>[];

  final out = <ViewRowData>[];
  for (final entry in items.entries) {
    final plateDocId = entry.key.toString();
    final value = entry.value;
    if (value is! Map) continue;

    final map = Map<String, dynamic>.from(value);
    final plateNumber = (map['plateNumber'] as String?) ??
        (map['plate_number'] as String?) ??
        _fallbackPlateNumberFromDocId(plateDocId);
    if (plateNumber.trim().isEmpty) continue;

    final location = _normalizeViewRowLocation(map['location'] as String?);
    final primaryAt = _viewRowToDate(map[primaryAtField]);
    final updatedAt = _viewRowToDate(map['updatedAt']);
    final createdAt = primaryAt ?? updatedAt;

    out.add(
      ViewRowData(
        plateId: plateDocId,
        plateNumber: plateNumber,
        location: location,
        primaryAt: primaryAt,
        updatedAt: updatedAt,
        createdAt: createdAt,
      ),
    );
  }

  return List<ViewRowData>.unmodifiable(out);
}

class FirestorePlateRepository implements PlateRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final PlateWriteService _writeService = PlateWriteService();
  final PlateQueryService _queryService = PlateQueryService();
  final PlateCreationService _creationService = PlateCreationService();
  final PlateStatusService _statusService = PlateStatusService();

  String _safeArea(String area) {
    final trimmed = area.trim();
    return trimmed.isEmpty ? 'unknown' : trimmed;
  }

  String _monthKey(DateTime dt) =>
      '${dt.year}${dt.month.toString().padLeft(2, '0')}';

  String _canonicalPlateNumber(String plateNumber) {
    final trimmed = plateNumber.trim().replaceAll(' ', '');
    final raw = trimmed.replaceAll('-', '');
    final match = RegExp(r'^(\d{2,3})([가-힣])(\d{4})$').firstMatch(raw);
    if (match == null) return trimmed;
    return '${match.group(1)}-${match.group(2)}-${match.group(3)}';
  }

  String _plateDocId(String plateNumber, String area) {
    final safeArea = _safeArea(area);
    final canonical = _canonicalPlateNumber(plateNumber);
    return '${canonical}_$safeArea';
  }

  String _resolveLogDocId({
    String? plateId,
    String? plateNumber,
    required String area,
  }) {
    final trimmedPlateId = plateId?.trim();
    if (trimmedPlateId != null && trimmedPlateId.isNotEmpty) {
      return trimmedPlateId;
    }

    final trimmedPlateNumber = plateNumber?.trim() ?? '';
    final trimmedArea = area.trim();
    if (trimmedPlateNumber.isEmpty || trimmedArea.isEmpty) {
      throw StateError('plateId 또는 (initialPlateNumber + area)이 필요합니다.');
    }

    return _plateDocId(trimmedPlateNumber, trimmedArea);
  }

  @override
  Future<void> addOrUpdatePlate(String documentId, PlateModel plate) {
    return _writeService.addOrUpdatePlate(documentId, plate);
  }

  @override
  Future<void> updatePlate(
    String documentId,
    Map<String, dynamic> updatedFields, {
    PlateLogModel? log,
  }) {
    return _writeService.updatePlate(documentId, updatedFields, log: log);
  }

  @override
  Future<void> deletePlate(
    String documentId, {
    String? area,
    bool syncViews = true,
  }) {
    return _writeService.deletePlate(
      documentId,
      area: area,
      syncViews: syncViews,
    );
  }

  @override
  Future<void> recordWhoPlateClick(
    String id,
    bool isSelected, {
    String? selectedBy,
    required String area,
  }) {
    return _writeService.recordWhoPlateClick(
      id,
      isSelected,
      selectedBy: selectedBy,
      area: area,
    );
  }

  @override
  Future<void> addPlate({
    required String plateNumber,
    required String location,
    required String area,
    required PlateType plateType,
    required String userName,
    String? billingType,
    List<String>? statusList,
    int? basicStandard,
    int? basicAmount,
    int? addStandard,
    int? addAmount,
    required String region,
    List<String>? imageUrls,
    bool isLockedFee = false,
    int? lockedAtTimeInSeconds,
    int? lockedFeeAmount,
    DateTime? endTime,
    String? paymentMethod,
    String? customStatus,
    required String selectedBillType,
  }) {
    return _creationService.addPlate(
      plateNumber: plateNumber,
      location: location,
      area: area,
      plateType: plateType,
      userName: userName,
      billingType: billingType,
      statusList: statusList,
      basicStandard: basicStandard,
      basicAmount: basicAmount,
      addStandard: addStandard,
      addAmount: addAmount,
      region: region,
      imageUrls: imageUrls,
      isLockedFee: isLockedFee,
      lockedAtTimeInSeconds: lockedAtTimeInSeconds,
      lockedFeeAmount: lockedFeeAmount,
      endTime: endTime,
      paymentMethod: paymentMethod,
      customStatus: customStatus,
      selectedBillType: selectedBillType,
    );
  }

  @override
  Future<PlateModel?> getPlate(String documentId) {
    return _queryService.getPlate(documentId);
  }

  @override
  Future<List<PlateModel>> fetchSelectedPlatesByUser({
    required String userName,
    required List<PlateType> plateTypes,
  }) async {
    final trimmedUserName = userName.trim();
    final types = plateTypes.map((e) => e.firestoreValue).toSet().toList(growable: false);

    if (trimmedUserName.isEmpty || types.isEmpty) {
      return <PlateModel>[];
    }

    try {
      final snap = await _firestore
          .collection('plates')
          .where('isSelected', isEqualTo: true)
          .where('selectedBy', isEqualTo: trimmedUserName)
          .where('type', whereIn: types)
          .get();

      final out = snap.docs.map((d) => PlateModel.fromDocument(d)).toList(growable: false);
      out.sort((a, b) {
        final at = a.updatedAt ?? a.requestTime;
        final bt = b.updatedAt ?? b.requestTime;
        return bt.compareTo(at);
      });
      return out;
    } catch (_) {}

    try {
      final snap = await _firestore
          .collection('plates')
          .where('isSelected', isEqualTo: true)
          .where('selectedBy', isEqualTo: trimmedUserName)
          .get();

      final out = snap.docs
          .map((d) => PlateModel.fromDocument(d))
          .where((p) => types.contains(p.type))
          .toList(growable: false);
      out.sort((a, b) {
        final at = a.updatedAt ?? a.requestTime;
        final bt = b.updatedAt ?? b.requestTime;
        return bt.compareTo(at);
      });
      return out;
    } catch (_) {
      return <PlateModel>[];
    }
  }

  @override
  Future<PlateFetchResult> fetchPlatesByTypeAndArea({
    required PlateType type,
    required String area,
    required bool descending,
    bool cacheFirst = true,
  }) async {
    final trimmedArea = area.trim();
    if (trimmedArea.isEmpty) {
      return const PlateFetchResult(items: <PlateModel>[], sourceLabel: '-');
    }

    final query = _platesByTypeAreaQuery(
      _firestore,
      type: type,
      area: trimmedArea,
      descending: descending,
    );

    try {
      final snapServer = await query.get(const GetOptions(source: Source.server));
      final serverResults = _plateModelsFromSnapshot(snapServer, type);
      return PlateFetchResult(items: serverResults, sourceLabel: 'server');
    } catch (_) {
      if (!cacheFirst) rethrow;
      final snapCache = await query.get(const GetOptions(source: Source.cache));
      final cacheResults = _plateModelsFromSnapshot(snapCache, type);
      return PlateFetchResult(items: cacheResults, sourceLabel: 'cache');
    }
  }

  @override
  Future<void> upsertViewItem({
    required String collection,
    required String area,
    required String plateDocId,
    required String plateNumber,
    required String location,
    required String primaryAtField,
  }) async {
    final c = collection.trim();
    final a = area.trim();
    final docId = plateDocId.trim();
    if (c.isEmpty || a.isEmpty || docId.isEmpty) return;

    await _firestore.collection(c).doc(a).set(
      <String, dynamic>{
        'area': a,
        'updatedAt': FieldValue.serverTimestamp(),
        'items': <String, dynamic>{
          docId: <String, dynamic>{
            'plateNumber': plateNumber,
            'location': location.isNotEmpty ? location : _kLocUnknown,
            primaryAtField: FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          },
        },
      },
      SetOptions(merge: true),
    );
  }

  @override
  Future<void> removeViewItem({
    required String collection,
    required String area,
    required String plateDocId,
  }) async {
    final c = collection.trim();
    final a = area.trim();
    final docId = plateDocId.trim();
    if (c.isEmpty || a.isEmpty || docId.isEmpty) return;

    await _firestore.collection(c).doc(a).set(
      <String, dynamic>{
        'area': a,
        'updatedAt': FieldValue.serverTimestamp(),
        'items': <String, dynamic>{
          docId: FieldValue.delete(),
        },
      },
      SetOptions(merge: true),
    );
  }

  @override
  Future<void> transitionPlateType({
    required String plateId,
    required String actor,
    required PlateType fromType,
    required PlateType toType,
    required String area,
    required String location,
    required String eventAtField,
    bool forceOverride = true,
  }) {
    return _writeService.transitionPlateType(
      plateId: plateId,
      actor: actor,
      fromType: fromType.firestoreValue,
      toType: toType.firestoreValue,
      extraFields: <String, dynamic>{
        'area': area,
        'location': location,
        eventAtField: FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      },
      forceOverride: forceOverride,
    );
  }

  @override
  Stream<List<ViewRowData>> watchViewRows({
    required String collection,
    required String area,
    required String primaryAtField,
  }) {
    final c = collection.trim();
    final a = area.trim();
    if (c.isEmpty || a.isEmpty) {
      return Stream<List<ViewRowData>>.value(const <ViewRowData>[]);
    }

    return _firestore.collection(c).doc(a).snapshots().map(
          (snap) => _viewRowsFromSnapshot(
            snap,
            primaryAtField: primaryAtField,
          ),
        );
  }

  @override
  Future<List<PlateLogModel>> fetchPlateLogs({
    String? plateId,
    String? plateNumber,
    required String area,
    bool descending = false,
  }) async {
    final docId = _resolveLogDocId(
      plateId: plateId,
      plateNumber: plateNumber,
      area: area,
    );

    try {
      final snap = await _firestore.collection('plates').doc(docId).get();

      if (!snap.exists) {
        throw StateError('문서를 찾을 수 없습니다.');
      }

      final data = snap.data() ?? <String, dynamic>{};
      final rawLogs = (data['logs'] as List?) ?? const [];
      final logs = <PlateLogModel>[];

      for (final entry in rawLogs) {
        if (entry is! Map) {
          continue;
        }

        try {
          logs.add(PlateLogModel.fromMap(Map<String, dynamic>.from(entry)));
        } catch (_) {}
      }

      logs.sort(
        (a, b) => descending
            ? b.timestamp.compareTo(a.timestamp)
            : a.timestamp.compareTo(b.timestamp),
      );

      return logs;
    } on FirebaseException catch (e) {
      throw PlateLogReadException(
        '로그를 불러오는 중 오류가 발생했습니다. (${e.code}: ${e.message})',
        cause: e,
      );
    } on StateError {
      rethrow;
    } catch (e) {
      throw PlateLogReadException(
        '로그를 불러오는 중 오류가 발생했습니다. ($e)',
        cause: e,
      );
    }
  }

  @override
  Future<void> appendPlateLog({
    required String plateId,
    required Map<String, dynamic> log,
  }) async {
    final docId = plateId.trim();
    if (docId.isEmpty) {
      throw ArgumentError('plateId is empty');
    }

    await _firestore.collection('plates').doc(docId).update({
      'logs': FieldValue.arrayUnion([log]),
    });
  }

  @override
  Future<void> settlePlateBilling({
    required String documentId,
    required int lockedAtTimeInSeconds,
    required int lockedFeeAmount,
    required String paymentMethod,
    required PlateLogModel log,
  }) {
    return updatePlate(
      documentId,
      <String, dynamic>{
        'isLockedFee': true,
        'lockedAtTimeInSeconds': lockedAtTimeInSeconds,
        'lockedFeeAmount': lockedFeeAmount,
        'paymentMethod': paymentMethod,
      },
      log: log,
    );
  }

  @override
  Future<void> cancelPlateBilling({
    required String documentId,
    required PlateLogModel log,
  }) {
    return updatePlate(
      documentId,
      <String, dynamic>{
        'isLockedFee': false,
        'lockedAtTimeInSeconds': FieldValue.delete(),
        'lockedFeeAmount': FieldValue.delete(),
        'paymentMethod': FieldValue.delete(),
      },
      log: log,
    );
  }

  @override
  Future<PlateStatusRecord?> fetchLatestPlateStatus({
    required String plateNumber,
    required String area,
  }) async {
    final safeArea = _safeArea(area);
    final docId = _plateDocId(plateNumber, safeArea);
    final now = DateTime.now();
    final monthsToTry = <DateTime>[
      DateTime(now.year, now.month, 1),
      DateTime(now.year, now.month - 1, 1),
    ];

    try {
      for (final month in monthsToTry) {
        final monthKey = _monthKey(month);
        final doc = await _firestore
            .collection('plate_status')
            .doc(safeArea)
            .collection('months')
            .doc(monthKey)
            .collection('plates')
            .doc(docId)
            .get();
        if (doc.exists) {
          return PlateStatusRecord.fromMap(doc.data()!);
        }
      }

      try {
        final primary = await _firestore
            .collectionGroup('plates')
            .where('plateDocId', isEqualTo: docId)
            .orderBy('monthKey', descending: true)
            .limit(1)
            .get();
        if (primary.docs.isNotEmpty) {
          return PlateStatusRecord.fromMap(primary.docs.first.data());
        }
      } on FirebaseException {}

      final secondary = await _firestore
          .collectionGroup('plates')
          .where('plateDocId', isEqualTo: docId)
          .limit(12)
          .get();
      if (secondary.docs.isEmpty) {
        return null;
      }

      QueryDocumentSnapshot<Map<String, dynamic>>? best;
      var bestMonth = -1;

      for (final doc in secondary.docs) {
        final data = doc.data();
        var monthInt = -1;
        final monthKey = (data['monthKey'] as String?)?.trim();
        if (monthKey != null && monthKey.isNotEmpty) {
          monthInt = int.tryParse(monthKey) ?? -1;
        } else {
          final parts = doc.reference.path.split('/');
          final index = parts.indexOf('months');
          if (index >= 0 && index + 1 < parts.length) {
            monthInt = int.tryParse(parts[index + 1]) ?? -1;
          }
        }
        if (monthInt > bestMonth) {
          bestMonth = monthInt;
          best = doc;
        }
      }

      final selected = best?.data() ?? secondary.docs.first.data();
      return PlateStatusRecord.fromMap(selected);
    } on FirebaseException catch (e) {
      throw PlateStatusReadException(
        'plate_status 조회에 실패했습니다.',
        cause: e,
      );
    } on TimeoutException catch (e) {
      throw PlateStatusReadException(
        'plate_status 조회 중 시간이 초과되었습니다.',
        cause: e,
      );
    } catch (e) {
      throw PlateStatusReadException(
        'plate_status 조회 중 알 수 없는 오류가 발생했습니다.',
        cause: e,
      );
    }
  }

  @override
  Future<PlateStatusRecord?> fetchMonthlyPlateStatus({
    required String plateNumber,
    required String area,
  }) async {
    final safeArea = _safeArea(area);
    final docId = _plateDocId(plateNumber, safeArea);

    try {
      final doc =
          await _firestore.collection('monthly_plate_status').doc(docId).get();
      if (!doc.exists) {
        return null;
      }
      final data = doc.data();
      if (data == null) {
        return null;
      }
      return PlateStatusRecord.fromMap(data, docId: docId);
    } on FirebaseException catch (e) {
      throw MonthlyPlateStatusReadException(
        'monthly_plate_status 조회에 실패했습니다.',
        cause: e,
      );
    } on TimeoutException catch (e) {
      throw MonthlyPlateStatusReadException(
        'monthly_plate_status 조회 중 시간이 초과되었습니다.',
        cause: e,
      );
    } catch (e) {
      throw MonthlyPlateStatusReadException(
        'monthly_plate_status 조회 중 알 수 없는 오류가 발생했습니다.',
        cause: e,
      );
    }
  }

  @override
  Future<void> upsertMonthlyMemoAndStatus({
    required String plateNumber,
    required String area,
    required String createdBy,
    required String customStatus,
    required List<String> statusList,
    String? countType,
  }) {
    return _statusService.upsertMonthlyMemoAndStatus(
      plateNumber: plateNumber,
      area: area,
      createdBy: createdBy,
      customStatus: customStatus,
      statusList: statusList,
      countType: countType,
    );
  }

  @override
  Future<void> clearMonthlyMemoAndStatus({
    required String plateNumber,
    required String area,
  }) {
    return _statusService.clearMonthlyMemoAndStatus(
      plateNumber: plateNumber,
      area: area,
    );
  }

  @override
  Future<List<String>> fetchViewLocations({
    required String collectionName,
    required String area,
  }) async {
    final safeArea = area.trim();
    if (safeArea.isEmpty) {
      return const <String>[];
    }

    final doc = await _firestore.collection(collectionName).doc(safeArea).get();
    if (!doc.exists) {
      return const <String>[];
    }

    final data = doc.data() ?? <String, dynamic>{};
    final items = data['items'];
    final out = <String>[];

    if (items is Map) {
      for (final entry in items.entries) {
        final value = entry.value;
        if (value is! Map) continue;
        final map = Map<String, dynamic>.from(value);
        final location = (map['location'] ?? '').toString().trim();
        if (location.isNotEmpty) {
          out.add(location);
        }
      }
    }

    return out;
  }

  @override
  Future<bool> hasMonthlyParkingByArea({
    required String area,
  }) async {
    final safeArea = area.trim();
    if (safeArea.isEmpty) {
      return false;
    }

    final qs = await _firestore
        .collection('monthly_plate_status')
        .where('area', isEqualTo: safeArea)
        .limit(1)
        .get();

    return qs.docs.isNotEmpty;
  }

  @override
  Stream<List<PlateStatusRecord>> watchMonthlyPlateStatuses({
    required String area,
  }) {
    final safeArea = area.trim();
    if (safeArea.isEmpty) {
      return Stream.value(const <PlateStatusRecord>[]);
    }

    return _firestore
        .collection('monthly_plate_status')
        .where('type', isEqualTo: '정기')
        .where('area', isEqualTo: safeArea)
        .orderBy('updatedAt', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => PlateStatusRecord.fromMap(doc.data(), docId: doc.id))
            .toList(growable: false));
  }

  @override
  Future<void> deleteMonthlyPlateStatus({
    required String documentId,
  }) async {
    final trimmed = documentId.trim();
    if (trimmed.isEmpty) {
      return;
    }
    await _firestore.collection('monthly_plate_status').doc(trimmed).delete();
  }

  @override
  Future<void> recordMonthlyPayment({
    required String plateNumber,
    required String area,
    required String paidBy,
    required int amount,
    required String note,
    required bool extended,
  }) async {
    final docId = _plateDocId(plateNumber, area);
    final historyEntry = <String, dynamic>{
      'paidAt': DateTime.now().toIso8601String(),
      'paidBy': paidBy,
      'amount': amount,
      'note': note,
      'extended': extended,
    };

    await _firestore.collection('monthly_plate_status').doc(docId).set(
      <String, dynamic>{
        'payment_history': FieldValue.arrayUnion([historyEntry]),
      },
      SetOptions(merge: true),
    );
  }

  @override
  Future<void> extendMonthlyDateRange({
    required String plateNumber,
    required String area,
    required String startDate,
    required String endDate,
    required String extendedBy,
  }) async {
    final docId = _plateDocId(plateNumber, area);
    await _firestore.collection('monthly_plate_status').doc(docId).set(
      <String, dynamic>{
        'startDate': startDate,
        'endDate': endDate,
        'updatedAt': FieldValue.serverTimestamp(),
        'extendedAt': FieldValue.serverTimestamp(),
        'extendedBy': extendedBy,
      },
      SetOptions(merge: true),
    );
  }

  @override
  Future<void> clearMonthlyMemoAndStatusWithAudit({
    required String plateNumber,
    required String area,
    required String clearedBy,
  }) async {
    final docId = _plateDocId(plateNumber, area);
    await _firestore.collection('monthly_plate_status').doc(docId).set(
      <String, dynamic>{
        'customStatus': '',
        'statusList': <String>[],
        'updatedAt': FieldValue.serverTimestamp(),
        'clearedAt': FieldValue.serverTimestamp(),
        'clearedBy': clearedBy,
      },
      SetOptions(merge: true),
    );
  }

  @override
  Future<Map<String, dynamic>?> fetchViewDocumentData({
    required String collection,
    required String area,
  }) async {
    final safeCollection = collection.trim();
    final safeArea = area.trim();

    if (safeCollection.isEmpty || safeArea.isEmpty) {
      return null;
    }

    final doc = await _firestore.collection(safeCollection).doc(safeArea).get();
    return doc.data();
  }

  @override
  Future<int> countPlatesByAreaAndType({
    required String area,
    required PlateType plateType,
  }) async {
    final trimmedArea = area.trim();

    if (trimmedArea.isEmpty) {
      return 0;
    }

    final aggregate = await _firestore
        .collection('plates')
        .where('area', isEqualTo: trimmedArea)
        .where('type', isEqualTo: plateType.firestoreValue)
        .count()
        .get();

    return aggregate.count ?? 0;
  }

  @override
  Future<List<PlateModel>> fourDigitCommonQuery({
    required String plateFourDigit,
    required String area,
  }) {
    return _queryService.fourDigitCommonQuery(
      plateFourDigit: plateFourDigit,
      area: area,
    );
  }

  @override
  Future<List<PlateOutLogSearchResult>> searchPlateOutLogsByFourDigit({
    required String plateFourDigit,
    required String area,
  }) async {
    final safeArea = _safeArea(area);
    final fourDigit = plateFourDigit.trim();

    if (!RegExp(r'^\d{4}$').hasMatch(fourDigit)) {
      return const <PlateOutLogSearchResult>[];
    }

    final snapshot = await _firestore
        .collectionGroup('plates')
        .where('logScope', isEqualTo: 'plate_out_log')
        .where('area', isEqualTo: safeArea)
        .where('plate_four_digit', isEqualTo: fourDigit)
        .get();

    final items = snapshot.docs
        .map((doc) => PlateOutLogSearchResult(
              docId: doc.id,
              path: doc.reference.path,
              data: Map<String, dynamic>.from(doc.data()),
            ))
        .toList(growable: false);

    final sorted = List<PlateOutLogSearchResult>.from(items)
      ..sort((a, b) {
        final month = (b.stringValue('monthKey') ?? '')
            .compareTo(a.stringValue('monthKey') ?? '');
        if (month != 0) return month;
        return b.docId.compareTo(a.docId);
      });

    return sorted;
  }

  @override
  Future<List<PlateModel>> fourDigitSignatureQuery({
    required String plateFourDigit,
    required String area,
  }) {
    return _queryService.fourDigitSignatureQuery(
      plateFourDigit: plateFourDigit,
      area: area,
    );
  }

  @override
  Future<List<PlateModel>> fourDigitForTabletQuery({
    required String plateFourDigit,
    required String area,
  }) {
    return _queryService.fourDigitForTabletQuery(
      plateFourDigit: plateFourDigit,
      area: area,
    );
  }

  @override
  Future<List<PlateModel>> fourDigitDepartureCompletedQuery({
    required String plateFourDigit,
    required String area,
  }) {
    return _queryService.fourDigitDepartureCompletedQuery(
      plateFourDigit: plateFourDigit,
      area: area,
    );
  }

  @override
  Future<void> setPlateStatus({
    required String plateNumber,
    required String area,
    required String customStatus,
    required List<String> statusList,
    required String createdBy,
  }) {
    return _statusService.setPlateStatus(
      plateNumber: plateNumber,
      area: area,
      customStatus: customStatus,
      statusList: statusList,
      createdBy: createdBy,
    );
  }

  @override
  Future<void> setMonthlyPlateStatus({
    required String plateNumber,
    required String area,
    required String createdBy,
    required String customStatus,
    required List<String> statusList,
    required String countType,
    required int regularAmount,
    required int regularDurationHours,
    required String regularType,
    required String startDate,
    required String endDate,
    required String periodUnit,
    String? specialNote,
    bool? isExtended,
  }) {
    return _statusService.setMonthlyPlateStatus(
      plateNumber: plateNumber,
      area: area,
      createdBy: createdBy,
      customStatus: customStatus,
      statusList: statusList,
      countType: countType,
      regularAmount: regularAmount,
      regularDurationHours: regularDurationHours,
      regularType: regularType,
      startDate: startDate,
      endDate: endDate,
      periodUnit: periodUnit,
      specialNote: specialNote,
      isExtended: isExtended,
    );
  }

  @override
  Future<void> setMonthlyMemoAndStatusOnly({
    required String plateNumber,
    required String area,
    required String createdBy,
    required String customStatus,
    required List<String> statusList,
    bool skipIfDocMissing = true,
  }) async {
    try {
      await _statusService.setMonthlyMemoAndStatusOnly(
        plateNumber: plateNumber,
        area: area,
        createdBy: createdBy,
        customStatus: customStatus,
        statusList: statusList,
        skipIfDocMissing: skipIfDocMissing,
      );
    } on FirebaseException catch (e) {
      throw MonthlyPlateStatusWriteException(
        'monthly_plate_status 반영에 실패했습니다.',
        cause: e,
      );
    } on TimeoutException catch (e) {
      throw MonthlyPlateStatusWriteException(
        'monthly_plate_status 반영 중 시간이 초과되었습니다.',
        cause: e,
      );
    } catch (e) {
      throw MonthlyPlateStatusWriteException(
        'monthly_plate_status 반영 중 알 수 없는 오류가 발생했습니다.',
        cause: e,
      );
    }
  }

  @override
  Future<void> deletePlateStatus(String plateNumber, String area) {
    return _statusService.deletePlateStatus(plateNumber, area);
  }

  @override
  Future<void> transitionPlateState({
    required String documentId,
    required PlateType toType,
    required String location,
    required String userName,
    bool resetSelection = true,
    bool includeEndTime = false,
    bool? isLockedFee,
    int? lockedAtTimeInSeconds,
    int? lockedFeeAmount,
    PlateLogModel? log,
  }) async {
    final updateData = <String, dynamic>{
      'type': toType.firestoreValue,
      'location': _locationToMap(location),
      'userName': userName,
      if (resetSelection) ...{
        'isSelected': false,
        'selectedBy': null,
      },
      if (includeEndTime) 'endTime': DateTime.now(),
      if (isLockedFee == true) 'isLockedFee': true,
      if (lockedAtTimeInSeconds != null)
        'lockedAtTimeInSeconds': lockedAtTimeInSeconds,
      if (lockedFeeAmount != null) 'lockedFeeAmount': lockedFeeAmount,
      if (log != null) 'logs': FieldValue.arrayUnion([log.toMap()]),
    };

    await updatePlate(documentId, updateData);
  }
}
