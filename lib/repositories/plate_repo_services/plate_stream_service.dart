import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../enums/plate_type.dart';
import '../../models/plate_model.dart';
import '../../screens/stub_package/debug_package/debug_firestore_logger.dart';

class PlateStreamService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Stream<List<PlateModel>> streamToCurrentArea(
      PlateType type,
      String area, {
        bool descending = true,
        String? location,
      }) {
    final query = _buildPlateQuery(
      type: type,
      area: area,
      location: location,
      descending: descending,
    );

    return query
        .snapshots()
    // Firestore 스트림 실패만 로깅 + 재전파
        .handleError((e, st) {
      // ignore: unawaited_futures
      DebugFirestoreLogger().log({
        'op': 'plates.stream.currentArea',
        'collection': 'plates',
        'filters': {
          'type': type.firestoreValue,
          'area': area,
          if (location != null && location.isNotEmpty) 'location': location,
        },
        'orderBy': {'field': 'request_time', 'descending': descending},
        'error': {
          'type': e.runtimeType.toString(),
          if (e is FirebaseException) 'code': e.code,
          'message': e.toString(),
        },
        'stack': st.toString(),
        'tags': ['plates', 'stream', 'currentArea', 'error'],
      }, level: 'error');

      Error.throwWithStackTrace(e, st);
    })
        .map((snapshot) {
      final results = snapshot.docs
          .map((doc) {
        try {
          return PlateModel.fromDocument(doc);
        } catch (e, st) {
          // 파싱 실패도 Firestore 로거에 error 기록(동기 컨텍스트 → await 없음)
          // ignore: unawaited_futures
          DebugFirestoreLogger().log({
            'op': 'plates.stream.parse',
            'collection': 'plates',
            'docPath': doc.reference.path,
            'docId': doc.id,
            'error': {
              'type': e.runtimeType.toString(),
              'message': e.toString(),
            },
            'stack': st.toString(),
            'tags': ['plates', 'stream', 'parse', 'error'],
            // 과도한 로그 방지: 키만 일부 기록
            'rawKeys': doc.data().keys.take(30).toList(),
          }, level: 'error');
          return null;
        }
      })
          .whereType<PlateModel>()
          .toList();

      return results;
    });
  }

  Query<Map<String, dynamic>> _buildPlateQuery({
    required PlateType type,
    required String area,
    String? location,
    bool descending = true,
  }) {
    Query<Map<String, dynamic>> query = _firestore
        .collection('plates')
        .where('type', isEqualTo: type.firestoreValue)
        .where('area', isEqualTo: area);

    if (type == PlateType.departureCompleted) {
      query = query.where('isLockedFee', isEqualTo: false);
    }

    if (type == PlateType.parkingCompleted && location != null && location.isNotEmpty) {
      query = query.where('location', isEqualTo: location);
    }

    query = query.orderBy('request_time', descending: descending);

    return query;
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> departureUnpaidSnapshots({
    required String area,
    bool descending = true,
  }) {
    final query = _firestore
        .collection('plates')
        .where('type', isEqualTo: PlateType.departureCompleted.firestoreValue)
        .where('area', isEqualTo: area)
        .where('isLockedFee', isEqualTo: false)
        .orderBy(PlateFields.requestTime, descending: descending); // ← 상수화

    // 스트림 에러 Firestore 로깅 + 전파
    return query.snapshots().handleError((e, st) {
      // ignore: unawaited_futures
      DebugFirestoreLogger().log({
        'op': 'plates.stream.departureUnpaid',
        'collection': 'plates',
        'filters': {
          'type': PlateType.departureCompleted.firestoreValue,
          'area': area,
          'isLockedFee': false,
        },
        'orderBy': {'field': PlateFields.requestTime, 'descending': descending},
        'error': {
          'type': e.runtimeType.toString(),
          if (e is FirebaseException) 'code': e.code,
          'message': e.toString(),
        },
        'stack': st.toString(),
        'tags': ['plates', 'stream', 'departureUnpaid', 'error'],
      }, level: 'error');

      Error.throwWithStackTrace(e, st); // 전파
    });
  }
}
