import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/plate_request.dart';

/// Plate 관련 데이터를 처리하는 추상 클래스
abstract class PlateRepository {
  /// 지정된 컬렉션의 데이터를 스트림 형태로 가져옴
  Stream<List<PlateRequest>> getCollectionStream(String collectionName);

  /// 문서를 추가하거나 업데이트
  Future<void> addOrUpdateDocument(String collection, String documentId, Map<String, dynamic> data);

  /// 문서를 삭제
  Future<void> deleteDocument(String collection, String documentId);

  /// 특정 문서를 가져옴
  Future<Map<String, dynamic>?> getDocument(String collection, String documentId);

  /// 모든 데이터 삭제
  Future<void> deleteAllData();

  /// 요청 데이터를 추가하거나 완료 데이터로 업데이트
  Future<void> addRequestOrCompleted({
    required String collection,
    required String plateNumber,
    required String location,
    required String area,
    required String type,
  });

  /// 특정 지역의 사용 가능한 위치 목록 가져오기
  Future<List<String>> getAvailableLocations(String area);
}

/// Firestore 기반 PlateRepository 구현 클래스
class FirestorePlateRepository implements PlateRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  @override
  Stream<List<PlateRequest>> getCollectionStream(String collectionName) {
    return _firestore.collection(collectionName).snapshots().map((snapshot) {
      return snapshot.docs.map((doc) => PlateRequest.fromDocument(doc)).toList();
    });
  }

  @override
  Future<void> addOrUpdateDocument(String collection, String documentId, Map<String, dynamic> data) async {
    await _firestore.collection(collection).doc(documentId).set(data);
  }

  @override
  Future<void> deleteDocument(String collection, String documentId) async {
    await _firestore.collection(collection).doc(documentId).delete();
  }

  @override
  Future<Map<String, dynamic>?> getDocument(String collection, String documentId) async {
    final doc = await _firestore.collection(collection).doc(documentId).get();
    return doc.exists ? doc.data() : null;
  }

  @override
  Future<void> deleteAllData() async {
    try {
      final collections = [
        'parking_requests',
        'parking_completed',
        'departure_requests',
        'departure_completed',
      ];

      for (final collection in collections) {
        final snapshot = await _firestore.collection(collection).get();
        for (final doc in snapshot.docs) {
          await doc.reference.delete();
        }
      }
    } catch (e) {
      rethrow;
    }
  }

  @override
  Future<void> addRequestOrCompleted({
    required String collection,
    required String plateNumber,
    required String location,
    required String area,
    required String type,
  }) async {
    final documentId = '${plateNumber}_$area';

    await _firestore.collection(collection).doc(documentId).set({
      'plate_number': plateNumber,
      'type': type,
      'request_time': DateTime.now(),
      'location': location.isNotEmpty ? location : '미지정',
      'area': area,
    });
  }

  @override
  Future<List<String>> getAvailableLocations(String area) async {
    try {
      final querySnapshot = await _firestore
          .collection('locations') // Firestore의 'locations' 컬렉션
          .where('area', isEqualTo: area) // area 필터 적용
          .get();

      return querySnapshot.docs.map((doc) => doc['locationName'] as String).toList();
    } catch (e) {
      throw Exception('Failed to fetch available locations: $e');
    }
  }
}
