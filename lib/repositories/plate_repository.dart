import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

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
  final String? adjustmentType; // 🔹 정산 유형 추가
  final List<String> statusList; // 🔹 상태 리스트 추가
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
    this.adjustmentType, // 🔹 추가
    this.statusList = const [], // 🔹 추가 (기본값 빈 리스트)
    this.basicStandard,
    this.basicAmount,
    this.addStandard,
    this.addAmount,
  });

  /// Firestore 문서 데이터를 PlateRequest 객체로 변환
  factory PlateModel.fromDocument(DocumentSnapshot<Map<String, dynamic>> doc) {
    final dynamic timestamp = doc['request_time'];
    final Map<String, dynamic>? data = doc.data();

    int parseToInt(dynamic value) {
      if (value is int) return value;
      if (value is String) return int.tryParse(value) ?? 0;
      return 0;
    }

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
      basicStandard: parseToInt(data?['basicStandard']),
      basicAmount: parseToInt(data?['basicAmount']),
      addStandard: parseToInt(data?['addStandard']),
      addAmount: parseToInt(data?['addAmount']),
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
    List<String>? statusList,
    int? basicStandard,
    int? basicAmount,
    int? addStandard,
    int? addAmount,
  }) async {
    final documentId = '${plateNumber}_$area';

    // ✅ Firestore에서 adjustmentType + area 를 활용해 문서명을 직접 조회
    if (adjustmentType != null) {
      try {
        final adjustmentRef = FirebaseFirestore.instance.collection('adjustment');
        final adjustmentDoc = await adjustmentRef.doc('${adjustmentType}_$area').get();

        if (adjustmentDoc.exists) {
          final adjustmentData = adjustmentDoc.data()!;

          debugPrint('🔥 Firestore에서 가져온 정산 데이터: $adjustmentData');

          // ✅ Firestore에서 가져온 값이 존재하면 적용
          basicStandard = int.tryParse(adjustmentData['basicStandard'].toString()) ?? 0;
          basicAmount = int.tryParse(adjustmentData['basicAmount'].toString()) ?? 0;
          addStandard = int.tryParse(adjustmentData['addStandard'].toString()) ?? 0;
          addAmount = int.tryParse(adjustmentData['addAmount'].toString()) ?? 0;

          debugPrint(
              '✅ Firestore 반영된 값: basicStandard=$basicStandard, basicAmount=$basicAmount, addStandard=$addStandard, addAmount=$addAmount');
        } else {
          debugPrint('⚠ Firestore에서 adjustmentType=$adjustmentType, area=$area 데이터를 찾을 수 없음');
        }
      } catch (e) {
        debugPrint('❌ Firestore 데이터 로드 실패: $e');
      }
    }

    // ✅ Firestore에 저장할 데이터
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
    final docRef = FirebaseFirestore.instance.collection(collection).doc(id);

    try {
      await FirebaseFirestore.instance.runTransaction((transaction) async {
        final docSnapshot = await transaction.get(docRef);
        if (!docSnapshot.exists) throw Exception('Document not found');

        // ✅ Firestore에 업데이트 수행
        transaction.update(docRef, {
          'isSelected': isSelected,
          'selectedBy': isSelected ? selectedBy : null,
        });

        debugPrint('✅ Firestore 업데이트 완료: isSelected=$isSelected, selectedBy=$selectedBy');
      });
    } catch (e) {
      debugPrint('❌ Firestore 업데이트 실패: $e');
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
