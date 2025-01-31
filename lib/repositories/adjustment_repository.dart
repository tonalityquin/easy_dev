import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

/// 정산 데이터를 관리하는 추상 클래스
abstract class AdjustmentRepository {
  /// Firestore 위치 데이터를 스트림 형태로 반환
  Stream<List<Map<String, dynamic>>> getAdjustmentStream(String currentArea);

  /// Firestore에 새로운 정산 기준 추가
  Future<void> addAdjustment(Map<String, dynamic> adjustmentData);

  /// Firestore에서 여러 정산 기준 삭제
  Future<void> deleteAdjustment(List<String> ids);
}

/// Firestore 기반 정산 데이터 관리 구현 클래스
class FirestoreAdjustmentRepository implements AdjustmentRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  @override
  Stream<List<Map<String, dynamic>>> getAdjustmentStream(String currentArea) {
    return _firestore
        .collection('adjustment')
        .where('area', isEqualTo: currentArea)
        .snapshots()
        .map((snapshot) {
      final dataList = snapshot.docs.map((doc) {
        final data = doc.data();
        return {
          'id': doc.id,
          'CountType': data['CountType']?.toString() ?? '',
          'area': data['area']?.toString() ?? '',
          'basicStandard': int.tryParse(data['basicStandard'].toString().replaceAll(RegExp(r'[^0-9]'), '')) ?? 0,
          'basicAmount': int.tryParse(data['basicAmount'].toString()) ?? 0,
          'addStandard': int.tryParse(data['addStandard'].toString().replaceAll(RegExp(r'[^0-9]'), '')) ?? 0,
          'addAmount': int.tryParse(data['addAmount'].toString()) ?? 0,
        };
      }).toList();

      debugPrint('🔥 Firestore에서 받아온 데이터 ($currentArea): $dataList');
      return dataList;
    });
  }



  @override
  Future<void> addAdjustment(Map<String, dynamic> adjustmentData) async {
    try {
      String countType = adjustmentData['CountType'];
      String area = adjustmentData['area'];
      String documentId = '${countType}_$area'; // 🔥 문서 ID를 countType_지역명으로 설정

      await _firestore.collection('adjustment').doc(documentId).set({
        'CountType': countType,
        'area': area,
        'basicStandard': int.tryParse(adjustmentData['basicStandard'].toString().replaceAll(RegExp(r'[^0-9]'), '')) ?? 0,
        'basicAmount': int.tryParse(adjustmentData['basicAmount'].toString()) ?? 0,
        'addStandard': int.tryParse(adjustmentData['addStandard'].toString().replaceAll(RegExp(r'[^0-9]'), '')) ?? 0,
        'addAmount': int.tryParse(adjustmentData['addAmount'].toString()) ?? 0,
      });
    } catch (e) {
      rethrow; // 예외 재발생
    }
  }


  @override
  Future<void> deleteAdjustment(List<String> ids) async {
    try {
      for (var id in ids) {
        await _firestore.collection('adjustment').doc(id).delete();
      }
    } catch (e) {
      rethrow; // 예외 재발생
    }
  }
}
