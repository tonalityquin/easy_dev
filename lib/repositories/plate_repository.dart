import 'package:cloud_firestore/cloud_firestore.dart';

/// 차량 번호판 요청 데이터를 나타내는 모델 클래스
class PlateModel {
  final String id; // Firestore 문서 ID
  final String plateNumber; // 차량 번호판
  final String type; // 요청 유형
  final DateTime requestTime; // 요청 시간
  final String location; // 요청 위치
  final String area; // 요청 지역
  final String userName; // 생성한 유저 이름
  final bool isSelected; // 선택 여부
  final String? selectedBy; // 선택한 유저 이름

  PlateModel({
    required this.id,
    required this.plateNumber,
    required this.type,
    required this.requestTime,
    required this.location,
    required this.area,
    required this.userName,
    this.isSelected = false,
    this.selectedBy,
  });

  /// Firestore 문서 데이터를 PlateRequest 객체로 변환
  factory PlateModel.fromDocument(DocumentSnapshot<Map<String, dynamic>> doc) {
    final dynamic timestamp = doc['request_time'];
    return PlateModel(
      id: doc.id,
      plateNumber: doc['plate_number'],
      type: doc['type'],
      requestTime: (timestamp is Timestamp)
          ? timestamp.toDate()
          : (timestamp is DateTime)
              ? timestamp
              : DateTime.now(),
      location: doc['location'] ?? '미지정',
      area: doc.data()?.containsKey('area') == true ? doc['area'] : '미지정',
      userName: doc['userName'] ?? 'Unknown',
      isSelected: doc.data()?.containsKey('isSelected') == true ? doc['isSelected'] : false,
      selectedBy: doc['selectedBy'],
    );
  }

  /// PlateRequest 객체를 Map 형식으로 변환
  Map<String, dynamic> toMap() {
    return {
      'plate_number': plateNumber,
      'type': type,
      'request_time': requestTime,
      'location': location,
      'area': area,
      'userName': userName,
      'isSelected': isSelected,
      'selectedBy': selectedBy,
    };
  }
}

/// Plate 관련 데이터를 처리하는 추상 클래스
abstract class PlateRepository {
  /// 지정된 컬렉션의 데이터를 스트림 형태로 가져옴
  Stream<List<PlateModel>> getCollectionStream(String collectionName);

  /// 문서를 추가하거나 업데이트
  Future<void> addOrUpdateDocument(String collection, String documentId, Map<String, dynamic> data);

  /// 문서를 삭제
  Future<void> deleteDocument(String collection, String documentId);

  /// 특정 문서를 가져옴
  Future<Map<String, dynamic>?> getDocument(String collection, String documentId);

  /// 모든 데이터 삭제
  Future<void> deleteAllData();

  Future<void> updatePlateSelection(String collection, String id, bool isSelected, {String? selectedBy});

  /// 요청 데이터를 추가하거나 완료 데이터로 업데이트
  Future<void> addRequestOrCompleted({
    required String collection,
    required String plateNumber,
    required String location,
    required String area,
    required String type,
    required String userName,
    String? adjustmentType,
  });

  /// 특정 지역의 사용 가능한 위치 목록 가져오기
  Future<List<String>> getAvailableLocations(String area);
}

/// Firestore 기반 PlateRepository 구현 클래스
class FirestorePlateRepository implements PlateRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  @override
  Stream<List<PlateModel>> getCollectionStream(String collectionName) {
    return _firestore.collection(collectionName).snapshots().map((snapshot) {
      return snapshot.docs.map((doc) => PlateModel.fromDocument(doc)).toList();
    });
  }

  @override
  Future<void> addOrUpdateDocument(String collection, String documentId, Map<String, dynamic> data) async {
    final updatedData = {
      ...data,
      'selectedBy': data['selectedBy'], // 추가된 필드
    };
    await _firestore.collection(collection).doc(documentId).set(updatedData);
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
    required String userName,
    String? adjustmentType,
  }) async {
    final documentId = '${plateNumber}_$area';

    await _firestore.collection(collection).doc(documentId).set({
      'plate_number': plateNumber,
      'type': type,
      'request_time': DateTime.now(),
      'location': location.isNotEmpty ? location : '미지정',
      'area': area,
      'userName': userName,
      'adjustmentType': adjustmentType, // 🔹 Firestore에 정산 유형 저장
      'isSelected': false,
      'selectedBy': null,
    });
  }


  @override
  Future<void> updatePlateSelection(String collection, String id, bool isSelected, {String? selectedBy}) async {
    try {
      final updateData = {
        'isSelected': isSelected,
        'selectedBy': selectedBy, // 선택 유저 추가
      };

      await _firestore.collection(collection).doc(id).update(updateData);
    } catch (e) {
      throw Exception('Failed to update plate selection: $e');
    }
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
