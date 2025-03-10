import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:developer' as dev;

/// Firestore 필드명을 관리하는 클래스 (중복 제거 및 통일)
class FirestoreFields {
  static const String id = 'id';
  static const String name = 'name';
  static const String isActive = 'isActive';
  static const String area = 'area';
}

class MemoRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static const String _collectionName = 'memoToggles';

  /// Firestore 컬렉션 참조 반환
  CollectionReference<Map<String, dynamic>> _getCollectionRef() {
    return _firestore.collection(_collectionName);
  }

  /// Firestore 상태 데이터 실시간 스트림 반환 (지역 필터 적용)
  Stream<List<Map<String, dynamic>>> getMemoStream(String area) {
    return _getCollectionRef().where(FirestoreFields.area, isEqualTo: area).snapshots().map((snapshot) {
      return snapshot.docs.map((doc) {
        final data = doc.data();
        return {
          FirestoreFields.id: doc.id,
          FirestoreFields.name: data[FirestoreFields.name] ?? '',
          FirestoreFields.isActive: data[FirestoreFields.isActive] ?? false,
          FirestoreFields.area: data[FirestoreFields.area] ?? '',
        };
      }).toList();
    });
  }

  /// Firestore에 상태 항목 추가
  Future<void> addMemo(Map<String, dynamic> item) async {
    try {
      final docRef = _getCollectionRef().doc();
      final newItem = {
        ...item,
        FirestoreFields.id: docRef.id, // ✅ 자동 생성된 ID 추가
      };

      await docRef.set(newItem);
      dev.log("Firestore 저장 완료 (ID: ${docRef.id})", name: "Firestore");
    } catch (e) {
      dev.log("Firestore 저장 실패: $e", name: "Firestore");
      throw Exception("Firestore 저장 실패: ${e.toString()}");
    }
  }

  /// Firestore에서 상태 변경
  // transaction = 여러 클라이언트가 같은 문서를 동시에 수정할 경우 발생하는 충돌 방지
  Future<void> updateMemo(String id, bool isActive) async {
    final docRef = _getCollectionRef().doc(id);

    try {
      await _firestore.runTransaction((transaction) async {
        final docSnapshot = await transaction.get(docRef);
        if (!docSnapshot.exists) {
          dev.log("Firestore 업데이트 실패: 문서가 존재하지 않음 (ID: $id)", name: "Firestore");
          throw FirebaseException(plugin: "Firestore", message: "문서가 존재하지 않습니다.");
        }

        transaction.update(docRef, {FirestoreFields.isActive: isActive});
      });

      dev.log("Firestore 업데이트 완료 (ID: $id, isActive: $isActive)", name: "Firestore");
    } catch (e) {
      dev.log("Firestore 업데이트 실패: $e", name: "Firestore");
      throw FirebaseException(plugin: "Firestore", message: "업데이트 실패: ${e.toString()}");
    }
  }

  /// Firestore에서 삭제
  Future<void> removeMemo(String id) async {
    final docRef = _getCollectionRef().doc(id);

    try {
      await _firestore.runTransaction((transaction) async {
        final docSnapshot = await transaction.get(docRef);
        if (!docSnapshot.exists) {
          dev.log("Firestore 삭제 실패: 문서가 존재하지 않음 (ID: $id)", name: "Firestore");
          throw Exception("문서가 존재하지 않습니다.");
        }

        transaction.delete(docRef);
      });

      dev.log("Firestore 삭제 완료 (ID: $id)", name: "Firestore");
    } catch (e) {
      dev.log("Firestore 삭제 실패: $e", name: "Firestore");
      throw Exception("Firestore 삭제 실패: ${e.toString()}");
    }
  }
}
