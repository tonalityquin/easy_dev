import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/plate_model.dart';
import 'plate_repository.dart';
import 'dart:developer' as dev;

/// Firestore 기반 PlateRepository 구현 클래스
class FirestorePlateRepository implements PlateRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  @override

  /// 특정 Firestore 컬렉션의 데이터를 스트림 형태로 가져오는 메서드
  Stream<List<PlateModel>> getCollectionStream(String collectionName) {
    return _firestore.collection(collectionName).snapshots().map((snapshot) {
      return snapshot.docs.map((doc) => PlateModel.fromDocument(doc)).toList();
    });
  }

  @override

  /// Firestore 문서를 추가하거나 업데이트하는 메서드
  Future<void> addOrUpdateDocument(String collection, String documentId, Map<String, dynamic> data) async {
    final docRef = _firestore.collection(collection).doc(documentId);
    final docSnapshot = await docRef.get();

    if (docSnapshot.exists) {
      final existingData = docSnapshot.data();
      if (existingData != null && _isSameData(existingData, data)) {
        dev.log("데이터 변경 없음: $documentId", name: "Firestore");
        return;
      }
    }

    await docRef.set(data, SetOptions(merge: true));
    dev.log("DB 문서 저장 완료: $documentId", name: "Firestore");
  }

  /// 기존 데이터와 새로운 데이터를 비교하는 함수
  bool _isSameData(Map<String, dynamic> oldData, Map<String, dynamic> newData) {
    if (oldData.length != newData.length) return false;
    for (String key in oldData.keys) {
      if (!newData.containsKey(key) || oldData[key] != newData[key]) {
        return false;
      }
    }
    return true;
  }

  @override

  /// Firestore 문서를 삭제하는 메서드
  Future<void> deleteDocument(String collection, String documentId) async {
    final docRef = _firestore.collection(collection).doc(documentId);
    final docSnapshot = await docRef.get();

    if (docSnapshot.exists) {
      await docRef.delete();
    } else {
      dev.log("DB에 존재하지 않는 문서 (deleteDocument): $documentId", name: "Firestore");
    }
  }

  @override

  /// Firestore에서 특정 문서를 가져오는 메서드
  Future<PlateModel?> getDocument(String collection, String documentId) async {
    final doc = await _firestore.collection(collection).doc(documentId).get();
    if (!doc.exists) return null;
    return PlateModel.fromDocument(doc);
  }

  @override

  /// Firestore의 모든 데이터를 삭제하는 메서드
  Future<void> deleteAllData() async {
    try {
      final collections = [
        'parking_requests',
        'parking_completed',
        'departure_requests',
        'departure_completed',
      ];

      await Future.wait(collections.map((collection) async {
        final snapshot = await _firestore.collection(collection).get();
        final batch = _firestore.batch();

        for (var doc in snapshot.docs) {
          batch.delete(doc.reference);
        }

        await batch.commit();
      }));
    } catch (e) {
      dev.log('❌ Firestore 전체 데이터 삭제 실패: $e');
      throw Exception("전체 데이터 삭제 실패: $e");
    }
  }

  @override

  /// 요청 또는 완료 데이터를 추가하는 메서드
  Future<void> addRequestOrCompleted({
    required String collection,
    required String plateNumber,
    required String location,
    required String area,
    required String type,
    required String userName,
    String? adjustmentType,
    List<String>? statusList,
    int? basicStandard,
    int? basicAmount,
    int? addStandard,
    int? addAmount,
  }) async {
    final documentId = '${plateNumber}_$area';

    if (adjustmentType != null) {
      try {
        final adjustmentRef = _firestore.collection('adjustment');
        final adjustmentDoc = await adjustmentRef.doc('${adjustmentType}_$area').get();

        if (adjustmentDoc.exists) {
          final adjustmentData = adjustmentDoc.data()!;
          dev.log('🔥 Firestore에서 가져온 정산 데이터: $adjustmentData');

          basicStandard = adjustmentData['basicStandard'] as int? ?? 0;
          basicAmount = adjustmentData['basicAmount'] as int? ?? 0;
          addStandard = adjustmentData['addStandard'] as int? ?? 0;
          addAmount = adjustmentData['addAmount'] as int? ?? 0;
        } else {
          throw Exception('🚨 Firestore에서 데이터를 찾을 수 없음');
        }
      } catch (e) {
        dev.log("🔥 Firestore 에러 (addRequestOrCompleted): $e");
        throw Exception("Firestore 데이터 로드 실패: $e");
      }
    }

    final data = {
      'plate_number': plateNumber,
      'type': type,
      'request_time': DateTime.now(),
      'location': location.isNotEmpty ? location : '미지정',
      'area': area,
      'userName': userName,
      'adjustmentType': adjustmentType,
      'statusList': statusList ?? [],
      'isSelected': false,
      'selectedBy': null,
      'basicStandard': basicStandard ?? 0,
      'basicAmount': basicAmount ?? 0,
      'addStandard': addStandard ?? 0,
      'addAmount': addAmount ?? 0,
    };

    dev.log('🔥 Firestore 저장 데이터: $data');

    await _firestore.collection(collection).doc(documentId).set(data);
  }

  @override

  /// 특정 번호판의 선택 상태를 업데이트하는 메서드
  Future<void> updatePlateSelection(String collection, String id, bool isSelected, {String? selectedBy}) async {
    final docRef = _firestore.collection(collection).doc(id);
    try {
      await _firestore.runTransaction((transaction) async {
        final docSnapshot = await transaction.get(docRef);
        if (!docSnapshot.exists) {
          dev.log("번호판을 찾을 수 없음: $id", name: "Firestore");
          return;
        }

        transaction.update(docRef, {
          'isSelected': isSelected,
          'selectedBy': isSelected ? selectedBy : null,
        });
      });
    } catch (e) {
      dev.log("DB 에러 (updatePlateSelection): $e", name: "Firestore");
      throw Exception("DB 업데이트 실패: $e");
    }
  }

  @override

  /// 특정 지역의 사용 가능한 구역 목록을 가져오는 메서드
  Future<List<String>> getAvailableLocations(String area) async {
    try {
      final querySnapshot = await _firestore
          .collection('locations') // Firestore의 'locations' 컬렉션
          .where('area', isEqualTo: area) // area 필터 적용
          .get();

      return querySnapshot.docs.map((doc) => doc['locationName'] as String).toList();
    } catch (e) {
      dev.log("🔥 Firestore 에러 (getAvailableLocations): $e", name: "Firestore");
      throw Exception('Firestore에서 사용 가능한 위치 목록을 가져오지 못했습니다: $e');
    }
  }
}
