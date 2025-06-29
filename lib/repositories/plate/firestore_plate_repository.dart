import 'package:cloud_firestore/cloud_firestore.dart';
import '../../enums/plate_type.dart';
import '../../models/plate_model.dart';
import 'plate_repository.dart';
import 'dart:developer' as dev;

class FirestorePlateRepository implements PlateRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  @override
  Stream<List<PlateModel>> getPlatesByTypeAndArea(
    PlateType type,
    String area, {
    bool descending = true,
  }) {
    Query<Map<String, dynamic>> query = _firestore
        .collection('plates')
        .where('type', isEqualTo: type.firestoreValue)
        .where('area', isEqualTo: area)
        .orderBy('request_time', descending: descending);

    return query.snapshots().map(
          (snapshot) => snapshot.docs.map((doc) => PlateModel.fromDocument(doc)).toList(),
        );
  }

  @override
  Future<int> getPlateCountByTypeAndArea(
    PlateType type,
    String area,
  ) async {
    final aggregateQuerySnapshot = await _firestore
        .collection('plates')
        .where('type', isEqualTo: type.firestoreValue)
        .where('area', isEqualTo: area)
        .count()
        .get();

    return aggregateQuerySnapshot.count ?? 0;
  }

  @override
  Future<List<PlateModel>> getPlatesByFourDigit({
    required String plateFourDigit,
    required String area,
  }) async {
    final querySnapshot = await _firestore
        .collection('plates')
        .where('plate_four_digit', isEqualTo: plateFourDigit)
        .where('area', isEqualTo: area)
        .get();

    return querySnapshot.docs.map((doc) => PlateModel.fromDocument(doc)).toList();
  }

  @override
  Future<List<PlateModel>> getPlatesByLocation({
    required PlateType type,
    required String area,
    required String location,
  }) async {
    final querySnapshot = await _firestore
        .collection('plates')
        .where('type', isEqualTo: type.firestoreValue)
        .where('area', isEqualTo: area)
        .where('location', isEqualTo: location)
        .get();

    return querySnapshot.docs.map((doc) => PlateModel.fromDocument(doc)).toList();
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
  Future<void> updatePlate(String documentId, Map<String, dynamic> updatedFields) async {
    final docRef = _firestore.collection('plates').doc(documentId);

    try {
      await docRef.update(updatedFields);
      dev.log("✅ 문서 업데이트 완료: $documentId", name: "Firestore");
    } catch (e) {
      dev.log("🔥 문서 업데이트 실패: $e", name: "Firestore");
      rethrow;
    }
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
  Future<void> addRequestOrCompleted({
    required String plateNumber,
    required String location,
    required String area,
    required PlateType plateType,
    required String userName,
    String? billingType,
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
    String? paymentMethod,
    String? customStatus,
  }) async {
    final documentId = '${plateNumber}_$area';

    final existingPlate = await getPlate(documentId);
    if (existingPlate != null) {
      if (existingPlate.type == PlateType.departureCompleted.firestoreValue) {
        dev.log("⚠️ departure_completed 중복 등록 허용: $plateNumber");
      } else {
        dev.log("🚨 중복된 번호판 등록 시도: $plateNumber");
        throw Exception("이미 등록된 번호판입니다: $plateNumber");
      }
    }

    if (billingType != null) {
      try {
        final billDoc = await _firestore.collection('bill').doc('${billingType}_$area').get();

        if (billDoc.exists) {
          final billData = billDoc.data()!;
          dev.log('🔥 Firestore에서 가져온 정산 데이터: $billData');
          basicStandard = billData['basicStandard'] as int? ?? 0;
          basicAmount = billData['basicAmount'] as int? ?? 0;
          addStandard = billData['addStandard'] as int? ?? 0;
          addAmount = billData['addAmount'] as int? ?? 0;
        } else {
          throw Exception('🚨 Firestore에서 정산 데이터를 찾을 수 없음');
        }
      } catch (e) {
        dev.log("🔥 Firestore 에러 (addRequestOrCompleted): $e");
        throw Exception("Firestore 데이터 로드 실패: $e");
      }
    }

    final plateFourDigit = plateNumber.length >= 4 ? plateNumber.substring(plateNumber.length - 4) : plateNumber;

    final bool effectiveIsLockedFee = isLockedFee || (billingType == null || billingType.trim().isEmpty);

    final plate = PlateModel(
      id: documentId,
      plateNumber: plateNumber,
      plateFourDigit: plateFourDigit,
      type: plateType.firestoreValue,
      requestTime: DateTime.now(),
      endTime: endTime,
      location: location.isNotEmpty ? location : '미지정',
      area: area,
      userName: userName,
      billingType: billingType,
      statusList: statusList ?? [],
      basicStandard: basicStandard ?? 0,
      basicAmount: basicAmount ?? 0,
      addStandard: addStandard ?? 0,
      addAmount: addAmount ?? 0,
      region: region,
      imageUrls: imageUrls,
      isSelected: false,
      selectedBy: null,
      isLockedFee: effectiveIsLockedFee,
      lockedAtTimeInSeconds: lockedAtTimeInSeconds,
      lockedFeeAmount: lockedFeeAmount,
      paymentMethod: paymentMethod,
      customStatus: customStatus,
    );

    dev.log('🔥 저장할 PlateModel: ${plate.toMap()}');
    await addOrUpdatePlate(documentId, plate);

    if (customStatus != null && customStatus.trim().isNotEmpty) {
      final statusDocRef = _firestore.collection('plate_status').doc(documentId);
      final expireAt = Timestamp.fromDate(DateTime.now().add(const Duration(days: 1)));

      await statusDocRef.set({
        'customStatus': customStatus,
        'updatedAt': Timestamp.now(),
        'createdBy': userName,
        'expireAt': expireAt,
      });
    }
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
  Future<int> getPlateCountByType(
    PlateType type, {
    DateTime? selectedDate,
    required String area,
  }) async {
    try {
      Query<Map<String, dynamic>> query =
          _firestore.collection('plates').where('type', isEqualTo: type.firestoreValue).where('area', isEqualTo: area);

      if (selectedDate != null && type == PlateType.departureCompleted) {
        final start = DateTime(selectedDate.year, selectedDate.month, selectedDate.day);
        final end = start.add(const Duration(days: 1));
        query = query.where('request_time', isGreaterThanOrEqualTo: start).where('request_time', isLessThan: end);
      }

      final result = await query.count().get();
      return result.count ?? 0;
    } catch (e) {
      dev.log("🔥 문서 count 실패: $e", name: "Firestore");
      return 0;
    }
  }

  @override
  Future<bool> checkDuplicatePlate({
    required String plateNumber,
    required String area,
  }) async {
    final querySnapshot = await _firestore
        .collection('plates')
        .where('plate_number', isEqualTo: plateNumber)
        .where('area', isEqualTo: area)
        .where('type', whereIn: [
          PlateType.parkingRequests.firestoreValue,
          PlateType.parkingCompleted.firestoreValue,
          PlateType.departureRequests.firestoreValue,
        ])
        .limit(1)
        .get();

    return querySnapshot.docs.isNotEmpty;
  }
}
