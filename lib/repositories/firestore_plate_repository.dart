import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/plate_model.dart';
import 'plate_repository.dart';
import 'dart:developer' as dev;

/// PlateRepository를 구현(implements)하는 클래스
class FirestorePlateRepository implements PlateRepository {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance; // Firestore 인스턴스를 생성하여 _firestore 변수에 저장한다.

  /// Firestore 컬렉션(collectionName)을 실시간(Stream)으로 가져오는 메서드
  @override
  Stream<List<PlateModel>> getCollectionStream(String collectionName) {
    return _firestore.collection(collectionName).snapshots().map((snapshot) {
      // snapshots()를 호출하면 해당 컬렉션의 데이터가 변경될 때마다 자동으로 업데이트된다.
      return snapshot.docs
          .map((doc) => PlateModel.fromDocument(doc))
          .toList(); // .docs.map((doc) => PlateModel.fromDocument(doc)) Firestore 문서를 PlateModel로 변환한다.
    });
  }

  @override
  Future<void> addOrUpdateDocument(String collection, String documentId, Map<String, dynamic> data) async {
    final docRef = _firestore
        .collection(collection)
        .doc(documentId); // Firestore의 특정 컬렉션(collection)에서 주어진 문서 ID(documentId)를 참조하는 DocumentReference 객체를 생성한다.
    final docSnapshot = await docRef.get(); //  해당 문서(docRef)의 현재 데이터를 Firestore에서 가져와 DocumentSnapshot 객체로 저장한다.

    if (docSnapshot.exists) {
      final existingData = docSnapshot.data(); // 문서가 존재하면 해당 문서의 데이터를 Map<String, dynamic> 형식으로 가져온다.
      if (existingData != null && _isSameData(existingData, data)) {
        // 기존 데이터(existingData)가 null이 아니고, 새로 입력하려는 데이터(data)와 동일한지 _isSameData 함수를 통해 비교한다.
        dev.log("데이터 변경 없음: $documentId", name: "Firestore");
        return;
      }
    }

    await docRef.set(data, SetOptions(merge: true));
    dev.log("DB 문서 저장 완료: $documentId", name: "Firestore");
  }

  /// Firestore의 기존 데이터(oldData) 와 새로운 데이터(newData) 가 동일한지 비교하는 함수
  bool _isSameData(Map<String, dynamic> oldData, Map<String, dynamic> newData) {
    if (oldData.length != newData.length) return false;
    for (String key in oldData.keys) {
      if (!newData.containsKey(key) || oldData[key] != newData[key]) {
        return false;
      }
    }
    return true;
  }

  @override
  Future<void> deleteDocument(String collection, String documentId) async {
    final docRef = _firestore.collection(collection).doc(documentId);
    final docSnapshot = await docRef.get();

    if (docSnapshot.exists) {
      await docRef.delete();
    } else {
      dev.log("DB에 존재하지 않는 문서 (deleteDocument): $documentId", name: "Firestore");
    }
  }

  @override
  Future<PlateModel?> getDocument(String collection, String documentId) async {
    final doc = await _firestore.collection(collection).doc(documentId).get();
    if (!doc.exists) return null;
    return PlateModel.fromDocument(doc);
  }

  @override
  Future<void> deleteAllData() async {
    try {
      final collections = [
        'parking_requests',
        'parking_completed',
        'departure_requests',
        'departure_completed',
      ];

      await Future.wait(collections.map((collection) async {
        final snapshot = await _firestore.collection(collection).get();
        final batch = _firestore.batch();

        for (var doc in snapshot.docs) {
          batch.delete(doc.reference);
        }

        await batch.commit();
      }));
    } catch (e) {
      dev.log('❌ Firestore 전체 데이터 삭제 실패: $e');
      throw Exception("전체 데이터 삭제 실패: $e");
    }
  }

  @override
  Future<void> addRequestOrCompleted({
    required String collection,
    required String plateNumber,
    required String location,
    required String area,
    required String type,
    required String userName,
    String? adjustmentType,
    List<String>? memoList,
    int? basicStandard,
    int? basicAmount,
    int? addStandard,
    int? addAmount,
  }) async {
    final documentId = '${plateNumber}_$area';

    if (adjustmentType != null) {
      try {
        final adjustmentRef = _firestore.collection('adjustment');
        final adjustmentDoc = await adjustmentRef.doc('${adjustmentType}_$area').get();

        if (adjustmentDoc.exists) {
          final adjustmentData = adjustmentDoc.data()!;
          dev.log('🔥 Firestore에서 가져온 정산 데이터: $adjustmentData');

          basicStandard = adjustmentData['basicStandard'] as int? ?? 0;
          basicAmount = adjustmentData['basicAmount'] as int? ?? 0;
          addStandard = adjustmentData['addStandard'] as int? ?? 0;
          addAmount = adjustmentData['addAmount'] as int? ?? 0;
        } else {
          throw Exception('🚨 Firestore에서 데이터를 찾을 수 없음');
        }
      } catch (e) {
        dev.log("🔥 Firestore 에러 (addRequestOrCompleted): $e");
        throw Exception("Firestore 데이터 로드 실패: $e");
      }
    }

    final data = {
      'plate_number': plateNumber,
      'type': type,
      'entry_time': DateTime.now(),
      'location': location.isNotEmpty ? location : '미지정',
      'area': area,
      'user_name': userName,
      'adjustment_type': adjustmentType,
      'memo_list': memoList ?? [],
      'is_selected': false,
      'who_selected': null,
      'basic_standard': basicStandard ?? 0,
      'basic-amount': basicAmount ?? 0,
      'add_standard': addStandard ?? 0,
      'add_amount': addAmount ?? 0,
    };

    dev.log('🔥 Firestore 저장 데이터: $data');

    await _firestore.collection(collection).doc(documentId).set(data);
  }

  @override

  /// 특정 번호판의 선택 상태를 업데이트하는 메서드
  Future<void> togglePlateSelection(String collection, String id, bool isSelected, {String? whoSelected}) async {
    final docRef = _firestore.collection(collection).doc(id);
    try {
      await _firestore.runTransaction((transaction) async {
        final docSnapshot = await transaction.get(docRef);
        if (!docSnapshot.exists) {
          dev.log("번호판을 찾을 수 없음: $id", name: "Firestore");
          return;
        }

        transaction.update(docRef, {
          'is_selected': isSelected,
          'who_selected': isSelected ? whoSelected : null,
        });
      });
    } catch (e) {
      dev.log("DB 에러 (togglePlateSelection): $e", name: "Firestore");
      throw Exception("DB 업데이트 실패: $e");
    }
  }

  @override

  /// 특정 지역의 사용 가능한 구역 목록을 가져오는 메서드
  Future<List<String>> getAvailableLocations(String area) async {
    try {
      final querySnapshot = await _firestore
          .collection('locations') // Firestore의 'locations' 컬렉션
          .where('area', isEqualTo: area) // area 필터 적용
          .get();

      return querySnapshot.docs.map((doc) => doc['locationName'] as String).toList();
    } catch (e) {
      dev.log("🔥 Firestore 에러 (getAvailableLocations): $e", name: "Firestore");
      throw Exception('Firestore에서 사용 가능한 위치 목록을 가져오지 못했습니다: $e');
    }
  }
}
