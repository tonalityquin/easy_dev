import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../enums/plate_type.dart';
import '../../models/plate_model.dart';
import '../../screens/type_pages/debugs/firestore_logger.dart';

class PlateStreamService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Stream<List<PlateModel>> streamToCurrentArea(
    PlateType type,
    String area, {
    bool descending = true,
    String? location,
  }) {
    unawaited(FirestoreLogger().log(
      'streamToCurrentArea called: type=${type.name}, area=$area, descending=$descending, location=$location',
    ));

    final query = _buildPlateQuery(
      type: type,
      area: area,
      location: location,
      descending: descending,
    );

    // 로그 폭주 방지용: 개수 변동 시 또는 1초에 한 번만 로깅
    DateTime lastLogAt = DateTime.fromMillisecondsSinceEpoch(0);
    int? lastLoggedCount;

    return query.snapshots().handleError((e, st) {
      unawaited(FirestoreLogger().log('🔥 streamToCurrentArea stream error: $e\n$st'));
      // 로그 후 전파 (원본 스택 보존)
      Error.throwWithStackTrace(e, st);
    }).map((snapshot) {
      final results = snapshot.docs
          .map((doc) {
            try {
              return PlateModel.fromDocument(doc);
            } catch (e, st) {
              unawaited(FirestoreLogger().log(
                '❌ streamToCurrentArea parsing error: docId=${doc.id}, type=${type.name}, area=$area, error=$e\n$st',
              ));
              return null;
            }
          })
          .whereType<PlateModel>()
          .toList();

      final now = DateTime.now();
      final needLog = lastLoggedCount != results.length || now.difference(lastLogAt) > const Duration(seconds: 1);
      if (needLog) {
        unawaited(FirestoreLogger()
            .log('✅ streamToCurrentArea loaded: ${results.length} items (type=${type.name}, area=$area)'));
        lastLoggedCount = results.length;
        lastLogAt = now;
      }

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

    // 비동기 로깅 (결과 대기 안 함)
    unawaited(FirestoreLogger().log(
      'departureUnpaidSnapshots called: area=$area, descending=$descending',
    ));

    // 스트림 에러 로깅 + 전파
    return query.snapshots().handleError((e, st) {
      unawaited(FirestoreLogger().log('🔥 departureUnpaidSnapshots stream error: $e\n$st'));
      Error.throwWithStackTrace(e, st); // 전파
    });
  }
}
