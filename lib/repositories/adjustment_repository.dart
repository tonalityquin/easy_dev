import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

/// 🔥 숫자 변환 유틸리티 함수 추가
int parseInt(dynamic value) {
  return int.tryParse(value.toString().replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
}

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
    return _firestore.collection('adjustment').where('area', isEqualTo: currentArea).snapshots().map((snapshot) {
      final dataList = snapshot.docs.map((doc) {
        final data = doc.data();
        return {
          'id': doc.id,
          'CountType': data['CountType']?.toString() ?? '',
          'area': data['area']?.toString() ?? '',
          'basicStandard': parseInt(data['basicStandard']),
          'basicAmount': parseInt(data['basicAmount']),
          'addStandard': parseInt(data['addStandard']),
          'addAmount': parseInt(data['addAmount']),
        };
      }).toList();

      debugPrint('🔥 Firestore에서 가져온 최신 데이터 ($currentArea): $dataList'); // 로그 출력
      return dataList;
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
      debugPrint("🔥 Firestore 에러 (addAdjustment): ${e.message}");
      throw Exception("Firestore 저장 실패: ${e.message}");
    } catch (e) {
      debugPrint("🔥 알 수 없는 에러 (addAdjustment): $e");
      throw Exception("예상치 못한 에러 발생");
    }
  }

  @override
  Future<void> deleteAdjustment(List<String> ids) async {
    try {
      await Future.wait(
        ids.map((id) => _firestore.collection('adjustment').doc(id).delete()),
      );
    } on FirebaseException catch (e) {
      debugPrint("🔥 Firestore 에러 (deleteAdjustment): ${e.message}");
      throw Exception("Firestore 삭제 실패: ${e.message}");
    } catch (e) {
      debugPrint("🔥 알 수 없는 에러 (deleteAdjustment): $e");
      throw Exception("예상치 못한 에러 발생");
    }
  }
}
