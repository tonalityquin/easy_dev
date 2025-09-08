import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../enums/plate_type.dart';
import '../../models/plate_model.dart';

class PlateQueryService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Future<PlateModel?> getPlate(String documentId) async {
    final doc = await _firestore.collection('plates').doc(documentId).get().timeout(const Duration(seconds: 10));

    if (!doc.exists) {
      return null;
    }

    return PlateModel.fromDocument(doc);
  }

  Future<List<PlateModel>> fourDigitCommonQuery({
    required String plateFourDigit,
    required String area,
  }) async {
    final query = _firestore
        .collection('plates')
        .where('plate_four_digit', isEqualTo: plateFourDigit)
        .where('area', isEqualTo: area);

    final result = await _queryPlates(query);

    return result;
  }

  Future<List<PlateModel>> fourDigitSignatureQuery({
    required String plateFourDigit,
    required String area,
  }) async {
    final query = _firestore
        .collection('plates')
        .where('plate_four_digit', isEqualTo: plateFourDigit)
        .where('area', isEqualTo: area)
        .where('type', isEqualTo: PlateType.parkingCompleted.firestoreValue);

    final result = await _queryPlates(query);

    return result;
  }

  Future<List<PlateModel>> fourDigitForTabletQuery({
    required String plateFourDigit,
    required String area,
  }) async {
    final query = _firestore
        .collection('plates')
        .where('plate_four_digit', isEqualTo: plateFourDigit)
        .where('area', isEqualTo: area)
        .where('type', whereIn: [
      PlateType.parkingCompleted.firestoreValue,
      PlateType.departureCompleted.firestoreValue,
    ]);

    final result = await _queryPlates(query);

    return result;
  }

  Future<List<PlateModel>> fourDigitDepartureCompletedQuery({
    required String plateFourDigit,
    required String area,
  }) async {
    final query = _firestore
        .collection('plates')
        .where('plate_four_digit', isEqualTo: plateFourDigit)
        .where('area', isEqualTo: area)
        .where('type', isEqualTo: PlateType.departureCompleted.firestoreValue);

    final result = await _queryPlates(query);

    return result;
  }

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
        .get()
        .timeout(const Duration(seconds: 10)); // ⏱ 타임아웃

    return querySnapshot.docs.isNotEmpty;
  }

  Future<List<PlateModel>> _queryPlates(Query<Map<String, dynamic>> query) async {
    final querySnapshot = await query.get();
    return querySnapshot.docs.map((doc) => PlateModel.fromDocument(doc)).toList();
  }
}
