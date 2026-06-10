import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../../app/utils/dev_firebase_debug_dialog.dart';
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
const String _monthlyPlateStatusCollection = 'monthly_plate_status';
const String _monthlyPlateStatusViewCollection = 'monthly_plate_status_view';

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
    final isSelected = map['isSelected'] == true;
    final selectedBy = (map['selectedBy'] as String?)?.trim();

    out.add(
      ViewRowData(
        plateId: plateDocId,
        plateNumber: plateNumber,
        location: location,
        primaryAt: primaryAt,
        updatedAt: updatedAt,
        createdAt: createdAt,
        isSelected: isSelected,
        selectedBy: selectedBy == null || selectedBy.isEmpty ? null : selectedBy,
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

  int _intValue(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString().trim() ?? '') ?? 0;
  }

  String _textValue(dynamic value) {
    return value?.toString().trim() ?? '';
  }

  List<String> _stringListValue(dynamic value) {
    if (value is! List) return const <String>[];
    return value.map((e) => e.toString()).toList(growable: false);
  }

  int _paymentCountFromData(Map<String, dynamic> data) {
    final explicit = data['paymentCount'];
    if (explicit != null) return _intValue(explicit);
    final history = data['payment_history'];
    if (history is List) return history.length;
    return 0;
  }

  bool _hasMonthlyMemo(Map<String, dynamic> data) {
    final customStatus = _textValue(data['customStatus']);
    if (customStatus.isNotEmpty && customStatus != '없음') return true;
    final statusList = data['statusList'];
    return statusList is List && statusList.isNotEmpty;
  }

  bool _isEmptyMonthlyPayload({
    required String customStatus,
    required List<String> statusList,
    required String countType,
    required int regularAmount,
    required int regularDurationValue,
    required String regularType,
    required String startDate,
    required String endDate,
    required String periodUnit,
    String? specialNote,
    bool? isExtended,
  }) {
    return customStatus.trim().isEmpty &&
        statusList.isEmpty &&
        countType.trim().isEmpty &&
        regularAmount == 0 &&
        regularDurationValue == 0 &&
        regularType.trim().isEmpty &&
        startDate.trim().isEmpty &&
        endDate.trim().isEmpty &&
        periodUnit.trim().isEmpty &&
        (specialNote ?? '').trim().isEmpty &&
        isExtended == null;
  }

  Map<String, dynamic> _monthlyViewItemFromData({
    required String docId,
    required Map<String, dynamic> data,
    Object? updatedAt,
  }) {
    final plateNumber = _textValue(data['plateNumber']).isNotEmpty
        ? _textValue(data['plateNumber'])
        : _fallbackPlateNumberFromDocId(docId);
    final duration = _intValue(data['regularDurationValue'] ?? data['regularDurationHours']);
    final statusList = _stringListValue(data['statusList']);
    final merged = <String, dynamic>{
      'docId': docId,
      'plateNumber': plateNumber,
      'area': _textValue(data['area']),
      'region': _textValue(data['region']).isEmpty ? '전국' : _textValue(data['region']),
      'type': '정기',
      'countType': _textValue(data['countType']),
      'regularType': _textValue(data['regularType']),
      'regularAmount': _intValue(data['regularAmount']),
      'regularDurationValue': duration,
      'regularDurationHours': duration,
      'periodUnit': _textValue(data['periodUnit']),
      'startDate': _textValue(data['startDate']),
      'endDate': _textValue(data['endDate']),
      'customStatus': _textValue(data['customStatus']),
      'statusList': statusList,
      'hasMemo': _hasMonthlyMemo(data),
      'paymentCount': _paymentCountFromData(data),
      'updatedAt': updatedAt ?? data['updatedAt'] ?? FieldValue.serverTimestamp(),
    };
    return merged;
  }

  Map<String, dynamic> _monthlyViewItemFromWritePayload({
    required String docId,
    required String plateNumber,
    required String area,
    required String region,
    required String customStatus,
    required List<String> statusList,
    required String countType,
    required int regularAmount,
    required int regularDurationValue,
    required String regularType,
    required String startDate,
    required String endDate,
    required String periodUnit,
    required int paymentCount,
  }) {
    return <String, dynamic>{
      'docId': docId,
      'plateNumber': plateNumber,
      'area': area,
      'region': region.trim().isEmpty ? '전국' : region.trim(),
      'type': '정기',
      'countType': countType,
      'regularType': regularType,
      'regularAmount': regularAmount,
      'regularDurationValue': regularDurationValue,
      'regularDurationHours': regularDurationValue,
      'periodUnit': periodUnit,
      'startDate': startDate,
      'endDate': endDate,
      'customStatus': customStatus.trim(),
      'statusList': statusList,
      'hasMemo': customStatus.trim().isNotEmpty || statusList.isNotEmpty,
      'paymentCount': paymentCount,
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  Future<void> _mergeMonthlyViewItem({
    required String area,
    required String docId,
    required Map<String, dynamic> item,
  }) {
    final safeArea = area.trim();
    if (safeArea.isEmpty || docId.trim().isEmpty) return Future<void>.value();
    return _firestore.collection(_monthlyPlateStatusViewCollection).doc(safeArea).set(
      <String, dynamic>{
        'area': safeArea,
        'updatedAt': FieldValue.serverTimestamp(),
        'items': <String, dynamic>{
          docId: item,
        },
      },
      SetOptions(merge: true),
    );
  }

  Future<void> _removeMonthlyViewItem({
    required String area,
    required String docId,
  }) {
    final safeArea = area.trim();
    if (safeArea.isEmpty || docId.trim().isEmpty) return Future<void>.value();
    return _firestore.collection(_monthlyPlateStatusViewCollection).doc(safeArea).set(
      <String, dynamic>{
        'area': safeArea,
        'updatedAt': FieldValue.serverTimestamp(),
        'items': <String, dynamic>{
          docId: FieldValue.delete(),
        },
      },
      SetOptions(merge: true),
    );
  }

  Future<void> _rebuildMonthlyViewFromQuery({
    required String area,
    required List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  }) async {
    final safeArea = area.trim();
    if (safeArea.isEmpty) return;
    final items = <String, dynamic>{};
    for (final doc in docs) {
      final data = doc.data();
      items[doc.id] = _monthlyViewItemFromData(
        docId: doc.id,
        data: data,
        updatedAt: data['updatedAt'],
      );
    }
    await _firestore.collection(_monthlyPlateStatusViewCollection).doc(safeArea).set(
      <String, dynamic>{
        'area': safeArea,
        'updatedAt': FieldValue.serverTimestamp(),
        'items': items,
      },
      SetOptions(merge: true),
    );
  }

  Future<void> _syncMonthlyViewItemFromSource({
    required String plateNumber,
    required String area,
  }) async {
    final safeArea = area.trim();
    if (safeArea.isEmpty) return;
    final canonicalPlate = _canonicalPlateNumber(plateNumber);
    final docId = _plateDocId(canonicalPlate, safeArea);
    final doc = await _firestore.collection(_monthlyPlateStatusCollection).doc(docId).get();
    if (!doc.exists) {
      await _removeMonthlyViewItem(area: safeArea, docId: docId);
      return;
    }
    final data = doc.data();
    if (data == null) return;
    await _mergeMonthlyViewItem(
      area: safeArea,
      docId: docId,
      item: _monthlyViewItemFromData(
        docId: docId,
        data: data,
        updatedAt: data['updatedAt'],
      ),
    );
  }

  Future<void> _showMonthlyFirebaseDebug({
    required String operation,
    Object? error,
    StackTrace? stackTrace,
    Map<String, Object?> details = const <String, Object?>{},
  }) {
    return DevFirebaseDebugDialog.show(
      operation: operation,
      error: error,
      stackTrace: stackTrace,
      details: details,
    );
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
    required String division,
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
    String? manufacturerName,
    String? modelName,
    String? priority1SlotKey,
    String? priority2SlotKey,
    String? priority3SlotKey,
  }) {
    return _creationService.addPlate(
      plateNumber: plateNumber,
      location: location,
      area: area,
      division: division,
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
      manufacturerName: manufacturerName,
      modelName: modelName,
      priority1SlotKey: priority1SlotKey,
      priority2SlotKey: priority2SlotKey,
      priority3SlotKey: priority3SlotKey,
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
            'isSelected': false,
            'selectedBy': null,
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
    } on FirebaseException catch (e, st) {
      await _showMonthlyFirebaseDebug(
        operation: 'monthly.fetchMonthlyPlateStatus',
        error: e,
        stackTrace: st,
        details: <String, Object?>{
          'collection': 'monthly_plate_status',
          'docId': docId,
          'plateNumber': plateNumber,
          'area': safeArea,
          'query': 'monthly_plate_status/$docId',
        },
      );
      throw MonthlyPlateStatusReadException(
        'monthly_plate_status 조회에 실패했습니다.',
        cause: e,
      );
    } on TimeoutException catch (e, st) {
      await _showMonthlyFirebaseDebug(
        operation: 'monthly.fetchMonthlyPlateStatus.timeout',
        error: e,
        stackTrace: st,
        details: <String, Object?>{
          'collection': 'monthly_plate_status',
          'docId': docId,
          'plateNumber': plateNumber,
          'area': safeArea,
          'query': 'monthly_plate_status/$docId',
        },
      );
      throw MonthlyPlateStatusReadException(
        'monthly_plate_status 조회 중 시간이 초과되었습니다.',
        cause: e,
      );
    } catch (e, st) {
      await _showMonthlyFirebaseDebug(
        operation: 'monthly.fetchMonthlyPlateStatus.unknown',
        error: e,
        stackTrace: st,
        details: <String, Object?>{
          'collection': 'monthly_plate_status',
          'docId': docId,
          'plateNumber': plateNumber,
          'area': safeArea,
          'query': 'monthly_plate_status/$docId',
        },
      );
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
  }) async {
    try {
      await _statusService.upsertMonthlyMemoAndStatus(
        plateNumber: plateNumber,
        area: area,
        createdBy: createdBy,
        customStatus: customStatus,
        statusList: statusList,
        countType: countType,
      );
      await _syncMonthlyViewItemFromSource(plateNumber: plateNumber, area: area);
    } on FirebaseException catch (e, st) {
      await _showMonthlyFirebaseDebug(
        operation: 'monthly.upsertMonthlyMemoAndStatus',
        error: e,
        stackTrace: st,
        details: <String, Object?>{
          'collection': 'monthly_plate_status',
          'docId': _plateDocId(plateNumber, area),
          'plateNumber': plateNumber,
          'area': area,
          'createdBy': createdBy,
          'customStatus': customStatus,
          'statusList': statusList,
          'countType': countType,
          'writePath': 'PlateStatusService.upsertMonthlyMemoAndStatus',
        },
      );
      throw MonthlyPlateStatusWriteException(
        'monthly_plate_status 반영에 실패했습니다.',
        cause: e,
      );
    } on TimeoutException catch (e, st) {
      await _showMonthlyFirebaseDebug(
        operation: 'monthly.upsertMonthlyMemoAndStatus.timeout',
        error: e,
        stackTrace: st,
        details: <String, Object?>{
          'collection': 'monthly_plate_status',
          'docId': _plateDocId(plateNumber, area),
          'plateNumber': plateNumber,
          'area': area,
          'createdBy': createdBy,
          'customStatus': customStatus,
          'statusList': statusList,
          'countType': countType,
          'writePath': 'PlateStatusService.upsertMonthlyMemoAndStatus',
        },
      );
      throw MonthlyPlateStatusWriteException(
        'monthly_plate_status 반영 중 시간이 초과되었습니다.',
        cause: e,
      );
    } catch (e, st) {
      await _showMonthlyFirebaseDebug(
        operation: 'monthly.upsertMonthlyMemoAndStatus.unknown',
        error: e,
        stackTrace: st,
        details: <String, Object?>{
          'collection': 'monthly_plate_status',
          'docId': _plateDocId(plateNumber, area),
          'plateNumber': plateNumber,
          'area': area,
          'createdBy': createdBy,
          'customStatus': customStatus,
          'statusList': statusList,
          'countType': countType,
          'writePath': 'PlateStatusService.upsertMonthlyMemoAndStatus',
        },
      );
      throw MonthlyPlateStatusWriteException(
        'monthly_plate_status 반영 중 알 수 없는 오류가 발생했습니다.',
        cause: e,
      );
    }
  }

  @override
  Future<void> clearMonthlyMemoAndStatus({
    required String plateNumber,
    required String area,
  }) async {
    try {
      await _statusService.clearMonthlyMemoAndStatus(
        plateNumber: plateNumber,
        area: area,
      );
      await _syncMonthlyViewItemFromSource(plateNumber: plateNumber, area: area);
    } on FirebaseException catch (e, st) {
      await _showMonthlyFirebaseDebug(
        operation: 'monthly.clearMonthlyMemoAndStatus',
        error: e,
        stackTrace: st,
        details: <String, Object?>{
          'collection': 'monthly_plate_status',
          'docId': _plateDocId(plateNumber, area),
          'plateNumber': plateNumber,
          'area': area,
          'writePath': 'PlateStatusService.clearMonthlyMemoAndStatus',
        },
      );
      throw MonthlyPlateStatusWriteException(
        'monthly_plate_status 반영에 실패했습니다.',
        cause: e,
      );
    } on TimeoutException catch (e, st) {
      await _showMonthlyFirebaseDebug(
        operation: 'monthly.clearMonthlyMemoAndStatus.timeout',
        error: e,
        stackTrace: st,
        details: <String, Object?>{
          'collection': 'monthly_plate_status',
          'docId': _plateDocId(plateNumber, area),
          'plateNumber': plateNumber,
          'area': area,
          'writePath': 'PlateStatusService.clearMonthlyMemoAndStatus',
        },
      );
      throw MonthlyPlateStatusWriteException(
        'monthly_plate_status 반영 중 시간이 초과되었습니다.',
        cause: e,
      );
    } catch (e, st) {
      await _showMonthlyFirebaseDebug(
        operation: 'monthly.clearMonthlyMemoAndStatus.unknown',
        error: e,
        stackTrace: st,
        details: <String, Object?>{
          'collection': 'monthly_plate_status',
          'docId': _plateDocId(plateNumber, area),
          'plateNumber': plateNumber,
          'area': area,
          'writePath': 'PlateStatusService.clearMonthlyMemoAndStatus',
        },
      );
      throw MonthlyPlateStatusWriteException(
        'monthly_plate_status 반영 중 알 수 없는 오류가 발생했습니다.',
        cause: e,
      );
    }
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

    try {
      final qs = await _firestore
          .collection('monthly_plate_status')
          .where('area', isEqualTo: safeArea)
          .limit(1)
          .get();

      return qs.docs.isNotEmpty;
    } catch (e, st) {
      await _showMonthlyFirebaseDebug(
        operation: 'monthly.hasMonthlyParkingByArea',
        error: e,
        stackTrace: st,
        details: <String, Object?>{
          'collection': 'monthly_plate_status',
          'area': safeArea,
          'query': 'where(area == $safeArea).limit(1)',
          'filters': 'area == $safeArea',
          'limit': 1,
        },
      );
      rethrow;
    }
  }

  @override
  Stream<List<PlateStatusRecord>> watchMonthlyPlateStatuses({
    required String area,
  }) {
    final safeArea = area.trim();
    if (safeArea.isEmpty) {
      return Stream.value(const <PlateStatusRecord>[]);
    }

    final stream = _firestore
        .collection('monthly_plate_status')
        .where('type', isEqualTo: '정기')
        .where('area', isEqualTo: safeArea)
        .orderBy('updatedAt', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs
            .map((doc) => PlateStatusRecord.fromMap(doc.data(), docId: doc.id))
            .toList(growable: false));

    return stream.transform(
      StreamTransformer<List<PlateStatusRecord>, List<PlateStatusRecord>>.fromHandlers(
        handleError: (Object error, StackTrace stackTrace, EventSink<List<PlateStatusRecord>> sink) {
          unawaited(
            _showMonthlyFirebaseDebug(
              operation: 'monthly.watchMonthlyPlateStatuses',
              error: error,
              stackTrace: stackTrace,
              details: <String, Object?>{
                'collection': 'monthly_plate_status',
                'area': safeArea,
                'query': 'where(type == 정기).where(area == $safeArea).orderBy(updatedAt desc)',
                'filters': <String, Object?>{
                  'type': '정기',
                  'area': safeArea,
                },
                'orderBy': 'updatedAt desc',
                'indexDebug': 'if FirebaseException.code == failed-precondition, firebase.message usually contains the composite index creation link',
                'compositeIndexCandidate': 'monthly_plate_status: type ASC, area ASC, updatedAt DESC',
              },
            ),
          );
          sink.addError(error, stackTrace);
        },
      ),
    );
  }

  @override
  Future<List<Map<String, dynamic>>> fetchMonthlyPlateStatusView({
    required String area,
  }) async {
    final safeArea = area.trim();
    if (safeArea.isEmpty) {
      return const <Map<String, dynamic>>[];
    }

    try {
      final doc = await _firestore
          .collection(_monthlyPlateStatusViewCollection)
          .doc(safeArea)
          .get()
          .timeout(const Duration(seconds: 10));
      final data = doc.data() ?? const <String, dynamic>{};
      final items = data['items'];
      if (items is Map && items.isNotEmpty) {
        final out = <Map<String, dynamic>>[];
        for (final entry in items.entries) {
          final value = entry.value;
          if (value is! Map) continue;
          final item = Map<String, dynamic>.from(value);
          item['docId'] = item['docId']?.toString().trim().isNotEmpty == true
              ? item['docId'].toString().trim()
              : entry.key.toString();
          item['plateNumber'] = item['plateNumber']?.toString().trim().isNotEmpty == true
              ? item['plateNumber'].toString().trim()
              : _fallbackPlateNumberFromDocId(item['docId'].toString());
          item['area'] = item['area']?.toString().trim().isNotEmpty == true
              ? item['area'].toString().trim()
              : safeArea;
          out.add(item);
        }
        out.sort((a, b) {
          final av = _viewRowToDate(a['updatedAt'])?.millisecondsSinceEpoch ?? 0;
          final bv = _viewRowToDate(b['updatedAt'])?.millisecondsSinceEpoch ?? 0;
          return bv.compareTo(av);
        });
        return List<Map<String, dynamic>>.unmodifiable(out);
      }

      final source = await _firestore
          .collection(_monthlyPlateStatusCollection)
          .where('type', isEqualTo: '정기')
          .where('area', isEqualTo: safeArea)
          .orderBy('updatedAt', descending: true)
          .get()
          .timeout(const Duration(seconds: 10));
      if (source.docs.isEmpty) {
        return const <Map<String, dynamic>>[];
      }
      await _rebuildMonthlyViewFromQuery(area: safeArea, docs: source.docs);
      return List<Map<String, dynamic>>.unmodifiable(
        source.docs.map((doc) {
          final data = Map<String, dynamic>.from(doc.data());
          final item = _monthlyViewItemFromData(
            docId: doc.id,
            data: data,
            updatedAt: data['updatedAt'],
          );
          item['area'] = safeArea;
          return item;
        }).toList(growable: false),
      );
    } on FirebaseException catch (e, st) {
      await _showMonthlyFirebaseDebug(
        operation: 'monthly.fetchMonthlyPlateStatusView',
        error: e,
        stackTrace: st,
        details: <String, Object?>{
          'collection': _monthlyPlateStatusViewCollection,
          'sourceCollection': _monthlyPlateStatusCollection,
          'area': safeArea,
          'viewPath': '$_monthlyPlateStatusViewCollection/$safeArea',
        },
      );
      throw MonthlyPlateStatusReadException(
        'monthly_plate_status_view 조회에 실패했습니다.',
        cause: e,
      );
    } on TimeoutException catch (e, st) {
      await _showMonthlyFirebaseDebug(
        operation: 'monthly.fetchMonthlyPlateStatusView.timeout',
        error: e,
        stackTrace: st,
        details: <String, Object?>{
          'collection': _monthlyPlateStatusViewCollection,
          'sourceCollection': _monthlyPlateStatusCollection,
          'area': safeArea,
          'viewPath': '$_monthlyPlateStatusViewCollection/$safeArea',
        },
      );
      throw MonthlyPlateStatusReadException(
        'monthly_plate_status_view 조회 중 시간이 초과되었습니다.',
        cause: e,
      );
    } catch (e, st) {
      await _showMonthlyFirebaseDebug(
        operation: 'monthly.fetchMonthlyPlateStatusView.unknown',
        error: e,
        stackTrace: st,
        details: <String, Object?>{
          'collection': _monthlyPlateStatusViewCollection,
          'sourceCollection': _monthlyPlateStatusCollection,
          'area': safeArea,
          'viewPath': '$_monthlyPlateStatusViewCollection/$safeArea',
        },
      );
      throw MonthlyPlateStatusReadException(
        'monthly_plate_status_view 조회 중 알 수 없는 오류가 발생했습니다.',
        cause: e,
      );
    }
  }

  @override
  Future<MonthlyPlateViewRebuildResult> rebuildAllMonthlyPlateStatusViews() async {
    try {
      final source = await _firestore
          .collection(_monthlyPlateStatusCollection)
          .where('type', isEqualTo: '정기')
          .get()
          .timeout(const Duration(seconds: 30));

      final grouped = <String, Map<String, dynamic>>{};
      var skippedCount = 0;
      var itemCount = 0;

      for (final doc in source.docs) {
        final data = Map<String, dynamic>.from(doc.data());
        final area = _textValue(data['area']);
        if (area.isEmpty) {
          skippedCount++;
          continue;
        }
        final item = _monthlyViewItemFromData(
          docId: doc.id,
          data: data,
          updatedAt: data['updatedAt'],
        );
        item['area'] = area;
        grouped.putIfAbsent(area, () => <String, dynamic>{})[doc.id] = item;
        itemCount++;
      }

      final existingViews = await _firestore
          .collection(_monthlyPlateStatusViewCollection)
          .get()
          .timeout(const Duration(seconds: 30));

      WriteBatch batch = _firestore.batch();
      var pendingWrites = 0;
      var deletedViewCount = 0;

      Future<void> commitIfFull() async {
        if (pendingWrites < 450) return;
        await batch.commit().timeout(const Duration(seconds: 30));
        batch = _firestore.batch();
        pendingWrites = 0;
      }

      for (final entry in grouped.entries) {
        batch.set(
          _firestore.collection(_monthlyPlateStatusViewCollection).doc(entry.key),
          <String, dynamic>{
            'area': entry.key,
            'updatedAt': FieldValue.serverTimestamp(),
            'totalCount': entry.value.length,
            'items': entry.value,
          },
        );
        pendingWrites++;
        await commitIfFull();
      }

      for (final doc in existingViews.docs) {
        if (grouped.containsKey(doc.id)) continue;
        batch.delete(doc.reference);
        pendingWrites++;
        deletedViewCount++;
        await commitIfFull();
      }

      if (pendingWrites > 0) {
        await batch.commit().timeout(const Duration(seconds: 30));
      }

      return MonthlyPlateViewRebuildResult(
        areaCount: grouped.length,
        itemCount: itemCount,
        skippedCount: skippedCount,
        deletedViewCount: deletedViewCount,
      );
    } on FirebaseException catch (e, st) {
      await _showMonthlyFirebaseDebug(
        operation: 'monthly.rebuildAllMonthlyPlateStatusViews',
        error: e,
        stackTrace: st,
        details: <String, Object?>{
          'collection': _monthlyPlateStatusCollection,
          'viewCollection': _monthlyPlateStatusViewCollection,
          'query': 'where(type == 정기)',
        },
      );
      throw MonthlyPlateStatusWriteException(
        'monthly_plate_status_view 전체 재생성에 실패했습니다.',
        cause: e,
      );
    } on TimeoutException catch (e, st) {
      await _showMonthlyFirebaseDebug(
        operation: 'monthly.rebuildAllMonthlyPlateStatusViews.timeout',
        error: e,
        stackTrace: st,
        details: <String, Object?>{
          'collection': _monthlyPlateStatusCollection,
          'viewCollection': _monthlyPlateStatusViewCollection,
          'query': 'where(type == 정기)',
        },
      );
      throw MonthlyPlateStatusWriteException(
        'monthly_plate_status_view 전체 재생성이 시간 초과되었습니다.',
        cause: e,
      );
    } catch (e, st) {
      await _showMonthlyFirebaseDebug(
        operation: 'monthly.rebuildAllMonthlyPlateStatusViews.unknown',
        error: e,
        stackTrace: st,
        details: <String, Object?>{
          'collection': _monthlyPlateStatusCollection,
          'viewCollection': _monthlyPlateStatusViewCollection,
          'query': 'where(type == 정기)',
        },
      );
      throw MonthlyPlateStatusWriteException(
        'monthly_plate_status_view 전체 재생성 중 알 수 없는 오류가 발생했습니다.',
        cause: e,
      );
    }
  }

  @override
  Future<void> deleteMonthlyPlateStatus({
    required String documentId,
  }) async {
    final trimmed = documentId.trim();
    if (trimmed.isEmpty) {
      return;
    }

    final areaIndex = trimmed.lastIndexOf('_');
    final area = areaIndex >= 0 && areaIndex + 1 < trimmed.length ? trimmed.substring(areaIndex + 1) : '';

    try {
      final batch = _firestore.batch();
      batch.delete(_firestore.collection(_monthlyPlateStatusCollection).doc(trimmed));
      if (area.trim().isNotEmpty) {
        batch.set(
          _firestore.collection(_monthlyPlateStatusViewCollection).doc(area.trim()),
          <String, dynamic>{
            'area': area.trim(),
            'updatedAt': FieldValue.serverTimestamp(),
            'items': <String, dynamic>{
              trimmed: FieldValue.delete(),
            },
          },
          SetOptions(merge: true),
        );
      }
      await batch.commit().timeout(const Duration(seconds: 10));
    } catch (e, st) {
      await _showMonthlyFirebaseDebug(
        operation: 'monthly.deleteMonthlyPlateStatus',
        error: e,
        stackTrace: st,
        details: <String, Object?>{
          'collection': _monthlyPlateStatusCollection,
          'viewCollection': _monthlyPlateStatusViewCollection,
          'docId': trimmed,
          'area': area,
          'writePath': '$_monthlyPlateStatusCollection/$trimmed delete + $_monthlyPlateStatusViewCollection/$area items delete',
        },
      );
      rethrow;
    }
  }

  @override
  Future<void> recordMonthlyPaymentAndMaybeExtend({
    required String plateNumber,
    required String area,
    required String paidBy,
    required int paymentAmount,
    required String note,
    required bool extended,
    required String regularType,
    required String periodUnit,
    required int durationValue,
    String? startDate,
    String? endDate,
    String? extendedBy,
  }) async {
    final safeArea = area.trim();
    final canonicalPlate = _canonicalPlateNumber(plateNumber);
    final docId = _plateDocId(canonicalPlate, safeArea);
    final ref = _firestore.collection(_monthlyPlateStatusCollection).doc(docId);
    final viewRef = _firestore.collection(_monthlyPlateStatusViewCollection).doc(safeArea);
    final historyEntry = <String, dynamic>{
      'paidAt': DateTime.now().toIso8601String(),
      'paidBy': paidBy,
      'amount': paymentAmount,
      'paymentAmount': paymentAmount,
      'note': note,
      'extended': extended,
      'regularType': regularType,
      'periodUnit': periodUnit,
      'durationValue': durationValue,
      'regularDurationValue': durationValue,
      if (startDate != null && startDate.trim().isNotEmpty) 'startDate': startDate.trim(),
      if (endDate != null && endDate.trim().isNotEmpty) 'endDate': endDate.trim(),
    };

    final payload = <String, dynamic>{
      'payment_history': FieldValue.arrayUnion([historyEntry]),
      'updatedAt': FieldValue.serverTimestamp(),
    };

    if (extended &&
        startDate != null &&
        startDate.trim().isNotEmpty &&
        endDate != null &&
        endDate.trim().isNotEmpty) {
      payload['startDate'] = startDate.trim();
      payload['endDate'] = endDate.trim();
      payload['extendedAt'] = FieldValue.serverTimestamp();
      payload['extendedBy'] = extendedBy ?? paidBy;
    }

    try {
      await _firestore.runTransaction((tx) async {
        final snap = await tx.get(ref).timeout(const Duration(seconds: 10));
        final existing = snap.data() ?? <String, dynamic>{};
        tx.update(ref, payload);

        final viewData = Map<String, dynamic>.from(existing);
        viewData['plateNumber'] = canonicalPlate;
        viewData['area'] = safeArea;
        viewData['paymentCount'] = _paymentCountFromData(existing) + 1;
        viewData['updatedAt'] = FieldValue.serverTimestamp();
        if (extended &&
            startDate != null &&
            startDate.trim().isNotEmpty &&
            endDate != null &&
            endDate.trim().isNotEmpty) {
          viewData['startDate'] = startDate.trim();
          viewData['endDate'] = endDate.trim();
        }
        tx.set(
          viewRef,
          <String, dynamic>{
            'area': safeArea,
            'updatedAt': FieldValue.serverTimestamp(),
            'items': <String, dynamic>{
              docId: _monthlyViewItemFromData(
                docId: docId,
                data: viewData,
                updatedAt: FieldValue.serverTimestamp(),
              ),
            },
          },
          SetOptions(merge: true),
        );
      }).timeout(const Duration(seconds: 10));
    } catch (e, st) {
      await _showMonthlyFirebaseDebug(
        operation: 'monthly.recordMonthlyPaymentAndMaybeExtend',
        error: e,
        stackTrace: st,
        details: <String, Object?>{
          'collection': _monthlyPlateStatusCollection,
          'viewCollection': _monthlyPlateStatusViewCollection,
          'docId': docId,
          'plateNumber': canonicalPlate,
          'area': safeArea,
          'paidBy': paidBy,
          'paymentAmount': paymentAmount,
          'note': note,
          'extended': extended,
          'regularType': regularType,
          'periodUnit': periodUnit,
          'durationValue': durationValue,
          'startDate': startDate,
          'endDate': endDate,
          'extendedBy': extendedBy,
          'writePath': '$_monthlyPlateStatusCollection/$docId update + $_monthlyPlateStatusViewCollection/$safeArea items.$docId update',
          'fieldUpdates': payload.keys.toList(growable: false),
        },
      );
      rethrow;
    }
  }

  @override
  Future<void> extendMonthlyDateRange({
    required String plateNumber,
    required String area,
    required String startDate,
    required String endDate,
    required String extendedBy,
  }) async {
    final safeArea = area.trim();
    final canonicalPlate = _canonicalPlateNumber(plateNumber);
    final docId = _plateDocId(canonicalPlate, safeArea);
    final ref = _firestore.collection(_monthlyPlateStatusCollection).doc(docId);
    final viewRef = _firestore.collection(_monthlyPlateStatusViewCollection).doc(safeArea);
    try {
      await _firestore.runTransaction((tx) async {
        final snap = await tx.get(ref).timeout(const Duration(seconds: 10));
        final existing = snap.data() ?? <String, dynamic>{};
        final payload = <String, dynamic>{
          'startDate': startDate,
          'endDate': endDate,
          'updatedAt': FieldValue.serverTimestamp(),
          'extendedAt': FieldValue.serverTimestamp(),
          'extendedBy': extendedBy,
        };
        tx.update(ref, payload);
        final viewData = Map<String, dynamic>.from(existing);
        viewData['plateNumber'] = canonicalPlate;
        viewData['area'] = safeArea;
        viewData['startDate'] = startDate;
        viewData['endDate'] = endDate;
        viewData['updatedAt'] = FieldValue.serverTimestamp();
        tx.set(
          viewRef,
          <String, dynamic>{
            'area': safeArea,
            'updatedAt': FieldValue.serverTimestamp(),
            'items': <String, dynamic>{
              docId: _monthlyViewItemFromData(
                docId: docId,
                data: viewData,
                updatedAt: FieldValue.serverTimestamp(),
              ),
            },
          },
          SetOptions(merge: true),
        );
      }).timeout(const Duration(seconds: 10));
    } catch (e, st) {
      await _showMonthlyFirebaseDebug(
        operation: 'monthly.extendMonthlyDateRange',
        error: e,
        stackTrace: st,
        details: <String, Object?>{
          'collection': _monthlyPlateStatusCollection,
          'viewCollection': _monthlyPlateStatusViewCollection,
          'docId': docId,
          'plateNumber': canonicalPlate,
          'area': safeArea,
          'startDate': startDate,
          'endDate': endDate,
          'extendedBy': extendedBy,
          'writePath': '$_monthlyPlateStatusCollection/$docId update + $_monthlyPlateStatusViewCollection/$safeArea items.$docId update',
        },
      );
      rethrow;
    }
  }

  @override
  Future<void> clearMonthlyMemoAndStatusWithAudit({
    required String plateNumber,
    required String area,
    required String clearedBy,
  }) async {
    final safeArea = area.trim();
    final canonicalPlate = _canonicalPlateNumber(plateNumber);
    final docId = _plateDocId(canonicalPlate, safeArea);
    final ref = _firestore.collection(_monthlyPlateStatusCollection).doc(docId);
    final viewRef = _firestore.collection(_monthlyPlateStatusViewCollection).doc(safeArea);
    try {
      await _firestore.runTransaction((tx) async {
        final snap = await tx.get(ref).timeout(const Duration(seconds: 10));
        final existing = snap.data() ?? <String, dynamic>{};
        final payload = <String, dynamic>{
          'customStatus': '',
          'statusList': <String>[],
          'updatedAt': FieldValue.serverTimestamp(),
          'clearedAt': FieldValue.serverTimestamp(),
          'clearedBy': clearedBy,
        };
        tx.update(ref, payload);
        final viewData = Map<String, dynamic>.from(existing);
        viewData['plateNumber'] = canonicalPlate;
        viewData['area'] = safeArea;
        viewData['customStatus'] = '';
        viewData['statusList'] = <String>[];
        viewData['hasMemo'] = false;
        viewData['updatedAt'] = FieldValue.serverTimestamp();
        tx.set(
          viewRef,
          <String, dynamic>{
            'area': safeArea,
            'updatedAt': FieldValue.serverTimestamp(),
            'items': <String, dynamic>{
              docId: _monthlyViewItemFromData(
                docId: docId,
                data: viewData,
                updatedAt: FieldValue.serverTimestamp(),
              ),
            },
          },
          SetOptions(merge: true),
        );
      }).timeout(const Duration(seconds: 10));
    } catch (e, st) {
      await _showMonthlyFirebaseDebug(
        operation: 'monthly.clearMonthlyMemoAndStatusWithAudit',
        error: e,
        stackTrace: st,
        details: <String, Object?>{
          'collection': _monthlyPlateStatusCollection,
          'viewCollection': _monthlyPlateStatusViewCollection,
          'docId': docId,
          'plateNumber': canonicalPlate,
          'area': safeArea,
          'clearedBy': clearedBy,
          'writePath': '$_monthlyPlateStatusCollection/$docId update + $_monthlyPlateStatusViewCollection/$safeArea items.$docId update',
        },
      );
      rethrow;
    }
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
    required String region,
    required String createdBy,
    required String customStatus,
    required List<String> statusList,
    required String countType,
    required int regularAmount,
    required int regularDurationValue,
    required String regularType,
    required String startDate,
    required String endDate,
    required String periodUnit,
    String? specialNote,
    bool? isExtended,
  }) async {
    final safeArea = area.trim();
    final canonicalPlate = _canonicalPlateNumber(plateNumber);
    final docId = _plateDocId(canonicalPlate, safeArea);
    final ref = _firestore.collection(_monthlyPlateStatusCollection).doc(docId);
    final viewRef = _firestore.collection(_monthlyPlateStatusViewCollection).doc(safeArea);

    try {
      final emptyMonthly = _isEmptyMonthlyPayload(
        customStatus: customStatus,
        statusList: statusList,
        countType: countType,
        regularAmount: regularAmount,
        regularDurationValue: regularDurationValue,
        regularType: regularType,
        startDate: startDate,
        endDate: endDate,
        periodUnit: periodUnit,
        specialNote: specialNote,
        isExtended: isExtended,
      );

      await _firestore.runTransaction((tx) async {
        final snap = await tx.get(ref).timeout(const Duration(seconds: 10));
        final existing = snap.data() ?? <String, dynamic>{};

        if (emptyMonthly) {
          tx.delete(ref);
          if (safeArea.isNotEmpty) {
            tx.set(
              viewRef,
              <String, dynamic>{
                'area': safeArea,
                'updatedAt': FieldValue.serverTimestamp(),
                'items': <String, dynamic>{
                  docId: FieldValue.delete(),
                },
              },
              SetOptions(merge: true),
            );
          }
          return;
        }

        final base = <String, dynamic>{
          'customStatus': customStatus.trim(),
          'statusList': statusList,
          'updatedAt': FieldValue.serverTimestamp(),
          'createdBy': createdBy,
          'type': '정기',
          'countType': countType,
          'regularAmount': regularAmount,
          'regularDurationValue': regularDurationValue,
          'regularDurationHours': regularDurationValue,
          'regularType': regularType,
          'startDate': startDate,
          'endDate': endDate,
          'periodUnit': periodUnit,
          'area': safeArea,
          'region': region.trim().isEmpty ? '전국' : region.trim(),
          if (specialNote != null) 'specialNote': specialNote,
          if (isExtended != null) 'isExtended': isExtended,
        };

        if (!snap.exists) base['createdAt'] = FieldValue.serverTimestamp();

        tx.set(ref, base, SetOptions(merge: true));
        tx.set(
          viewRef,
          <String, dynamic>{
            'area': safeArea,
            'updatedAt': FieldValue.serverTimestamp(),
            'items': <String, dynamic>{
              docId: _monthlyViewItemFromWritePayload(
                docId: docId,
                plateNumber: canonicalPlate,
                area: safeArea,
                region: region,
                customStatus: customStatus,
                statusList: statusList,
                countType: countType,
                regularAmount: regularAmount,
                regularDurationValue: regularDurationValue,
                regularType: regularType,
                startDate: startDate,
                endDate: endDate,
                periodUnit: periodUnit,
                paymentCount: _paymentCountFromData(existing),
              ),
            },
          },
          SetOptions(merge: true),
        );
      }).timeout(const Duration(seconds: 10));
    } on FirebaseException catch (e, st) {
      await _showMonthlyFirebaseDebug(
        operation: 'monthly.setMonthlyPlateStatus',
        error: e,
        stackTrace: st,
        details: <String, Object?>{
          'collection': _monthlyPlateStatusCollection,
          'viewCollection': _monthlyPlateStatusViewCollection,
          'docId': docId,
          'plateNumber': canonicalPlate,
          'area': safeArea,
          'region': region,
          'createdBy': createdBy,
          'customStatus': customStatus,
          'statusList': statusList,
          'countType': countType,
          'regularAmount': regularAmount,
          'regularDurationValue': regularDurationValue,
          'regularType': regularType,
          'startDate': startDate,
          'endDate': endDate,
          'periodUnit': periodUnit,
          'specialNote': specialNote,
          'isExtended': isExtended,
          'writePath': '$_monthlyPlateStatusCollection/$docId set + $_monthlyPlateStatusViewCollection/$safeArea items.$docId set',
        },
      );
      throw MonthlyPlateStatusWriteException(
        'monthly_plate_status 반영에 실패했습니다.',
        cause: e,
      );
    } on TimeoutException catch (e, st) {
      await _showMonthlyFirebaseDebug(
        operation: 'monthly.setMonthlyPlateStatus.timeout',
        error: e,
        stackTrace: st,
        details: <String, Object?>{
          'collection': _monthlyPlateStatusCollection,
          'viewCollection': _monthlyPlateStatusViewCollection,
          'docId': docId,
          'plateNumber': canonicalPlate,
          'area': safeArea,
          'region': region,
          'createdBy': createdBy,
          'customStatus': customStatus,
          'statusList': statusList,
          'countType': countType,
          'regularAmount': regularAmount,
          'regularDurationValue': regularDurationValue,
          'regularType': regularType,
          'startDate': startDate,
          'endDate': endDate,
          'periodUnit': periodUnit,
          'specialNote': specialNote,
          'isExtended': isExtended,
          'writePath': '$_monthlyPlateStatusCollection/$docId set + $_monthlyPlateStatusViewCollection/$safeArea items.$docId set',
        },
      );
      throw MonthlyPlateStatusWriteException(
        'monthly_plate_status 반영 중 시간이 초과되었습니다.',
        cause: e,
      );
    } catch (e, st) {
      await _showMonthlyFirebaseDebug(
        operation: 'monthly.setMonthlyPlateStatus.unknown',
        error: e,
        stackTrace: st,
        details: <String, Object?>{
          'collection': _monthlyPlateStatusCollection,
          'viewCollection': _monthlyPlateStatusViewCollection,
          'docId': docId,
          'plateNumber': canonicalPlate,
          'area': safeArea,
          'region': region,
          'createdBy': createdBy,
          'customStatus': customStatus,
          'statusList': statusList,
          'countType': countType,
          'regularAmount': regularAmount,
          'regularDurationValue': regularDurationValue,
          'regularType': regularType,
          'startDate': startDate,
          'endDate': endDate,
          'periodUnit': periodUnit,
          'specialNote': specialNote,
          'isExtended': isExtended,
          'writePath': '$_monthlyPlateStatusCollection/$docId set + $_monthlyPlateStatusViewCollection/$safeArea items.$docId set',
        },
      );
      throw MonthlyPlateStatusWriteException(
        'monthly_plate_status 반영 중 알 수 없는 오류가 발생했습니다.',
        cause: e,
      );
    }
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
      await _syncMonthlyViewItemFromSource(plateNumber: plateNumber, area: area);
    } on FirebaseException catch (e, st) {
      await _showMonthlyFirebaseDebug(
        operation: 'monthly.setMonthlyMemoAndStatusOnly',
        error: e,
        stackTrace: st,
        details: <String, Object?>{
          'collection': 'monthly_plate_status',
          'docId': _plateDocId(plateNumber, area),
          'plateNumber': plateNumber,
          'area': area,
          'createdBy': createdBy,
          'customStatus': customStatus,
          'statusList': statusList,
          'skipIfDocMissing': skipIfDocMissing,
          'writePath': 'PlateStatusService.setMonthlyMemoAndStatusOnly',
        },
      );
      throw MonthlyPlateStatusWriteException(
        'monthly_plate_status 반영에 실패했습니다.',
        cause: e,
      );
    } on TimeoutException catch (e, st) {
      await _showMonthlyFirebaseDebug(
        operation: 'monthly.setMonthlyMemoAndStatusOnly.timeout',
        error: e,
        stackTrace: st,
        details: <String, Object?>{
          'collection': 'monthly_plate_status',
          'docId': _plateDocId(plateNumber, area),
          'plateNumber': plateNumber,
          'area': area,
          'createdBy': createdBy,
          'customStatus': customStatus,
          'statusList': statusList,
          'skipIfDocMissing': skipIfDocMissing,
          'writePath': 'PlateStatusService.setMonthlyMemoAndStatusOnly',
        },
      );
      throw MonthlyPlateStatusWriteException(
        'monthly_plate_status 반영 중 시간이 초과되었습니다.',
        cause: e,
      );
    } catch (e, st) {
      await _showMonthlyFirebaseDebug(
        operation: 'monthly.setMonthlyMemoAndStatusOnly.unknown',
        error: e,
        stackTrace: st,
        details: <String, Object?>{
          'collection': 'monthly_plate_status',
          'docId': _plateDocId(plateNumber, area),
          'plateNumber': plateNumber,
          'area': area,
          'createdBy': createdBy,
          'customStatus': customStatus,
          'statusList': statusList,
          'skipIfDocMissing': skipIfDocMissing,
          'writePath': 'PlateStatusService.setMonthlyMemoAndStatusOnly',
        },
      );
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
