import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:developer' as dev;

int parseInt(dynamic value) {
  return int.tryParse(value.toString().replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
}

class FirestoreFields {
  static const String id = 'id';
  static const String countType = 'CountType';
  static const String area = 'area';
  static const String basicStandard = 'basicStandard';
  static const String basicAmount = 'basicAmount';
  static const String addStandard = 'addStandard';
  static const String addAmount = 'addAmount';
}

abstract class AdjustmentRepository {
  Stream<List<Map<String, dynamic>>> getAdjustmentStream(String currentArea);

  Future<void> addAdjustment(Map<String, dynamic> adjustmentData);

  Future<void> deleteAdjustment(List<String> ids);
}

class FirestoreAdjustmentRepository implements AdjustmentRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  @override
  Stream<List<Map<String, dynamic>>> getAdjustmentStream(String currentArea) {
    return _firestore
        .collection('adjustment')
        .where(FirestoreFields.area, isEqualTo: currentArea)
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) {
        final data = doc.data();
        return {
          FirestoreFields.id: doc.id,
          FirestoreFields.countType: data[FirestoreFields.countType]?.toString() ?? '',
          FirestoreFields.area: data[FirestoreFields.area]?.toString() ?? '',
          FirestoreFields.basicStandard: parseInt(data[FirestoreFields.basicStandard]),
          FirestoreFields.basicAmount: parseInt(data[FirestoreFields.basicAmount]),
          FirestoreFields.addStandard: parseInt(data[FirestoreFields.addStandard]),
          FirestoreFields.addAmount: parseInt(data[FirestoreFields.addAmount]),
        };
      }).toList();
    });
  }

  @override
  Future<void> addAdjustment(Map<String, dynamic> adjustmentData) async {
    try {
      String documentId = '${adjustmentData['CountType']}_${adjustmentData['area']}';
      await _firestore.collection('adjustment').doc(documentId).set({
        'CountType': adjustmentData['CountType'],
        'area': adjustmentData['area'],
        'basicStandard': parseInt(adjustmentData['basicStandard']),
        'basicAmount': parseInt(adjustmentData['basicAmount']),
        'addStandard': parseInt(adjustmentData['addStandard']),
        'addAmount': parseInt(adjustmentData['addAmount']),
      });
    } on FirebaseException catch (e) {
      dev.log("DB 에러 (addAdjustment): ${e.message}");
      throw Exception("DB 저장 실패: ${e.message}");
    } catch (e) {
      dev.log("DB 에러 (addAdjustment): $e");
      throw Exception("예상치 못한 에러 발생");
    }
  }

  @override
  Future<void> deleteAdjustment(List<String> ids) async {
    try {
      await Future.wait(
        ids.map((id) async {
          final docRef = _firestore.collection('adjustment').doc(id);
          final docSnapshot = await docRef.get();
          if (docSnapshot.exists) {
            await docRef.delete();
          } else {
            dev.log("삭제할 데이터가 DB에 없음: $id");
          }
        }),
      );
    } on FirebaseException catch (e) {
      dev.log("DB 에러 (deleteAdjustment): ${e.message}");
      throw Exception("Firestore 삭제 실패: ${e.message}");
    } catch (e) {
      dev.log("DB 에러 (deleteAdjustment): $e");
      throw Exception("예상치 못한 에러 발생");
    }
  }
}
