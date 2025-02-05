import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

/// 위치 데이터를 관리하는 추상 클래스
abstract class LocationRepository {
  Stream<List<Map<String, dynamic>>> getLocationsStream();

  Future<void> addLocation(String locationName, String area);

  Future<void> deleteLocations(List<String> ids);

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
    } on FirebaseException catch (e) {
      debugPrint("🔥 Firestore 에러 (addLocation): ${e.message}");
      throw Exception("Firestore 저장 실패: ${e.message}");
    }
  }

  @override
  Future<void> deleteLocations(List<String> ids) async {
    try {
      await Future.wait(
        ids.map((id) => _firestore.collection('locations').doc(id).delete()),
      );
    } on FirebaseException catch (e) {
      debugPrint("🔥 Firestore 에러 (deleteLocations): ${e.message}");
      throw Exception("Firestore 삭제 실패: ${e.message}");
    }
  }

  @override
  Future<void> toggleLocationSelection(String id, bool isSelected) async {
    try {
      await _firestore.collection('locations').doc(id).update({
        'isSelected': isSelected,
      });
    } on FirebaseException catch (e) {
      debugPrint("🔥 Firestore 에러 (toggleLocationSelection): ${e.message}");
      throw Exception("Firestore 업데이트 실패: ${e.message}");
    }
  }
}
