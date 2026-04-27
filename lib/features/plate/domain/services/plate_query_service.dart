import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import '../enums/plate_type.dart';
import '../models/plate_model.dart';

class PlateQueryService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Future<PlateModel?> getPlate(String documentId) async {
    try {
      final doc = await _firestore
          .collection('plates')
          .doc(documentId)
          .get()
          .timeout(const Duration(seconds: 10));

      if (!doc.exists) {
        return null;
      }
      return PlateModel.fromDocument(doc);
    } catch (_) {
      rethrow;
    }
  }

  Future<List<PlateModel>> fourDigitCommonQuery({
    required String plateFourDigit,
    required String area,
  }) async {
    final query = _firestore
        .collection('plates')
        .where('plate_four_digit', isEqualTo: plateFourDigit)
        .where('area', isEqualTo: area);

    return _queryPlates(
      query,
      op: 'plates.query.fourDigit.common',
      filters: {'plate_four_digit': plateFourDigit, 'area': area},
      tags: const ['plates', 'query', 'fourDigit', 'common'],
    );
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

    return _queryPlates(
      query,
      op: 'plates.query.fourDigit.signature',
      filters: {
        'plate_four_digit': plateFourDigit,
        'area': area,
        'type': PlateType.parkingCompleted.firestoreValue,
      },
      tags: const ['plates', 'query', 'fourDigit', 'signature'],
    );
  }

  Future<List<PlateModel>> fourDigitForTabletQuery({
    required String plateFourDigit,
    required String area,
  }) async {
    final types = [
      PlateType.parkingCompleted.firestoreValue,
      PlateType.departureCompleted.firestoreValue,
    ];

    final query = _firestore
        .collection('plates')
        .where('plate_four_digit', isEqualTo: plateFourDigit)
        .where('area', isEqualTo: area)
        .where('type', whereIn: types);

    return _queryPlates(
      query,
      op: 'plates.query.fourDigit.tablet',
      filters: {
        'plate_four_digit': plateFourDigit,
        'area': area,
        'type_in': types
      },
      tags: const ['plates', 'query', 'fourDigit', 'tablet'],
    );
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

    return _queryPlates(
      query,
      op: 'plates.query.fourDigit.departureCompleted',
      filters: {
        'plate_four_digit': plateFourDigit,
        'area': area,
        'type': PlateType.departureCompleted.firestoreValue,
      },
      tags: const ['plates', 'query', 'fourDigit', 'departureCompleted'],
    );
  }

  Future<List<PlateModel>> _queryPlates(
    Query<Map<String, dynamic>> query, {
    required String op,
    required Map<String, dynamic> filters,
    List<String> tags = const ['plates', 'query'],
  }) async {
    try {
      final querySnapshot = await query.get();
      final results = querySnapshot.docs
          .map((doc) => PlateModel.fromDocument(doc))
          .toList();

      return results;
    } catch (_) {
      rethrow;
    }
  }
}
