import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'dart:developer' as dev;

import '../../models/plate_log_model.dart';
import '../../models/plate_model.dart';
import '../../screens/type_package/debugs/firestore_logger.dart';

class PlateWriteService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Future<void> addOrUpdatePlate(String documentId, PlateModel plate) async {
    try {
      await FirestoreLogger().log('addOrUpdatePlate called: $documentId');

      final docRef = _firestore.collection('plates').doc(documentId);
      final docSnapshot = await docRef.get().timeout(const Duration(seconds: 10));

      // 쓰기 데이터 생성 + 0원 잠금 규칙 보정
      var newData = plate.toMap();
      newData = _enforceZeroFeeLock(newData, existing: docSnapshot.data());

      final exists = docSnapshot.exists;
      if (exists) {
        final existingData = docSnapshot.data() ?? const <String, dynamic>{};

        // 비교시 logs 제외(로그 차이로 인한 불필요한 쓰기 방지)
        final compOld = Map<String, dynamic>.from(existingData)..remove(PlateFields.logs);
        final compNew = Map<String, dynamic>.from(newData)..remove(PlateFields.logs);

        if (_isSameData(compOld, compNew)) {
          await FirestoreLogger().log('addOrUpdatePlate skipped (no changes)');
          return;
        }

        // ✅ 기존 문서 업데이트 시 logs 덮어쓰기 방지
        newData.remove(PlateFields.logs);
      }
      // exists == false(신규 생성)일 때는 logs 포함 저장 허용

      await docRef.set(newData, SetOptions(merge: true)).timeout(const Duration(seconds: 10));
      await FirestoreLogger().log('addOrUpdatePlate success: $documentId');
    } on TimeoutException {
      await FirestoreLogger().log('addOrUpdatePlate timeout: $documentId');
      rethrow;
    } on FirebaseException catch (e) {
      await FirestoreLogger().log('addOrUpdatePlate firebase error: ${e.code} ${e.message}');
      rethrow;
    } catch (e, st) {
      await FirestoreLogger().log('addOrUpdatePlate error: $e\n$st');
      rethrow;
    }
  }

  Future<void> updatePlate(
    String documentId,
    Map<String, dynamic> updatedFields, {
    PlateLogModel? log,
  }) async {
    await FirestoreLogger().log('updatePlate called: $documentId, fields=$updatedFields');

    final docRef = _firestore.collection('plates').doc(documentId);

    // 기존 문서 + 변경 필드 기준으로 0/0 잠금 규칙 적용
    final current = (await docRef.get()).data();
    final fields = _enforceZeroFeeLock(Map<String, dynamic>.from(updatedFields), existing: current);

    if (log != null) {
      fields['logs'] = FieldValue.arrayUnion([log.toMap()]);
    }

    try {
      await docRef.update(fields);
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

  // -------------------------
  // 유틸: 0/0 잠금 규칙 강제
  // -------------------------
  Map<String, dynamic> _enforceZeroFeeLock(
    Map<String, dynamic> data, {
    Map<String, dynamic>? existing,
  }) {
    // data(이번 변경)에 없으면 existing(현재 문서)의 값을 사용해 '유효값'을 계산
    int effInt(String key) {
      if (data.containsKey(key)) return _toInt(data[key]);
      if (existing != null && existing.containsKey(key)) return _toInt(existing[key]);
      return 0;
    }

    final int basic = effInt(PlateFields.basicAmount);
    final int add = effInt(PlateFields.addAmount);

    final bool shouldLock = (basic == 0 && add == 0);

    if (shouldLock) {
      data[PlateFields.isLockedFee] = true;

      // 선택: 잠금 정보 기본값 세팅(없을 때만)
      data.putIfAbsent(
        PlateFields.lockedAtTimeInSeconds,
        () => DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000,
      );
      data.putIfAbsent(PlateFields.lockedFeeAmount, () => 0);
    }

    return data;
  }

  int _toInt(dynamic v) {
    if (v is int) return v;
    if (v is String) return int.tryParse(v) ?? 0;
    if (v is num) return v.toInt();
    return 0;
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
