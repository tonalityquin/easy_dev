import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../../enums/plate_type.dart';
import '../../models/plate_model.dart';
import 'plate_repository.dart';
import 'dart:developer' as dev;
import '../../utils/firestore_logger.dart'; // ✅ FirestoreLogger import

class FirestorePlateRepository implements PlateRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  int? _cachedPlateCount;
  DateTime? _lastFetchTime;

  @override
  Stream<List<PlateModel>> streamToCurrentArea(
    PlateType type,
    String area, {
    bool descending = true,
    String? location,
  }) {
    FirestoreLogger()
        .log('streamToCurrentArea called: type=${type.name}, area=$area, descending=$descending, location=$location');

    Query<Map<String, dynamic>> query =
        _firestore.collection('plates').where('type', isEqualTo: type.firestoreValue).where('area', isEqualTo: area);

    if (type == PlateType.departureCompleted) {
      query = query.where('isLockedFee', isEqualTo: false);
    }

    if (location != null && location.isNotEmpty && type == PlateType.parkingCompleted) {
      query = query.where('location', isEqualTo: location);
    }

    query = query.orderBy('request_time', descending: descending);

    return query.snapshots().map(
          (snapshot) => snapshot.docs.map((doc) => PlateModel.fromDocument(doc)).toList(),
        );
  }

  @override
  Future<void> addOrUpdatePlate(String documentId, PlateModel plate) async {
    await FirestoreLogger().log('addOrUpdatePlate called: $documentId, data=${plate.toMap()}');

    final docRef = _firestore.collection('plates').doc(documentId);
    final docSnapshot = await docRef.get();
    final data = plate.toMap();

    if (docSnapshot.exists) {
      final existingData = docSnapshot.data();
      if (existingData != null && _isSameData(existingData, data)) {
        dev.log("데이터 변경 없음: $documentId", name: "Firestore");
        await FirestoreLogger().log('addOrUpdatePlate skipped (no changes)');
        return;
      }
    }

    await docRef.set(data, SetOptions(merge: true));
    dev.log("DB 문서 저장 완료: $documentId", name: "Firestore");
    await FirestoreLogger().log('addOrUpdatePlate success: $documentId');
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
    await FirestoreLogger().log('updatePlate called: $documentId, fields=$updatedFields');
    final docRef = _firestore.collection('plates').doc(documentId);

    try {
      await docRef.update(updatedFields);
      dev.log("✅ 문서 업데이트 완료: $documentId", name: "Firestore");
      await FirestoreLogger().log('updatePlate success: $documentId');
    } catch (e) {
      dev.log("🔥 문서 업데이트 실패: $e", name: "Firestore");
      await FirestoreLogger().log('updatePlate error: $e');
      rethrow;
    }
  }

  @override
  Future<PlateModel?> getPlate(String documentId) async {
    await FirestoreLogger().log('getPlate called: $documentId');
    final doc = await _firestore.collection('plates').doc(documentId).get();
    if (!doc.exists) return null;
    await FirestoreLogger().log('getPlate success: $documentId');
    return PlateModel.fromDocument(doc);
  }

  @override
  Future<List<PlateModel>> getPlatesByLocation({
    required PlateType type,
    required String area,
    required String location,
  }) async {
    await FirestoreLogger().log('getPlatesByLocation called: type=${type.name}, area=$area, location=$location');
    final querySnapshot = await _firestore
        .collection('plates')
        .where('type', isEqualTo: type.firestoreValue)
        .where('area', isEqualTo: area)
        .where('location', isEqualTo: location)
        .get();

    final result = querySnapshot.docs.map((doc) => PlateModel.fromDocument(doc)).toList();

    await FirestoreLogger().log('getPlatesByLocation success: ${result.length} items loaded');
    return result;
  }

  @override
  Future<void> deletePlate(String documentId) async {
    await FirestoreLogger().log('deletePlate called: $documentId');
    final docRef = _firestore.collection('plates').doc(documentId);
    final docSnapshot = await docRef.get();

    if (docSnapshot.exists) {
      await docRef.delete();
      await FirestoreLogger().log('deletePlate success: $documentId');
    } else {
      debugPrint("DB에 존재하지 않는 문서 (deletePlate): $documentId");
      await FirestoreLogger().log('deletePlate skipped: document not found');
    }
  }

  @override
  Future<List<PlateModel>> fourDigitCommonQuery({
    required String plateFourDigit,
    required String area,
  }) async {
    await FirestoreLogger().log('fourDigitCommonQuery called: plateFourDigit=$plateFourDigit, area=$area');

    final querySnapshot = await _firestore
        .collection('plates')
        .where('plate_four_digit', isEqualTo: plateFourDigit)
        .where('area', isEqualTo: area)
        .get();

    final result = querySnapshot.docs.map((doc) => PlateModel.fromDocument(doc)).toList();

    await FirestoreLogger().log('fourDigitCommonQuery success: ${result.length} items loaded');
    return result;
  }

  @override
  Future<List<PlateModel>> fourDigitSignatureQuery({
    required String plateFourDigit,
    required String area,
  }) async {
    await FirestoreLogger().log(
      'fourDigitSignatureQuery called: plateFourDigit=$plateFourDigit, area=$area',
    );

    final querySnapshot = await _firestore
        .collection('plates')
        .where('plate_four_digit', isEqualTo: plateFourDigit)
        .where('area', isEqualTo: area)
        .where('type', isEqualTo: PlateType.parkingCompleted.firestoreValue) // ✅ type 조건 추가
        .get();

    final result = querySnapshot.docs.map((doc) => PlateModel.fromDocument(doc)).toList();

    await FirestoreLogger().log(
      'fourDigitSignatureQuery success: ${result.length} items loaded',
    );

    return result;
  }

  @override
  Future<void> addPlate({
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
    await FirestoreLogger().log('addPlate called: $documentId, plateNumber=$plateNumber');

    final existingPlate = await getPlate(documentId);
    if (existingPlate != null) {
      final existingType = PlateType.values.firstWhere(
        (type) => type.firestoreValue == existingPlate.type,
        orElse: () => PlateType.parkingRequests,
      );

      if (_isAllowedDuplicate(existingType)) {
        debugPrint("⚠️ ${existingType.name} 상태 중복 등록 허용: $plateNumber");
        await FirestoreLogger().log('addPlate allowed duplicate: $plateNumber (${existingType.name})');
      } else {
        debugPrint("🚨 중복된 번호판 등록 시도: $plateNumber (${existingType.name})");
        await FirestoreLogger().log('addPlate error: duplicate plate - $plateNumber');
        throw Exception("이미 등록된 번호판입니다: $plateNumber");
      }
    }

    if (billingType != null) {
      try {
        final billDoc = await _firestore.collection('bill').doc('${billingType}_$area').get();

        if (billDoc.exists) {
          final billData = billDoc.data()!;
          debugPrint('🔥 Firestore에서 가져온 정산 데이터: $billData');
          basicStandard = billData['basicStandard'] as int? ?? 0;
          basicAmount = billData['basicAmount'] as int? ?? 0;
          addStandard = billData['addStandard'] as int? ?? 0;
          addAmount = billData['addAmount'] as int? ?? 0;

          await FirestoreLogger().log('addPlate billing data loaded: $billingType');
        } else {
          throw Exception('Firestore에서 정산 데이터를 찾을 수 없음');
        }
      } catch (e) {
        debugPrint("🔥 Firestore 에러 (addPlate): $e");
        await FirestoreLogger().log('addPlate billing error: $e');
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

    debugPrint('🔥 저장할 PlateModel: ${plate.toMap()}');
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

      await FirestoreLogger().log('addPlate customStatus saved: $customStatus');
    }

    await FirestoreLogger().log('addPlate success: $documentId');
  }

  bool _isAllowedDuplicate(PlateType type) {
    return type == PlateType.departureCompleted;
  }

  @override
  Future<void> recordWhoPlateClick(
    String id,
    bool isSelected, {
    String? selectedBy,
  }) async {
    await FirestoreLogger().log('recordWhoPlateClick called: $id, isSelected=$isSelected, selectedBy=$selectedBy');
    final docRef = _firestore.collection('plates').doc(id);

    try {
      await docRef.update({
        'isSelected': isSelected,
        'selectedBy': isSelected ? selectedBy : null,
      });
      await FirestoreLogger().log('recordWhoPlateClick success: $id');
    } on FirebaseException catch (e) {
      if (e.code == 'not-found') {
        debugPrint("번호판 문서를 찾을 수 없습니다: $id");
        await FirestoreLogger().log('recordWhoPlateClick skipped (not found): $id');
        return;
      }
      debugPrint("DB 에러 (recordWhoPlateClick): $e");
      await FirestoreLogger().log('recordWhoPlateClick error: $e');
      throw Exception("DB 업데이트 실패: $e");
    } catch (e) {
      debugPrint("DB 에러 (recordWhoPlateClick): $e");
      await FirestoreLogger().log('recordWhoPlateClick error: $e');
      throw Exception("DB 업데이트 실패: $e");
    }
  }

  @override
  Future<int> getPlateCountForTypePage(
    PlateType type,
    String area,
  ) async {
    await FirestoreLogger().log('getPlateCountForTypePage called: type=${type.name}, area=$area');
    final aggregateQuerySnapshot = await _firestore
        .collection('plates')
        .where('type', isEqualTo: type.firestoreValue)
        .where('area', isEqualTo: area)
        .count()
        .get();

    final count = aggregateQuerySnapshot.count ?? 0;
    await FirestoreLogger().log('getPlateCountForTypePage success: $count');
    return count;
  }

  @override
  Future<int> getPlateCountToCurrentArea(String area) async {
    final now = DateTime.now();

    // 🔹 캐시 조건 확인
    final isCacheValid = _cachedPlateCount != null &&
        _lastFetchTime != null &&
        now.difference(_lastFetchTime!) < const Duration(minutes: 3);

    if (isCacheValid) {
      debugPrint('📦 캐시된 plate count 반환: $_cachedPlateCount (area=$area)');
      await FirestoreLogger().log('getPlateCountToCurrentArea: returned from cache → count=$_cachedPlateCount');
      return _cachedPlateCount!;
    }

    // 🔹 캐시 무효 → Firestore 호출
    debugPrint('📡 Firestore에서 plate count 쿼리 수행 (area=$area)');
    await FirestoreLogger().log('getPlateCountToCurrentArea: querying Firestore (area=$area)');

    try {
      final snapshot = await _firestore.collection('plates').where('area', isEqualTo: area).count().get();

      final count = snapshot.count ?? 0;

      // 🔹 캐시 갱신
      _cachedPlateCount = count;
      _lastFetchTime = now;

      debugPrint('✅ Firestore에서 plate count 수신: $count (area=$area)');
      await FirestoreLogger().log('getPlateCountToCurrentArea success: count=$count');

      return count;
    } catch (e) {
      debugPrint('❌ Firestore plate count 실패: $e');
      await FirestoreLogger().log('getPlateCountToCurrentArea failed: $e');
      return 0;
    }
  }

  @override
  Future<int> getPlateCountForClockInPage(
    PlateType type, {
    DateTime? selectedDate,
    required String area,
  }) async {
    // 필터링: 요청 타입만 허용
    if (type != PlateType.parkingRequests && type != PlateType.departureRequests) {
      return 0; // 무시할 타입
    }

    await FirestoreLogger()
        .log('getPlateCountForClockInPage called: type=${type.name}, area=$area, selectedDate=$selectedDate');
    try {
      Query<Map<String, dynamic>> query =
          _firestore.collection('plates').where('type', isEqualTo: type.firestoreValue).where('area', isEqualTo: area);

      final result = await query.count().get();
      final count = result.count ?? 0;
      await FirestoreLogger().log('getPlateCountForClockInPage success: $count');
      return count;
    } catch (e) {
      await FirestoreLogger().log('getPlateCountForClockInPage error: $e');
      return 0;
    }
  }

  @override
  Future<int> getPlateCountForClockOutPage(
    PlateType type, {
    DateTime? selectedDate,
    required String area,
  }) async {
    // 필터링: 완료 타입만 허용
    if (type != PlateType.parkingCompleted && type != PlateType.departureCompleted) {
      return 0; // 무시할 타입
    }

    await FirestoreLogger()
        .log('getPlateCountForClockOutPage called: type=${type.name}, area=$area, selectedDate=$selectedDate');
    try {
      Query<Map<String, dynamic>> query =
          _firestore.collection('plates').where('type', isEqualTo: type.firestoreValue).where('area', isEqualTo: area);

      if (selectedDate != null && type == PlateType.departureCompleted) {
        final start = DateTime(selectedDate.year, selectedDate.month, selectedDate.day);
        final end = start.add(const Duration(days: 1));
        query = query.where('request_time', isGreaterThanOrEqualTo: start).where('request_time', isLessThan: end);
      }

      final result = await query.count().get();
      final count = result.count ?? 0;
      await FirestoreLogger().log('getPlateCountForClockOutPage success: $count');
      return count;
    } catch (e) {
      await FirestoreLogger().log('getPlateCountForClockOutPage error: $e');
      return 0;
    }
  }

  @override
  Future<bool> checkDuplicatePlate({
    required String plateNumber,
    required String area,
  }) async {
    await FirestoreLogger().log('checkDuplicatePlate called: plateNumber=$plateNumber, area=$area');
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

    final isDuplicate = querySnapshot.docs.isNotEmpty;
    await FirestoreLogger().log('checkDuplicatePlate result: $isDuplicate');
    return isDuplicate;
  }
}
