import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

/// 🔥 숫자 변환 유틸리티 함수 추가
int parseInt(dynamic value) {
  if (value is int) return value;
  if (value is String) return int.tryParse(value) ?? 0;
  return 0;
}

/// 차량 번호판 요청 데이터를 나타내는 모델 클래스
class PlateModel {
  final String id;
  final String plateNumber;
  final String type;
  final DateTime requestTime;
  final String location;
  final String area;
  final String userName;
  final bool isSelected;
  final String? selectedBy;
  final String? adjustmentType;
  final List<String> statusList;
  final int? basicStandard;
  final int? basicAmount;
  final int? addStandard;
  final int? addAmount;

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
    this.adjustmentType,
    this.statusList = const [],
    this.basicStandard,
    this.basicAmount,
    this.addStandard,
    this.addAmount,
  });

  /// Firestore 문서 데이터를 PlateModel 객체로 변환
  factory PlateModel.fromDocument(DocumentSnapshot<Map<String, dynamic>> doc) {
    final dynamic timestamp = doc['request_time'];
    final Map<String, dynamic>? data = doc.data();

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
      area: doc['area'] ?? '미지정',
      userName: doc['userName'] ?? 'Unknown',
      isSelected: doc['isSelected'] ?? false,
      selectedBy: doc['selectedBy'],
      adjustmentType: doc['adjustmentType'],
      statusList: (doc['statusList'] is List) ? List<String>.from(doc['statusList']) : [],
      basicStandard: parseInt(data?['basicStandard']),
      basicAmount: parseInt(data?['basicAmount']),
      addStandard: parseInt(data?['addStandard']),
      addAmount: parseInt(data?['addAmount']),
    );
  }

  /// PlateModel 객체를 Map 형식으로 변환
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
      'adjustmentType': adjustmentType,
      'statusList': statusList,
      'basicStandard': basicStandard,
      'basicAmount': basicAmount,
      'addStandard': addStandard,
      'addAmount': addAmount,
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
    List<String>? statusList,
    int basicStandard, // 🔥 추가
    int basicAmount, // 🔥 추가
    int addStandard, // 🔥 추가
    int addAmount, // 🔥 추가
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

      await Future.wait(collections.map((collection) async {
        final snapshot = await _firestore.collection(collection).get();
        final batch = _firestore.batch();

        for (var doc in snapshot.docs) {
          batch.delete(doc.reference);
        }

        await batch.commit(); // 🔥 일괄 삭제 수행
      }));
    } catch (e) {
      debugPrint('❌ Firestore 전체 데이터 삭제 실패: $e');
      throw Exception("전체 데이터 삭제 실패: $e");
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
          debugPrint('🔥 Firestore에서 가져온 정산 데이터: $adjustmentData');

          basicStandard = parseInt(adjustmentData['basicStandard']);
          basicAmount = parseInt(adjustmentData['basicAmount']);
          addStandard = parseInt(adjustmentData['addStandard']);
          addAmount = parseInt(adjustmentData['addAmount']);
        } else {
          throw Exception('🚨 Firestore에서 adjustmentType=$adjustmentType, area=$area 데이터를 찾을 수 없음');
        }
      } on FirebaseException catch (e) {
        debugPrint("🔥 Firestore 에러 (addRequestOrCompleted): ${e.message}");
        throw Exception("Firestore 데이터 로드 실패: ${e.message}");
      } catch (e) {
        debugPrint("❌ 알 수 없는 에러 (addRequestOrCompleted): $e");
        throw Exception("예상치 못한 에러 발생");
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

    debugPrint('🔥 Firestore 저장 데이터: $data');

    await _firestore.collection(collection).doc(documentId).set(data);
  }

  @override
  Future<void> updatePlateSelection(String collection, String id, bool isSelected, {String? selectedBy}) async {
    final docRef = _firestore.collection(collection).doc(id);

    try {
      await _firestore.runTransaction((transaction) async {
        final docSnapshot = await transaction.get(docRef);
        if (!docSnapshot.exists) throw Exception('🚨 문서를 찾을 수 없음: $id');

        transaction.update(docRef, {
          'isSelected': isSelected,
          'selectedBy': isSelected ? selectedBy : null,
        });

        debugPrint('✅ Firestore 업데이트 완료: isSelected=$isSelected, selectedBy=$selectedBy');
      });
    } on FirebaseException catch (e) {
      debugPrint("🔥 Firestore 에러 (updatePlateSelection): ${e.message}");
      throw Exception("Firestore 업데이트 실패: ${e.message}");
    } catch (e) {
      debugPrint("❌ 알 수 없는 에러 (updatePlateSelection): $e");
      throw Exception("예상치 못한 에러 발생: $e");
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
