// lib/repositories/plate_repo_services/plate_write_service.dart
//
// (요청사항) 기존 주석처리 코드 유지, updatedAt 강제 세팅 반영(생성/업데이트/전환/선택 경로)

import 'dart:async';
import 'dart:developer' as dev;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../../models/plate_log_model.dart';
import '../../models/plate_model.dart';
// import '../../utils/usage_reporter.dart';

class PlateWriteService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Future<void> addOrUpdatePlate(String documentId, PlateModel plate) async {
    final docRef = _firestore.collection('plates').doc(documentId);

    try {
      final docSnapshot = await docRef.get().timeout(const Duration(seconds: 10));

      /*final preArea = (docSnapshot.data()?['area'] ?? plate.area ?? 'unknown') as String;
      await UsageReporter.instance.report(
        area: preArea,
        action: 'read',
        n: 1,
        source: 'PlateWriteService.addOrUpdatePlate.prefetch',
      );*/

      var newData = plate.toMap();
      newData = _enforceZeroFeeLock(newData, existing: docSnapshot.data());

      final exists = docSnapshot.exists;
      final existingData = docSnapshot.data() ?? const <String, dynamic>{};

      // 비교 시 로그 필드는 제외
      final compOld = Map<String, dynamic>.from(existingData)..remove(PlateFields.logs);
      final compNew = Map<String, dynamic>.from(newData)..remove(PlateFields.logs);

      // 변화 없음이면 조용히 종료(불필요 write 방지)
      if (exists && _isSameData(compOld, compNew)) {
        return;
      }

      // 기존 문서에 쓰는 경우 Firestore array 병합 충돌 방지 위해 logs 제거
      if (exists) {
        newData.remove(PlateFields.logs);
      }

      // ✅ 생성이든 업데이트든 실제 write를 수행하는 경우 updatedAt은 반드시 서버 시각으로 갱신
      newData['updatedAt'] = FieldValue.serverTimestamp();

      await docRef.set(newData, SetOptions(merge: true)).timeout(const Duration(seconds: 10));

      /*final area = (newData[PlateFields.area] ?? docSnapshot.data()?['area'] ?? plate.area ?? 'unknown') as String;

      await UsageReporter.instance.report(
        area: area,
        action: 'write',
        n: 1,
        source: 'PlateWriteService.addOrUpdatePlate.write',
      );*/
    } on TimeoutException {
      // ✅ DebugDatabaseLogger 로직 제거
      rethrow;
    } on FirebaseException {
      // ✅ DebugDatabaseLogger 로직 제거
      rethrow;
    } catch (_) {
      // ✅ DebugDatabaseLogger 로직 제거
      rethrow;
    }
  }

  Future<void> updatePlate(
      String documentId,
      Map<String, dynamic> updatedFields, {
        PlateLogModel? log,
      }) async {
    final docRef = _firestore.collection('plates').doc(documentId);

    Map<String, dynamic>? current;
    try {
      current = (await docRef.get().timeout(const Duration(seconds: 10))).data();

      /*final areaPref = (current?['area'] as String?) ?? 'unknown';
      await UsageReporter.instance.report(
        area: areaPref,
        action: 'read',
        n: 1,
        source: 'PlateWriteService.updatePlate.prefetch',
      );*/
    } on FirebaseException {
      // ✅ DebugDatabaseLogger 로직 제거
      rethrow;
    } on TimeoutException {
      // ✅ DebugDatabaseLogger 로직 제거
      rethrow;
    }

    final fields = _enforceZeroFeeLock(
      Map<String, dynamic>.from(updatedFields),
      existing: current,
    );

    if (log != null) {
      fields['logs'] = FieldValue.arrayUnion([log.toMap()]);
    }

    // ✅ 어떤 업데이트든 write가 발생하면 updatedAt을 서버 시각으로 갱신
    fields['updatedAt'] = FieldValue.serverTimestamp();

    try {
      await docRef.update(fields);
      debugPrint("✅ 문서 업데이트 완료: $documentId");

      /*final area = (fields[PlateFields.area] ?? current?['area'] ?? 'unknown') as String;
      await UsageReporter.instance.report(
        area: area,
        action: 'write',
        n: 1,
        source: 'PlateWriteService.updatePlate.write',
      );*/
    } on FirebaseException catch (e) {
      debugPrint("🔥 문서 업데이트 실패: $e");
      // ✅ DebugDatabaseLogger 로직 제거
      rethrow;
    } catch (e) {
      debugPrint("🔥 문서 업데이트 실패: $e");
      // ✅ DebugDatabaseLogger 로직 제거
      rethrow;
    }
  }

  Future<void> deletePlate(String documentId) async {
    final docRef = _firestore.collection('plates').doc(documentId);

    try {
      /*final snap = await docRef.get();
      final area = (snap.data()?['area'] as String?) ?? 'unknown';
      await UsageReporter.instance.report(
        area: area,
        action: 'read',
        n: 1,
        source: 'PlateWriteService.deletePlate.prefetch',
      );*/

      await docRef.delete();
      dev.log("🗑️ 문서 삭제 완료: $documentId", name: "Firestore");

      /*await UsageReporter.instance.report(
        area: area,
        action: 'delete',
        n: 1,
        source: 'PlateWriteService.deletePlate.delete',
      );*/
    } on FirebaseException catch (e) {
      if (e.code == 'not-found') {
        debugPrint("⚠️ 삭제 시 문서 없음 (무시): $documentId");
        return;
      }
      dev.log("🔥 문서 삭제 실패: $e", name: "Firestore");
      // ✅ DebugDatabaseLogger 로직 제거
      rethrow;
    } catch (_) {
      // ✅ DebugDatabaseLogger 로직 제거
      rethrow;
    }
  }

  /// ✅ 전환(입차/출차 완료 등) 트랜잭션:
  /// - 현재 상태(fromType)와 선점자(forceOverride=false면 검사)를 검증
  /// - 상태/선택/로그를 **원샷** 업데이트(WRITE 1)
  Future<void> transitionPlateType({
    required String plateId,
    required String actor, // 전환 수행자(userName)
    required String fromType, // 예: 'parking_requests'
    required String toType, // 예: 'parking_completed'
    Map<String, dynamic>? extraFields, // location/area 등 (nullable로 변경)
    bool forceOverride = true, // false면 타인 선택 시 전환 거부
  }) async {
    final docRef = _firestore.collection('plates').doc(plateId);

    try {
      await _firestore.runTransaction((tx) async {
        final snap = await tx.get(docRef); // READ 1
        if (!snap.exists) {
          throw FirebaseException(plugin: 'cloud_firestore', code: 'not-found');
        }
        final data = snap.data() ?? <String, dynamic>{};
        final currType = (data['type'] as String?) ?? '';

        if (currType != fromType) {
          throw FirebaseException(
            plugin: 'cloud_firestore',
            code: 'invalid-state',
            message: 'expected $fromType but was $currType',
          );
        }

        final currentSelectedBy = data['selectedBy'] as String?;
        if (!forceOverride &&
            currentSelectedBy != null &&
            currentSelectedBy.isNotEmpty &&
            currentSelectedBy != actor) {
          throw FirebaseException(
            plugin: 'cloud_firestore',
            code: 'conflict',
            message: 'selected by $currentSelectedBy',
          );
        }

        final update = <String, dynamic>{
          'type': toType,
          // 전환 시에는 선택 상태를 정리(유령 선택 방지)
          'isSelected': false,
          'selectedBy': null,
          'updatedAt': FieldValue.serverTimestamp(), // ✅ 전환 시점 갱신

          // 🔴 extraFields를 "같은 update 안에" 포함
          if (extraFields != null) ...extraFields,

          'logs': FieldValue.arrayUnion([
            {
              'action': '$fromType → $toType',
              'performedBy': actor,
              'timestamp': DateTime.now().toIso8601String(),
            },
          ]),
        };

        tx.update(docRef, update); // WRITE 1
      });

      /*await UsageReporter.instance.report(
        area: (extraFields?['area'] as String?) ?? '(unknown)',
        action: 'write',
        n: 1,
        source: 'PlateWriteService.transitionPlateType.tx',
      );*/
    } on FirebaseException {
      // ✅ DebugDatabaseLogger 로직 제거
      rethrow;
    } catch (e) {
      // ✅ DebugDatabaseLogger 로직 제거 (기존 throw 정책 유지)
      throw Exception("DB 업데이트 실패: $e");
    }
  }

  /// ✅ ‘주행’ 커밋 트랜잭션: 서버 상태(타입/선점자) 검증 + 원샷 업데이트
  Future<void> recordWhoPlateClick(
      String id,
      bool isSelected, {
        String? selectedBy,
        required String area,
      }) async {
    final docRef = _firestore.collection('plates').doc(id);

    try {
      await _firestore.runTransaction((tx) async {
        final snap = await tx.get(docRef); // READ 1
        if (!snap.exists) {
          throw FirebaseException(
            plugin: 'cloud_firestore',
            code: 'not-found',
            message: 'plate $id not found',
          );
        }

        final data = snap.data() ?? {};
        final type = (data['type'] as String?) ?? '';

        // ✅ 요청 계열 상태에서만 주행(선택) 허용
        const allowed = {'parking_requests', 'departure_requests'};
        if (!allowed.contains(type)) {
          throw FirebaseException(
            plugin: 'cloud_firestore',
            code: 'invalid-state',
            message: 'cannot set driving on $type',
          );
        }

        // ✅ 선택 충돌 방지
        final currentSelectedBy = data['selectedBy'] as String?;
        if (isSelected &&
            currentSelectedBy != null &&
            currentSelectedBy.isNotEmpty &&
            currentSelectedBy != selectedBy) {
          throw FirebaseException(
            plugin: 'cloud_firestore',
            code: 'conflict',
            message: 'already selected by $currentSelectedBy',
          );
        }

        final update = <String, dynamic>{
          'isSelected': isSelected,
          'selectedBy': isSelected ? selectedBy : null,
          'updatedAt': FieldValue.serverTimestamp(), // ✅ 선택 상태 변경 시각 갱신
          if (isSelected && (selectedBy?.trim().isNotEmpty ?? false))
            'logs': FieldValue.arrayUnion([
              {
                'action': '주행 중',
                'performedBy': selectedBy,
                'timestamp': DateTime.now().toIso8601String(),
              }
            ]),
        };

        tx.update(docRef, update); // WRITE 1
      });

      /*await UsageReporter.instance.report(
        area: area,
        action: 'write',
        n: 1,
        source: 'PlateWriteService.recordWhoPlateClick.tx',
      );*/
    } on FirebaseException {
      // ✅ DebugDatabaseLogger 로직 제거
      rethrow;
    } catch (e) {
      // ✅ DebugDatabaseLogger 로직 제거 (기존 throw 정책 유지)
      throw Exception("DB 업데이트 실패: $e");
    }
  }

  Map<String, dynamic> _enforceZeroFeeLock(
      Map<String, dynamic> data, {
        Map<String, dynamic>? existing,
      }) {
    int effInt(String key) {
      if (data.containsKey(key)) return _toInt(data[key]);
      if (existing != null && existing.containsKey(key)) {
        return _toInt(existing[key]);
      }
      return 0;
    }

    final int basic = effInt(PlateFields.basicAmount);
    final int add = effInt(PlateFields.addAmount);

    final bool shouldLock = (basic == 0 && add == 0);

    if (shouldLock) {
      data[PlateFields.isLockedFee] = true;

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
