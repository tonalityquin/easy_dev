import 'package:cloud_firestore/cloud_firestore.dart';

class LockedPlateRecord {
  final String docId;
  final Map<String, dynamic> data;

  const LockedPlateRecord({
    required this.docId,
    required this.data,
  });
}

class EndWorkReportFirestoreRepository {
  static const String _plateOutLogRoot = 'plate_out_log';
  static const String _monthsSub = 'months';
  static const String _platesSub = 'plates';

  final FirebaseFirestore _firestore;

  EndWorkReportFirestoreRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  Future<List<LockedPlateRecord>> fetchLockedDepartureCompletedPlates({
    required String area,
  }) async {
    final snap = await _firestore
        .collection('plates')
        .where('type', isEqualTo: 'departure_completed')
        .where('area', isEqualTo: area)
        .where('isLockedFee', isEqualTo: true)
        .get();

    return snap.docs
        .map((d) => LockedPlateRecord(docId: d.id, data: d.data()))
        .toList(growable: false);
  }

  Future<void> appendPlateOutLogs({
    required String area,
    required List<LockedPlateRecord> plates,
  }) async {
    final safeArea = _safeArea(area);
    if (plates.isEmpty) return;

    for (final plate in plates) {
      await _appendSinglePlateOutLog(
        safeArea: safeArea,
        record: plate,
      );
    }
  }

  Future<void> _appendSinglePlateOutLog({
    required String safeArea,
    required LockedPlateRecord record,
  }) async {
    final data = record.data;
    final now = DateTime.now();
    final completedAt = _readDate(data['departureCompletedAt']) ??
        _readDate(data['updatedAt']) ??
        now;
    final monthKey = _monthKey(completedAt);
    final plateNumber = _plateNumberFromRecord(record, safeArea);
    final plateKey = _normalizedPlateKey(plateNumber);
    final fourDigit = _plateFourDigit(plateNumber);
    final lockedFeeAmount = _readInt(data['lockedFeeAmount']) ??
        _latestIntFromLogs(data, 'lockedFee');
    final paymentMethod = _stringValue(data, const <String>['paymentMethod']);
    final reason = _latestReason(data);
    final customStatus = _stringValue(data, const <String>['customStatus']);
    final logKey = _logKey(
      plateDocId: record.docId,
      completedAt: completedAt,
      lockedFeeAmount: lockedFeeAmount,
      paymentMethod: paymentMethod,
      reason: reason,
    );
    final ref = _plateOutLogRef(
      area: safeArea,
      monthKey: monthKey,
      plateDocId: record.docId,
    );
    final createdAt = Timestamp.fromDate(now);
    final logEntry = <String, dynamic>{
      'logKey': logKey,
      'sourcePlateDocId': record.docId,
      'sourceType': data['type'],
      'departureCompletedAt': Timestamp.fromDate(completedAt),
      'departureCompletedDate': _dateText(completedAt),
      'departureCompletedTime': _timeText(completedAt),
      'lockedFeeAmount': lockedFeeAmount,
      'paymentMethod': paymentMethod,
      'reason': reason,
      'customStatus': customStatus,
      'createdAt': createdAt,
    };

    await _firestore.runTransaction((tx) async {
      final snap = await tx.get(ref);
      final existing = snap.data();
      final rawLogs = existing?['logs'];
      final existingLogs = rawLogs is List ? rawLogs : const <dynamic>[];
      final alreadyExists = existingLogs.any((item) {
        if (item is! Map) return false;
        return item['logKey'] == logKey;
      });
      final update = <String, dynamic>{
        'area': safeArea,
        'monthKey': monthKey,
        'plateDocId': record.docId,
        'plateNumber': plateNumber,
        'plateKey': plateKey,
        'plate_four_digit': fourDigit,
        'logScope': _plateOutLogRoot,
        'lastDepartureCompletedAt': Timestamp.fromDate(completedAt),
        'lastLockedFeeAmount': lockedFeeAmount,
        'lastPaymentMethod': paymentMethod,
        'lastReason': reason,
        'lastCustomStatus': customStatus,
        'updatedAt': FieldValue.serverTimestamp(),
        if (!snap.exists) 'createdAt': FieldValue.serverTimestamp(),
      };

      if (!alreadyExists) {
        update['logs'] = FieldValue.arrayUnion([logEntry]);
        update['logCount'] = FieldValue.increment(1);
      }

      tx.set(ref, update, SetOptions(merge: true));
    });
  }

  Future<void> saveMonthlyEndWorkReport({
    required String division,
    required String area,
    required String monthKey,
    required String dateStr,
    required Map<String, dynamic> vehicleCount,
    required Map<String, dynamic> metrics,
    required String createdAtIso,
    required String uploadedBy,
    String? logsUrl,
  }) async {
    final areaRef = _firestore.collection('end_work_reports').doc('area_$area');
    final monthRef = areaRef.collection('months').doc(monthKey);

    final historyEntry = <String, dynamic>{
      'date': dateStr,
      'monthKey': monthKey,
      'createdAt': createdAtIso,
      'uploadedBy': uploadedBy,
      'vehicleCount': vehicleCount,
      'metrics': metrics,
      if (logsUrl != null) 'logsUrl': logsUrl,
    };

    final dayPayload = <String, dynamic>{
      'division': division,
      'area': area,
      'monthKey': monthKey,
      'date': dateStr,
      'vehicleCount': vehicleCount,
      'metrics': metrics,
      'createdAt': createdAtIso,
      'uploadedBy': uploadedBy,
      if (logsUrl != null) 'logsUrl': logsUrl,
      'updatedAt': FieldValue.serverTimestamp(),
      'history': FieldValue.arrayUnion(<Map<String, dynamic>>[historyEntry]),
    };

    final batch = _firestore.batch();

    batch.set(
      areaRef,
      <String, dynamic>{
        'division': division,
        'area': area,
        'updatedAt': FieldValue.serverTimestamp(),
        'lastMonthKey': monthKey,
        'lastReportDate': dateStr,
      },
      SetOptions(merge: true),
    );

    batch.set(
      monthRef,
      <String, dynamic>{
        'division': division,
        'area': area,
        'monthKey': monthKey,
        'updatedAt': FieldValue.serverTimestamp(),
        'lastReportDate': dateStr,
        'reports': <String, dynamic>{
          dateStr: dayPayload,
        },
      },
      SetOptions(merge: true),
    );

    await batch.commit();
  }

  Future<void> cleanupLockedDepartureCompletedPlates({
    required String area,
    required List<String> plateDocIds,
  }) async {
    final batch = _firestore.batch();

    for (final id in plateDocIds) {
      batch.delete(_firestore.collection('plates').doc(id));
    }

    final countersRef = _firestore.collection('plate_counters').doc('area_$area');
    batch.set(
      countersRef,
      <String, dynamic>{
        'departureCompletedEvents': 0,
      },
      SetOptions(merge: true),
    );

    await batch.commit();
  }

  DocumentReference<Map<String, dynamic>> _plateOutLogRef({
    required String area,
    required String monthKey,
    required String plateDocId,
  }) {
    return _firestore
        .collection(_plateOutLogRoot)
        .doc(area)
        .collection(_monthsSub)
        .doc(monthKey)
        .collection(_platesSub)
        .doc(plateDocId);
  }

  static String _safeArea(String area) {
    final trimmed = area.trim();
    return trimmed.isEmpty ? 'unknown' : trimmed;
  }

  static String _monthKey(DateTime dt) {
    return '${dt.year}${dt.month.toString().padLeft(2, '0')}';
  }

  static String _normalizedPlateKey(String plateNumber) {
    return plateNumber.replaceAll('-', '').replaceAll(' ', '').trim();
  }

  static String _plateFourDigit(String plateNumber) {
    final key = _normalizedPlateKey(plateNumber);
    if (key.length <= 4) return key;
    return key.substring(key.length - 4);
  }

  static String _plateNumberFromRecord(
    LockedPlateRecord record,
    String safeArea,
  ) {
    final direct = _stringValue(
      record.data,
      const <String>['plate_number', 'plateNumber'],
    );
    if (direct.isNotEmpty) return direct;

    final suffix = '_$safeArea';
    if (record.docId.endsWith(suffix)) {
      return record.docId.substring(0, record.docId.length - suffix.length);
    }

    final index = record.docId.lastIndexOf('_');
    if (index > 0) return record.docId.substring(0, index);
    return record.docId;
  }

  static DateTime? _readDate(dynamic value) {
    if (value == null) return null;
    if (value is Timestamp) return value.toDate();
    if (value is DateTime) return value;
    if (value is int) {
      if (value > 1000000000000) {
        return DateTime.fromMillisecondsSinceEpoch(value);
      }
      return DateTime.fromMillisecondsSinceEpoch(value * 1000);
    }
    if (value is num) {
      final intValue = value.toInt();
      if (intValue > 1000000000000) {
        return DateTime.fromMillisecondsSinceEpoch(intValue);
      }
      return DateTime.fromMillisecondsSinceEpoch(intValue * 1000);
    }
    if (value is String) return DateTime.tryParse(value);
    return null;
  }

  static int? _readInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) {
      return int.tryParse(value.replaceAll(',', '').trim());
    }
    return null;
  }

  static int? _latestIntFromLogs(Map<String, dynamic> data, String key) {
    final logs = data['logs'];
    if (logs is! List) return null;

    for (final item in logs.reversed) {
      if (item is! Map) continue;
      final parsed = _readInt(item[key]);
      if (parsed != null) return parsed;
    }

    return null;
  }

  static String _stringValue(Map<String, dynamic> data, List<String> keys) {
    for (final key in keys) {
      final value = data[key];
      if (value == null) continue;
      final text = value.toString().trim();
      if (text.isNotEmpty) return text;
    }
    return '';
  }

  static String _latestReason(Map<String, dynamic> data) {
    final direct = data['reason'];
    if (direct != null && direct.toString().trim().isNotEmpty) {
      return direct.toString().trim();
    }

    final logs = data['logs'];
    if (logs is! List) return '';

    for (final item in logs.reversed) {
      if (item is! Map) continue;
      final reason = item['reason'];
      if (reason != null && reason.toString().trim().isNotEmpty) {
        return reason.toString().trim();
      }
    }

    return '';
  }

  static String _logKey({
    required String plateDocId,
    required DateTime completedAt,
    required int? lockedFeeAmount,
    required String paymentMethod,
    required String reason,
  }) {
    return [
      plateDocId,
      completedAt.toUtc().toIso8601String(),
      lockedFeeAmount?.toString() ?? '',
      paymentMethod,
      reason,
    ].join('|');
  }

  static String _dateText(DateTime dt) {
    return '${dt.year.toString().padLeft(4, '0')}-'
        '${dt.month.toString().padLeft(2, '0')}-'
        '${dt.day.toString().padLeft(2, '0')}';
  }

  static String _timeText(DateTime dt) {
    return '${dt.hour.toString().padLeft(2, '0')}:'
        '${dt.minute.toString().padLeft(2, '0')}:'
        '${dt.second.toString().padLeft(2, '0')}';
  }

  static dynamic jsonSafe(dynamic v) {
    if (v == null) return null;

    if (v is Timestamp) return v.toDate().toIso8601String();
    if (v is DateTime) return v.toIso8601String();

    if (v is GeoPoint) {
      return <String, dynamic>{
        '_type': 'GeoPoint',
        'lat': v.latitude,
        'lng': v.longitude,
      };
    }

    if (v is DocumentReference) {
      return <String, dynamic>{
        '_type': 'DocumentReference',
        'path': v.path,
      };
    }

    if (v is num || v is String || v is bool) return v;

    if (v is List) return v.map(jsonSafe).toList();
    if (v is Map) {
      return v.map(
        (key, value) => MapEntry(key.toString(), jsonSafe(value)),
      );
    }

    return v.toString();
  }
}
