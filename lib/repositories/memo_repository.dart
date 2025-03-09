import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:developer' as dev;

class FirestoreFields {
  static const String id = 'id';
  static const String name = 'name';
  static const String isActive = 'isActive';
  static const String area = 'area';
}

class MemoRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final String collectionName = 'statusToggles';

  /// Firestore 컬렉션 참조 반환 (중복 코드 제거)
  CollectionReference<Map<String, dynamic>> _getCollectionRef() {
    return _firestore.collection(collectionName);
  }

  /// Firestore 상태 데이터 실시간 스트림 반환 (지역 필터 적용)
  Stream<List<Map<String, dynamic>>> getStatusStream(String area) {
    return _getCollectionRef().where(FirestoreFields.area, isEqualTo: area).snapshots().map((snapshot) {
      return snapshot.docs.map((doc) {
        final data = doc.data();
        return {
          FirestoreFields.id: doc.id, // ✅ 문서 ID도 FirestoreFields 사용
          FirestoreFields.name: data[FirestoreFields.name] ?? '',
          FirestoreFields.isActive: data[FirestoreFields.isActive] ?? false,
          FirestoreFields.area: data[FirestoreFields.area] ?? '',
        };
      }).toList();
    });
  }

  /// Firestore에 상태 항목 추가
  Future<void> addToggleItem(Map<String, dynamic> item) async {
    try {
      final docRef = _getCollectionRef().doc(); // ✅ 자동 생성 ID 사용
      item[FirestoreFields.id] = docRef.id; // ✅ 생성된 ID를 item에 추가

      await docRef.set(item);
      dev.log("🔥 Firestore 저장 완료 (ID: ${docRef.id})", name: "Firestore");
    } catch (e) {
      dev.log("🔥 Firestore 저장 실패 (addToggleItem): $e", name: "Firestore");
      throw Exception("Firestore 저장 실패: ${e.toString()}");
    }
  }

  /// Firestore에서 상태 변경
  Future<void> updateToggleStatus(String id, bool isActive) async {
    try {
      final docRef = _getCollectionRef().doc(id);
      final docSnapshot = await docRef.get();

      if (!docSnapshot.exists) {
        dev.log("🔥 Firestore 업데이트 실패: 문서가 존재하지 않음 (ID: $id)", name: "Firestore");
        throw FirebaseException(
          plugin: "Firestore",
          message: "Firestore 업데이트 실패: 문서가 존재하지 않습니다.",
        );
      }

      await docRef.update({FirestoreFields.isActive: isActive});
    } on FirebaseException catch (e) {
      dev.log("🔥 Firestore 업데이트 실패 (updateToggleStatus): ${e.message}", name: "Firestore");
      rethrow;
    } catch (e) {
      dev.log("🔥 알 수 없는 에러 (updateToggleStatus): $e", name: "Firestore");
      throw FirebaseException(plugin: "Firestore", message: e.toString());
    }
  }

  /// Firestore에서 삭제
  Future<void> deleteToggleItem(String id) async {
    try {
      final docRef = _getCollectionRef().doc(id);
      final docSnapshot = await docRef.get();

      if (!docSnapshot.exists) {
        dev.log("🔥 Firestore 삭제 실패: 문서가 존재하지 않음 (ID: $id)", name: "Firestore");
        throw Exception("Firestore 삭제 실패: 문서가 존재하지 않습니다.");
      }

      await docRef.delete();
    } catch (e) {
      dev.log("🔥 Firestore 삭제 실패 (deleteToggleItem): $e", name: "Firestore");
      throw Exception("Firestore 삭제 실패: ${e.toString()}");
    }
  }
}
