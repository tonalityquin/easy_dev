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
