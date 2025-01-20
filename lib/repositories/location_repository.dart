import 'package:cloud_firestore/cloud_firestore.dart';

/// 위치 데이터를 관리하는 추상 클래스
abstract class LocationRepository {
  /// Firestore 위치 데이터를 스트림 형태로 반환
  Stream<List<Map<String, dynamic>>> getLocationsStream();

  /// Firestore에 새로운 위치 추가
  Future<void> addLocation(String locationName, String area);

  /// Firestore에서 여러 위치 삭제
  Future<void> deleteLocations(List<String> ids);

  /// Firestore에서 특정 위치의 선택 상태 변경
  Future<void> toggleLocationSelection(String id, bool isSelected);
}

/// Firestore 기반 위치 데이터 관리 구현 클래스
class FirestoreLocationRepository implements LocationRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  @override
  Stream<List<Map<String, dynamic>>> getLocationsStream() {
    return _firestore.collection('locations').snapshots().map((snapshot) {
      return snapshot.docs.map((doc) {
        final data = doc.data();
        return {
          'id': doc.id,
          'locationName': data['locationName']?.toString() ?? '',
          'area': data['area']?.toString() ?? '',
          'isSelected': (data['isSelected'] ?? false) == true,
        };
      }).toList();
    });
  }

  @override
  Future<void> addLocation(String locationName, String area) async {
    try {
      await _firestore.collection('locations').doc(locationName).set({
        'locationName': locationName,
        'area': area,
        'isSelected': false,
      });
    } catch (e) {
      rethrow; // 예외 재발생
    }
  }

  @override
  Future<void> deleteLocations(List<String> ids) async {
    try {
      for (var id in ids) {
        await _firestore.collection('locations').doc(id).delete();
      }
    } catch (e) {
      rethrow; // 예외 재발생
    }
  }

  @override
  Future<void> toggleLocationSelection(String id, bool isSelected) async {
    try {
      await _firestore.collection('locations').doc(id).update({
        'isSelected': isSelected,
      });
    } catch (e) {
      rethrow; // 예외 재발생
    }
  }
}
