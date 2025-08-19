import 'package:cloud_firestore/cloud_firestore.dart';
import '../../enums/plate_type.dart';
import '../../models/plate_model.dart';
import '../../screens/type_pages/debugs/firestore_logger.dart';

class PlateQueryService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Future<PlateModel?> getPlate(String documentId) async {
    await FirestoreLogger().log('getPlate called: $documentId');
    final doc = await _firestore.collection('plates').doc(documentId).get();
    if (!doc.exists) return null;
    await FirestoreLogger().log('getPlate success: $documentId');
    return PlateModel.fromDocument(doc);
  }

  Future<List<PlateModel>> getPlatesByLocation({
    required PlateType type,
    required String area,
    required String location,
  }) async {
    await FirestoreLogger().log(
      'getPlatesByLocation called: type=${type.name}, area=$area, location=$location',
    );

    final query = _firestore
        .collection('plates')
        .where('type', isEqualTo: type.firestoreValue)
        .where('area', isEqualTo: area)
        .where('location', isEqualTo: location);

    final result = await _queryPlates(query);

    await FirestoreLogger().log('getPlatesByLocation success: ${result.length} items loaded');
    return result;
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

  Future<List<PlateModel>> fourDigitDepartureCompletedQuery({
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
        .where('type', isEqualTo: PlateType.departureCompleted.firestoreValue);

    final result = await _queryPlates(query);

    await FirestoreLogger().log('fourDigitSignatureQuery success: ${result.length} items loaded');
    return result;
  }

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

  Future<List<PlateModel>> _queryPlates(Query<Map<String, dynamic>> query) async {
    final querySnapshot = await query.get();
    return querySnapshot.docs.map((doc) => PlateModel.fromDocument(doc)).toList();
  }
}
