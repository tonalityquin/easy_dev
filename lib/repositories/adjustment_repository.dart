import 'package:cloud_firestore/cloud_firestore.dart';

/// 정산 데이터를 관리하는 추상 클래스
abstract class AdjustmentRepository {
  /// Firestore 위치 데이터를 스트림 형태로 반환
  Stream<List<Map<String, dynamic>>> getAdjustmentStream(String currentArea);

  /// Firestore에 새로운 위치 추가
  Future<void> addAdjustment(Map<String, dynamic> adjustmentData);

  /// Firestore에서 여러 위치 삭제
  Future<void> deleteAdjustment(List<String> ids);

  /// Firestore에서 특정 타입의 선택 상태 변경
  Future<void> toggleAdjustmentSelection(String id, bool isSelected);
}

/// Firestore 기반 위치 데이터 관리 구현 클래스
class FirestoreAdjustmentRepository implements AdjustmentRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  @override
  Stream<List<Map<String, dynamic>>> getAdjustmentStream(String currentArea) {
    return _firestore
        .collection('adjustment')
        .where('area', isEqualTo: currentArea) // Firestore 쿼리 단계에서 필터링
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) {
        final data = doc.data();
        return {
          'id': doc.id,
          'CountType': data['CountType']?.toString() ?? '',
          'area': data['area']?.toString() ?? '',
          'basicStandard': data['basicStandard']?.toString() ?? '',
          'basicAmount': data['basicAmount']?.toString() ?? '',
          'addStandard': data['addStandard']?.toString() ?? '',
          'addAmount': data['addAmount']?.toString() ?? '',
          'isSelected': (data['isSelected'] ?? false) == true,
        };
      }).toList();
    });
  }

  @override
  Future<void> addAdjustment(Map<String, dynamic> adjustmentData) async {
    try {
      final documentId = adjustmentData['CountType']; // CountType을 문서 ID로 사용
      await _firestore.collection('adjustment').doc(documentId).set(adjustmentData);
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

  @override
  Future<void> toggleAdjustmentSelection(String id, bool isSelected) async {
    try {
      await _firestore.collection('adjustment').doc(id).update({
        'isSelected': isSelected, // 선택 상태를 업데이트
      });
    } catch (e) {
      rethrow; // 예외 재발생
    }
  }
}
