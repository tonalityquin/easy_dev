import 'package:cloud_firestore/cloud_firestore.dart';
import '../../enums/plate_type.dart';
import '../../models/plate_model.dart';
import 'plate_repository.dart';
import 'dart:developer' as dev;

class FirestorePlateRepository implements PlateRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  @override
  Stream<List<PlateModel>> getPlatesByType(PlateType type) {
    return _firestore
        .collection('plates')
        .where(PlateFields.type, isEqualTo: type.firestoreValue)
        .orderBy(PlateFields.requestTime, descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs.map((doc) => PlateModel.fromDocument(doc)).toList());
  }

  @override
  Future<void> addOrUpdatePlate(String documentId, PlateModel plate) async {
    final docRef = _firestore.collection('plates').doc(documentId);
    final docSnapshot = await docRef.get();
    final data = plate.toMap();

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
  Future<void> deletePlate(String documentId) async {
    final docRef = _firestore.collection('plates').doc(documentId);
    final docSnapshot = await docRef.get();

    if (docSnapshot.exists) {
      await docRef.delete();
    } else {
      dev.log("DB에 존재하지 않는 문서 (deletePlate): $documentId", name: "Firestore");
    }
  }

  @override
  Future<PlateModel?> getPlate(String documentId) async {
    final doc = await _firestore.collection('plates').doc(documentId).get();
    if (!doc.exists) return null;
    return PlateModel.fromDocument(doc);
  }

  @override
  Future<void> deleteAllData() async {
    try {
      final snapshot = await _firestore.collection('plates').get();
      final batch = _firestore.batch();
      for (var doc in snapshot.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();

      final entriesSnapshot = await _firestore.collection('logs').doc('plate_movements').collection('entries').get();
      final entriesBatch = _firestore.batch();
      for (var doc in entriesSnapshot.docs) {
        entriesBatch.delete(doc.reference);
      }
      await entriesBatch.commit();
    } catch (e) {
      dev.log('❌ Firestore 전체 데이터 삭제 실패: $e');
      throw Exception("전체 데이터 삭제 실패: $e");
    }
  }

  @override
  Future<List<PlateModel>> getPlatesByArea(PlateType type, String area) async {
    try {
      final querySnapshot = await _firestore
          .collection('plates')
          .where('type', isEqualTo: type.firestoreValue)
          .where('area', isEqualTo: area)
          .get();

      return querySnapshot.docs.map((doc) => PlateModel.fromDocument(doc)).toList();
    } catch (e) {
      dev.log("🔥 Firestore 데이터 가져오기 오류 (getPlatesByArea): $e", name: "Firestore");
      return [];
    }
  }

  @override
  Future<void> addRequestOrCompleted({
    required String plateNumber,
    required String location,
    required String area,
    required PlateType plateType,
    required String userName,
    String? adjustmentType,
    List<String>? statusList,
    int? basicStandard,
    int? basicAmount,
    int? addStandard,
    int? addAmount,
    required String region,
    List<String>? imageUrls,
    bool isLockedFee = false,
    int? lockedAtTimeInSeconds,
    int? lockedFeeAmount,
    DateTime? endTime,
  }) async {
    final documentId = '${plateNumber}_$area';

    final existingPlate = await getPlate(documentId);
    if (existingPlate != null) {
      dev.log("🚨 중복된 번호판 등록 시도: $plateNumber");
      throw Exception("이미 등록된 번호판입니다: $plateNumber");
    }

    if (adjustmentType != null) {
      try {
        final adjustmentDoc = await _firestore.collection('adjustment').doc('${adjustmentType}_$area').get();
        if (adjustmentDoc.exists) {
          final adjustmentData = adjustmentDoc.data()!;
          dev.log('🔥 Firestore에서 가져온 정산 데이터: $adjustmentData');
          basicStandard = adjustmentData['basicStandard'] as int? ?? 0;
          basicAmount = adjustmentData['basicAmount'] as int? ?? 0;
          addStandard = adjustmentData['addStandard'] as int? ?? 0;
          addAmount = adjustmentData['addAmount'] as int? ?? 0;
        } else {
          throw Exception('🚨 Firestore에서 정산 데이터를 찾을 수 없음');
        }
      } catch (e) {
        dev.log("🔥 Firestore 에러 (addRequestOrCompleted): $e");
        throw Exception("Firestore 데이터 로드 실패: $e");
      }
    }

    final plate = PlateModel(
      id: documentId,
      plateNumber: plateNumber,
      type: plateType.firestoreValue, // ✅ 여기 핵심 수정
      requestTime: DateTime.now(),
      endTime: endTime,
      location: location.isNotEmpty ? location : '미지정',
      area: area,
      userName: userName,
      adjustmentType: adjustmentType,
      statusList: statusList ?? [],
      basicStandard: basicStandard ?? 0,
      basicAmount: basicAmount ?? 0,
      addStandard: addStandard ?? 0,
      addAmount: addAmount ?? 0,
      region: region,
      imageUrls: imageUrls,
      isSelected: false,
      selectedBy: null,
      isLockedFee: isLockedFee,
      lockedAtTimeInSeconds: lockedAtTimeInSeconds,
      lockedFeeAmount: lockedFeeAmount,
    );

    dev.log('🔥 저장할 PlateModel: ${plate.toMap()}');
    await addOrUpdatePlate(documentId, plate);
  }

  @override
  Future<void> updatePlateSelection(String id, bool isSelected, {String? selectedBy}) async {
    final docRef = _firestore.collection('plates').doc(id);

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
  Future<List<String>> getAvailableLocations(String area) async {
    try {
      final querySnapshot = await _firestore.collection('locations').where('area', isEqualTo: area).get();
      return querySnapshot.docs.map((doc) => doc['locationName'] as String).toList();
    } catch (e) {
      dev.log("🔥 Firestore 에러 (getAvailableLocations): $e", name: "Firestore");
      throw Exception('Firestore에서 사용 가능한 위치 목록을 가져오지 못했습니다: $e');
    }
  }
}
