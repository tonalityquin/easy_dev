import 'package:cloud_firestore/cloud_firestore.dart';
import '../../enums/plate_type.dart';
import '../../models/plate_model.dart';
import '../../screens/type_pages/debugs/firestore_logger.dart';

class PlateStreamService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// 외부에 노출되는 스트림 메서드 (모델 리스트 변환)
  Stream<List<PlateModel>> streamToCurrentArea(
      PlateType type,
      String area, {
        bool descending = true,
        String? location,
      }) {
    FirestoreLogger().log(
      'streamToCurrentArea called: type=${type.name}, area=$area, descending=$descending, location=$location',
    );

    final query = _buildPlateQuery(
      type: type,
      area: area,
      location: location,
      descending: descending,
    );

    return query.snapshots().map((snapshot) {
      final results = snapshot.docs.map((doc) {
        try {
          return PlateModel.fromDocument(doc);
        } catch (e) {
          FirestoreLogger().log('❌ streamToCurrentArea parsing error: $e');
          return null;
        }
      }).whereType<PlateModel>().toList();

      FirestoreLogger().log('✅ streamToCurrentArea loaded: ${results.length} items');
      return results;
    });
  }

  /// ✅ 미정산 출차완료 전용: 원본 QuerySnapshot 스트림 (docChanges 사용 용도)
  /// - type: departureCompleted
  /// - area: 필수
  /// - isLockedFee == false (미정산만)
  /// - orderBy: request_time (descending 인자 반영)
  Stream<QuerySnapshot<Map<String, dynamic>>> departureUnpaidSnapshots({
    required String area,
    bool descending = true,
  }) {
    final query = _firestore
        .collection('plates')
        .where('type', isEqualTo: PlateType.departureCompleted.firestoreValue)
        .where('area', isEqualTo: area)
        .where('isLockedFee', isEqualTo: false)
        .orderBy('request_time', descending: descending);

    FirestoreLogger().log(
      'departureUnpaidSnapshots called: area=$area, descending=$descending',
    );

    return query.snapshots();
  }

  /// 내부 쿼리 빌더 (조건 확장 가능)
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

    // 출차 완료 상태: 요금 잠김이 아닌 경우만(미정산)
    if (type == PlateType.departureCompleted) {
      query = query.where('isLockedFee', isEqualTo: false);
    }

    // 주차 완료 상태: location 필터링 추가 (전달 시에만)
    if (type == PlateType.parkingCompleted && location != null && location.isNotEmpty) {
      query = query.where('location', isEqualTo: location);
    }

    // 정렬 기준
    query = query.orderBy('request_time', descending: descending);

    return query;
  }
}
