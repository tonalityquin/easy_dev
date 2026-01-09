// lib/repositories/plate_repo_services/plate_stream_service.dart

import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../enums/plate_type.dart';
import '../../models/plate_model.dart';

class PlateStreamService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// 현재 구역 스트림
  /// - type(예: parking_requests, parking_completed 등)
  /// - area 기준 필터
  /// - 필요 시 location 추가 필터
  Stream<List<PlateModel>> streamToCurrentArea(
      PlateType type,
      String area, {
        bool descending = true,
        String? location,
        bool countInitialSnapshot = false, // (사용량 리포트용, 현재는 미사용)
      }) {
    final query = _buildPlateQuery(
      type: type,
      area: area,
      location: location,
      descending: descending,
    );

    return query.snapshots().handleError((e, st) {
      // ✅ DebugDatabaseLogger 로직 제거
      Error.throwWithStackTrace(e, st);
    }).map((snapshot) {
      // 🔹 여기서는 단순히 PlateModel 리스트로 변환만 수행
      final results = snapshot.docs.map((doc) {
        try {
          return PlateModel.fromDocument(doc);
        } catch (_) {
          // ✅ DebugDatabaseLogger 로직 제거
          // 파싱 실패 문서는 스킵
          return null;
        }
      }).whereType<PlateModel>().toList();

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

  /// 출차완료(미정산) 스트림
  Stream<QuerySnapshot<Map<String, dynamic>>> departureUnpaidSnapshots({
    required String area,
    bool descending = true,
    bool countInitialSnapshot = false,
  }) {
    final query = _firestore
        .collection('plates')
        .where('type', isEqualTo: PlateType.departureCompleted.firestoreValue)
        .where('area', isEqualTo: area)
        .where('isLockedFee', isEqualTo: false)
        .orderBy(PlateFields.requestTime, descending: descending);

    return query.snapshots().handleError((e, st) {
      // ✅ DebugDatabaseLogger 로직 제거
      Error.throwWithStackTrace(e, st);
    });
  }
}
