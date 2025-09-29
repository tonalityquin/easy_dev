// lib/repositories/plate_repo_services/plate_stream_service.dart
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../enums/plate_type.dart';
import '../../models/plate_model.dart';
import '../../screens/dev_package/debug_package/debug_firestore_logger.dart';
import '../../utils/usage_reporter.dart'; // ✅

class PlateStreamService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Stream<List<PlateModel>> streamToCurrentArea(
    PlateType type,
    String area, {
    bool descending = true,
    String? location,
    bool countInitialSnapshot = false, // ✅ (3)
  }) {
    final query = _buildPlateQuery(
      type: type,
      area: area,
      location: location,
      descending: descending,
    );

    bool _didEmitOnce = false; // ✅ (3) 초기 스냅샷 스킵 플래그

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
    }).map((snapshot) {
      // ✅ 서버 확정 스냅샷만 집계 (로컬 보류 스냅샷 제외)
      if (!snapshot.metadata.hasPendingWrites) {
        final added = snapshot.docChanges.where((c) => c.type == DocumentChangeType.added).length;
        final modified = snapshot.docChanges.where((c) => c.type == DocumentChangeType.modified).length;
        final n = added + modified;
        if (n > 0) {
          if (!_didEmitOnce) {
            _didEmitOnce = true;
            if (countInitialSnapshot) {
              // ignore: unawaited_futures
              UsageReporter.instance.report(
                area: area,
                action: 'read',
                n: n,
                source: 'PlateStreamService.streamToCurrentArea.onData',
              );
            }
          } else {
            // ignore: unawaited_futures
            UsageReporter.instance.report(
              area: area,
              action: 'read',
              n: n,
              source: 'PlateStreamService.streamToCurrentArea.onData',
            );
          }
        }
      }

      final results = snapshot.docs
          .map((doc) {
            try {
              return PlateModel.fromDocument(doc);
            } catch (e, st) {
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
    Query<Map<String, dynamic>> query =
        _firestore.collection('plates').where('type', isEqualTo: type.firestoreValue).where('area', isEqualTo: area);

    if (type == PlateType.departureCompleted) {
      query = query.where('isLockedFee', isEqualTo: false);
    }

    if (type == PlateType.parkingCompleted && location != null && location.isNotEmpty) {
      query = query.where('location', isEqualTo: location);
    }

    query = query.orderBy('request_time', descending: descending);

    return query;
  }

  // ✅ 출차완료(미정산) 스냅샷 스트림: 기본은 초기 스냅샷 미집계, opt-in 시 집계
  Stream<QuerySnapshot<Map<String, dynamic>>> departureUnpaidSnapshots({
    required String area,
    bool descending = true,
    bool countInitialSnapshot = false, // ✅ (3)
  }) {
    final query = _firestore
        .collection('plates')
        .where('type', isEqualTo: PlateType.departureCompleted.firestoreValue)
        .where('area', isEqualTo: area)
        .where('isLockedFee', isEqualTo: false)
        .orderBy(PlateFields.requestTime, descending: descending);

    bool _didEmitOnceDeparture = false; // ✅ (3)

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

      Error.throwWithStackTrace(e, st);
    }).map((snapshot) {
      // ✅ 서버 확정 스냅샷만 집계 (로컬 보류 스냅샷 제외)
      if (!snapshot.metadata.hasPendingWrites) {
        final added = snapshot.docChanges.where((c) => c.type == DocumentChangeType.added).length;
        final modified = snapshot.docChanges.where((c) => c.type == DocumentChangeType.modified).length;
        final n = added + modified;
        if (n > 0) {
          if (!_didEmitOnceDeparture) {
            _didEmitOnceDeparture = true;
            if (countInitialSnapshot) {
              // ignore: unawaited_futures
              UsageReporter.instance.report(
                area: area,
                action: 'read',
                n: n,
                source: 'PlateStreamService.departureUnpaidSnapshots.onData',
              );
            }
          } else {
            // ignore: unawaited_futures
            UsageReporter.instance.report(
              area: area,
              action: 'read',
              n: n,
              source: 'PlateStreamService.departureUnpaidSnapshots.onData',
            );
          }
        }
      }
      return snapshot;
    });
  }
}
