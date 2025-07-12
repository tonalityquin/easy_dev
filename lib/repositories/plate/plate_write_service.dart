import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'dart:developer' as dev;

import '../../models/plate_model.dart';
import '../../screens/type_pages/debugs/firestore_logger.dart';

class PlateWriteService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Future<void> addOrUpdatePlate(String documentId, PlateModel plate) async {
    await FirestoreLogger().log('addOrUpdatePlate called: $documentId, data=${plate.toMap()}');

    final docRef = _firestore.collection('plates').doc(documentId);
    final docSnapshot = await docRef.get();
    final data = plate.toMap();

    if (docSnapshot.exists) {
      final existingData = docSnapshot.data();
      if (existingData != null && _isSameData(existingData, data)) {
        dev.log("데이터 변경 없음: $documentId", name: "Firestore");
        await FirestoreLogger().log('addOrUpdatePlate skipped (no changes)');
        return;
      }
    }

    await docRef.set(data, SetOptions(merge: true));
    dev.log("DB 문서 저장 완료: $documentId", name: "Firestore");
    await FirestoreLogger().log('addOrUpdatePlate success: $documentId');
  }

  Future<void> updatePlate(String documentId, Map<String, dynamic> updatedFields) async {
    await FirestoreLogger().log('updatePlate called: $documentId, fields=$updatedFields');
    final docRef = _firestore.collection('plates').doc(documentId);

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
    final docSnapshot = await docRef.get();

    if (docSnapshot.exists) {
      await docRef.delete();
      await FirestoreLogger().log('deletePlate success: $documentId');
    } else {
      debugPrint("DB에 존재하지 않는 문서 (deletePlate): $documentId");
      await FirestoreLogger().log('deletePlate skipped: document not found');
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

  /// 내부 사용: 문서 데이터 비교
  bool _isSameData(Map<String, dynamic> oldData, Map<String, dynamic> newData) {
    if (oldData.length != newData.length) return false;
    for (String key in oldData.keys) {
      if (!newData.containsKey(key) || oldData[key] != newData[key]) {
        return false;
      }
    }
    return true;
  }
}
