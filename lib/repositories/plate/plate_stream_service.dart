import 'package:cloud_firestore/cloud_firestore.dart';
import '../../enums/plate_type.dart';
import '../../models/plate_model.dart';
import '../../screens/type_pages/debugs/firestore_logger.dart';

class PlateStreamService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// 특정 PlateType, 지역, 위치에 대한 plates 스트리밍
  Stream<List<PlateModel>> streamToCurrentArea(
      PlateType type,
      String area, {
        bool descending = true,
        String? location,
      }) {
    FirestoreLogger().log(
      'streamToCurrentArea called: type=${type.name}, area=$area, descending=$descending, location=$location',
    );

    Query<Map<String, dynamic>> query = _firestore
        .collection('plates')
        .where('type', isEqualTo: type.firestoreValue)
        .where('area', isEqualTo: area);

    // 출차 완료 상태 → 요금 잠김이 아닌 경우만 필터링
    if (type == PlateType.departureCompleted) {
      query = query.where('isLockedFee', isEqualTo: false);
    }

    // 주차 완료 상태이면서 location 지정된 경우 필터링
    if (location != null && location.isNotEmpty && type == PlateType.parkingCompleted) {
      query = query.where('location', isEqualTo: location);
    }

    // 시간 기준 정렬
    query = query.orderBy('request_time', descending: descending);

    // 실시간 스트림 반환
    return query.snapshots().map(
          (snapshot) => snapshot.docs.map((doc) => PlateModel.fromDocument(doc)).toList(),
    );
  }
}
