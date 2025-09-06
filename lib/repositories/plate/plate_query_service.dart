import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../enums/plate_type.dart';
import '../../models/plate_model.dart';
import '../../screens/type_pages/debugs/firestore_logger.dart';

class PlateQueryService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Future<PlateModel?> getPlate(String documentId) async {
    await FirestoreLogger().log('getPlate called: $documentId');
    try {
      final doc =
          await _firestore.collection('plates').doc(documentId).get().timeout(const Duration(seconds: 10)); // ⏱ 타임아웃

      if (!doc.exists) {
        await FirestoreLogger().log('getPlate not found: $documentId'); // 📄 미존재 로그
        return null;
      }

      await FirestoreLogger().log('getPlate success: $documentId');
      return PlateModel.fromDocument(doc);
    } on FirebaseException catch (e) {
      await FirestoreLogger().log('getPlate firebase error: ${e.code} ${e.message}');
      rethrow; // 기존과 동일하게 예외 전파
    } on TimeoutException {
      await FirestoreLogger().log('getPlate timeout: $documentId');
      rethrow; // 기존과 동일하게 예외 전파
    } catch (e) {
      await FirestoreLogger().log('getPlate error: $e');
      rethrow; // 기존과 동일하게 예외 전파
    }
  }

  Future<List<PlateModel>> fourDigitCommonQuery({
    required String plateFourDigit,
    required String area,
  }) async {
    await FirestoreLogger().log(
      'fourDigitCommonQuery called: plateFourDigit=$plateFourDigit, area=$area',
    );

    final query = _firestore
        .collection('plates')
        .where('plate_four_digit', isEqualTo: plateFourDigit)
        .where('area', isEqualTo: area);

    final result = await _queryPlates(query);

    await FirestoreLogger().log('fourDigitCommonQuery success: ${result.length} items loaded');
    return result;
  }

  Future<List<PlateModel>> fourDigitSignatureQuery({
    required String plateFourDigit,
    required String area,
  }) async {
    await FirestoreLogger().log(
      'fourDigitSignatureQuery called: plateFourDigit=$plateFourDigit, area=$area',
    );

    final query = _firestore
        .collection('plates')
        .where('plate_four_digit', isEqualTo: plateFourDigit)
        .where('area', isEqualTo: area)
        .where('type', isEqualTo: PlateType.parkingCompleted.firestoreValue);

    final result = await _queryPlates(query);

    await FirestoreLogger().log('fourDigitSignatureQuery success: ${result.length} items loaded');
    return result;
  }

  Future<List<PlateModel>> fourDigitForTabletQuery({
    required String plateFourDigit,
    required String area,
  }) async {
    await FirestoreLogger().log(
      'fourDigitForTabletQuery called: plateFourDigit=$plateFourDigit, area=$area',
    );

    final query = _firestore
        .collection('plates')
        .where('plate_four_digit', isEqualTo: plateFourDigit)
        .where('area', isEqualTo: area)
        .where('type', whereIn: [
      PlateType.parkingCompleted.firestoreValue,
      PlateType.departureCompleted.firestoreValue,
    ]);

    final result = await _queryPlates(query);

    await FirestoreLogger().log('fourDigitForTabletQuery success: ${result.length} items loaded');
    return result;
  }

  Future<List<PlateModel>> fourDigitDepartureCompletedQuery({
    required String plateFourDigit,
    required String area,
  }) async {
    await FirestoreLogger().log(
      'fourDigitDepartureCompletedQuery called: plateFourDigit=$plateFourDigit, area=$area',
    );

    final query = _firestore
        .collection('plates')
        .where('plate_four_digit', isEqualTo: plateFourDigit)
        .where('area', isEqualTo: area)
        .where('type', isEqualTo: PlateType.departureCompleted.firestoreValue);

    final result = await _queryPlates(query);

    await FirestoreLogger().log('fourDigitDepartureCompletedQuery success: ${result.length} items loaded');
    return result;
  }

  Future<bool> checkDuplicatePlate({
    required String plateNumber,
    required String area,
  }) async {
    await FirestoreLogger().log('checkDuplicatePlate called: plateNumber=$plateNumber, area=$area');

    try {
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
          .get()
          .timeout(const Duration(seconds: 10)); // ⏱ 타임아웃

      final isDuplicate = querySnapshot.docs.isNotEmpty;

      await FirestoreLogger().log('checkDuplicatePlate result: $isDuplicate');
      return isDuplicate;
    } on FirebaseException catch (e) {
      await FirestoreLogger().log('checkDuplicatePlate firebase error: ${e.code} ${e.message}');
      rethrow; // 기존 동작 유지: 예외 전파
    } on TimeoutException {
      await FirestoreLogger().log('checkDuplicatePlate timeout: plateNumber=$plateNumber, area=$area');
      rethrow; // 기존 동작 유지: 예외 전파
    } catch (e) {
      await FirestoreLogger().log('checkDuplicatePlate error: $e');
      rethrow; // 기존 동작 유지: 예외 전파
    }
  }

  Future<List<PlateModel>> _queryPlates(Query<Map<String, dynamic>> query) async {
    final querySnapshot = await query.get();
    return querySnapshot.docs.map((doc) => PlateModel.fromDocument(doc)).toList();
  }
}
