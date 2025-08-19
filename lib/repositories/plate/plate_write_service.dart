import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'dart:developer' as dev;

import '../../models/plate_log_model.dart';
import '../../models/plate_model.dart';
import '../../screens/type_pages/debugs/firestore_logger.dart';

class PlateWriteService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Future<void> addOrUpdatePlate(String documentId, PlateModel plate) async {
    await FirestoreLogger().log('addOrUpdatePlate called: $documentId, data=${plate.toMap()}');

    final docRef = _firestore.collection('plates').doc(documentId);
    final docSnapshot = await docRef.get();
    final newData = plate.toMap();

    if (docSnapshot.exists) {
      final existingData = docSnapshot.data();
      if (existingData != null && _isSameData(existingData, newData)) {
        dev.log("📦 데이터 변경 없음 → 쓰기 생략: $documentId", name: "Firestore");
        await FirestoreLogger().log('addOrUpdatePlate skipped (no changes)');
        return;
      }
    }

    await docRef.set(newData, SetOptions(merge: true));
    dev.log("✅ 문서 저장 완료: $documentId", name: "Firestore");
    await FirestoreLogger().log('addOrUpdatePlate success: $documentId');
  }

  Future<void> updatePlate(
    String documentId,
    Map<String, dynamic> updatedFields, {
    PlateLogModel? log,
  }) async {
    await FirestoreLogger().log('updatePlate called: $documentId, fields=$updatedFields');

    final docRef = _firestore.collection('plates').doc(documentId);

    if (log != null) {
      updatedFields['logs'] = FieldValue.arrayUnion([log.toMap()]);
    }

    try {
      await docRef.update(updatedFields);
      dev.log("✅ 문서 업데이트 완료: $documentId", name: "Firestore");
      await FirestoreLogger().log('updatePlate success: $documentId');
    } catch (e) {
      dev.log("🔥 문서 업데이트 실패: $e", name: "Firestore");
      await FirestoreLogger().log('updatePlate error: $e');
      rethrow;
    }
  }

  Future<void> deletePlate(String documentId) async {
    await FirestoreLogger().log('deletePlate called: $documentId');
    final docRef = _firestore.collection('plates').doc(documentId);

    try {
      await docRef.delete();
      dev.log("🗑️ 문서 삭제 완료: $documentId", name: "Firestore");
      await FirestoreLogger().log('deletePlate success: $documentId');
    } on FirebaseException catch (e) {
      if (e.code == 'not-found') {
        debugPrint("⚠️ 삭제 시 문서 없음 (무시): $documentId");
        await FirestoreLogger().log('deletePlate skipped (not found): $documentId');
      } else {
        dev.log("🔥 문서 삭제 실패: $e", name: "Firestore");
        await FirestoreLogger().log('deletePlate error: $e');
        rethrow;
      }
    }
  }

  Future<void> recordWhoPlateClick(
    String id,
    bool isSelected, {
    String? selectedBy,
  }) async {
    await FirestoreLogger().log('recordWhoPlateClick called: $id, isSelected=$isSelected, selectedBy=$selectedBy');
    final docRef = _firestore.collection('plates').doc(id);

    try {
      await docRef.update({
        'isSelected': isSelected,
        'selectedBy': isSelected ? selectedBy : null,
      });
      await FirestoreLogger().log('recordWhoPlateClick success: $id');
    } on FirebaseException catch (e) {
      if (e.code == 'not-found') {
        debugPrint("번호판 문서를 찾을 수 없습니다: $id");
        await FirestoreLogger().log('recordWhoPlateClick skipped (not found): $id');
        return;
      }
      debugPrint("DB 에러 (recordWhoPlateClick): $e");
      await FirestoreLogger().log('recordWhoPlateClick error: $e');
      throw Exception("DB 업데이트 실패: $e");
    } catch (e) {
      debugPrint("DB 에러 (recordWhoPlateClick): $e");
      await FirestoreLogger().log('recordWhoPlateClick error: $e');
      throw Exception("DB 업데이트 실패: $e");
    }
  }

  bool _isSameData(Map<String, dynamic> oldData, Map<String, dynamic> newData) {
    if (oldData.length != newData.length) return false;

    for (String key in oldData.keys) {
      final oldValue = oldData[key];
      final newValue = newData[key];

      if (!_deepEquals(oldValue, newValue)) {
        return false;
      }
    }
    return true;
  }

  bool _deepEquals(dynamic a, dynamic b) {
    if (a == null || b == null) return a == b;

    if (a is List && b is List) {
      if (a.length != b.length) return false;
      for (int i = 0; i < a.length; i++) {
        if (!_deepEquals(a[i], b[i])) return false;
      }
      return true;
    }

    if (a is Timestamp && b is Timestamp) {
      return a.toDate() == b.toDate();
    }

    return a == b;
  }
}
