import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:developer' as dev;

class FirestoreFields {
  static const String id = 'id';
  static const String locationName = 'locationName';
  static const String area = 'area';
  static const String isSelected = 'isSelected';
}

/// 주차 구역 데이터를 관리하는 추상 클래스
abstract class LocationRepository {
  /// Firestore에서 주차 구역 데이터를 스트림 형태로 가져오는 메서드
  Stream<List<Map<String, dynamic>>> getLocationsStream();

  /// Firestore에 새로운 주차 구역 데이터를 추가하는 메서드
  Future<void> addLocation(String locationName, String area);

  /// Firestore에서 여러 개의 주차 구역 데이터를 삭제하는 메서드
  Future<void> deleteLocations(List<String> ids);

  /// 특정 주차 구역 선택 상태를 토글하는 메서드
  Future<void> toggleLocationSelection(String id, bool isSelected);
}

/// Firestore 기반 주차 구역 데이터 관리 구현 클래스
class FirestoreLocationRepository implements LocationRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  @override

  /// Firestore에서 주차 구역 데이터를 실시간 스트림으로 가져오는 메서드
  Stream<List<Map<String, dynamic>>> getLocationsStream() {
    return _getCollectionRef().snapshots().map((snapshot) {
      return snapshot.docs.map((doc) {
        final data = doc.data();
        return {
          FirestoreFields.id: doc.id,
          FirestoreFields.locationName: data[FirestoreFields.locationName]?.toString() ?? '',
          FirestoreFields.area: data[FirestoreFields.area]?.toString() ?? '',
          FirestoreFields.isSelected: (data[FirestoreFields.isSelected] ?? false) == true,
        };
      }).toList();
    });
  }

  CollectionReference<Map<String, dynamic>> _getCollectionRef() {
    return _firestore.collection('locations');
  }

  @override

  /// Firestore에 새로운 주차 구역 데이터를 추가하는 메서드
  Future<void> addLocation(String locationName, String area) async {
    try {
      final docRef = _firestore.collection('locations').doc(locationName);
      final docSnapshot = await docRef.get();

      if (docSnapshot.exists) {
        dev.log("DB에 이미 존재하는 구역: $locationName");
        return; // 중복 추가 방지
      }

      await docRef.set({
        'locationName': locationName,
        'area': area,
        'isSelected': false,
      });
    } on FirebaseException catch (e) {
      dev.log("DB 에러 (addLocation): ${e.message}");
      throw Exception("DB 저장 실패: ${e.message}");
    }
  }

  @override

  /// Firestore에서 여러 개의 주차 구역 데이터를 삭제하는 메서드
  Future<void> deleteLocations(List<String> ids) async {
    try {
      await Future.wait(
        ids.map((id) async {
          final docRef = _firestore.collection('locations').doc(id);
          final docSnapshot = await docRef.get();

          if (docSnapshot.exists) {
            await docRef.delete();
          } else {
            dev.log("DB에 존재하지 않는 구역 (deleteLocations): $id");
          }
        }),
      );
    } on FirebaseException catch (e) {
      dev.log("DB 에러 (deleteLocations): ${e.message}");
      throw Exception("DB 삭제 실패: ${e.message}");
    }
  }

  @override

  /// 특정 주차 구역 선택 상태를 토글하는 메서드
  Future<void> toggleLocationSelection(String id, bool isSelected) async {
    try {
      final docRef = _firestore.collection('locations').doc(id);
      final docSnapshot = await docRef.get();

      if (docSnapshot.exists) {
        await docRef.update({'isSelected': isSelected});
      } else {
        dev.log("DB에 존재하지 않는 구역 (toggleLocationSelection): $id");
      }
    } on FirebaseException catch (e) {
      dev.log("DB 에러 (toggleLocationSelection): ${e.message}");
      throw Exception("DB 업데이트 실패: ${e.message}");
    }
  }
}
