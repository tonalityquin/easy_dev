import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'dart:developer' as dev;

import '../../models/plate_log_model.dart';
import '../../models/plate_model.dart';
import '../../screens/community_package/debug_package/debug_firestore_logger.dart';

class PlateWriteService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Future<void> addOrUpdatePlate(String documentId, PlateModel plate) async {
    final docRef = _firestore.collection('plates').doc(documentId);

    try {
      final docSnapshot =
      await docRef.get().timeout(const Duration(seconds: 10));

      var newData = plate.toMap();
      newData =
          _enforceZeroFeeLock(newData, existing: docSnapshot.data());

      final exists = docSnapshot.exists;
      if (exists) {
        final existingData =
            docSnapshot.data() ?? const <String, dynamic>{};

        final compOld = Map<String, dynamic>.from(existingData)
          ..remove(PlateFields.logs);
        final compNew = Map<String, dynamic>.from(newData)
          ..remove(PlateFields.logs);

        if (_isSameData(compOld, compNew)) {
          return;
        }

        newData.remove(PlateFields.logs);
      }

      await docRef
          .set(newData, SetOptions(merge: true))
          .timeout(const Duration(seconds: 10));
    } on TimeoutException catch (e, st) {
      try {
        await DebugFirestoreLogger().log({
          'op': 'plates.write.addOrUpdate.timeout',
          'collection': 'plates',
          'docPath': docRef.path,
          'docId': documentId,
          'meta': {'timeoutSec': 10},
          'error': {
            'type': e.runtimeType.toString(),
            'message': e.toString(),
          },
          'stack': st.toString(),
          'tags': ['plates', 'write', 'addOrUpdate', 'timeout', 'error'],
        }, level: 'error');
      } catch (_) {}
      rethrow;
    } on FirebaseException catch (e, st) {
      try {
        await DebugFirestoreLogger().log({
          'op': 'plates.write.addOrUpdate',
          'collection': 'plates',
          'docPath': docRef.path,
          'docId': documentId,
          'error': {
            'type': e.runtimeType.toString(),
            'code': e.code,
            'message': e.toString(),
          },
          'stack': st.toString(),
          'tags': ['plates', 'write', 'addOrUpdate', 'error'],
        }, level: 'error');
      } catch (_) {}
      rethrow;
    } catch (e, st) {
      try {
        await DebugFirestoreLogger().log({
          'op': 'plates.write.addOrUpdate.unknown',
          'collection': 'plates',
          'docPath': docRef.path,
          'docId': documentId,
          'error': {
            'type': e.runtimeType.toString(),
            'message': e.toString(),
          },
          'stack': st.toString(),
          'tags': ['plates', 'write', 'addOrUpdate', 'error'],
        }, level: 'error');
      } catch (_) {}
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
    } on FirebaseException catch (e, st) {
      try {
        await DebugFirestoreLogger().log({
          'op': 'plates.update.prefetch',
          'collection': 'plates',
          'docPath': docRef.path,
          'docId': documentId,
          'error': {
            'type': e.runtimeType.toString(),
            'code': e.code,
            'message': e.toString(),
          },
          'stack': st.toString(),
          'tags': ['plates', 'update', 'prefetch', 'error'],
        }, level: 'error');
      } catch (_) {}
      rethrow;
    } on TimeoutException catch (e, st) {
      try {
        await DebugFirestoreLogger().log({
          'op': 'plates.update.prefetch.timeout',
          'collection': 'plates',
          'docPath': docRef.path,
          'docId': documentId,
          'meta': {'timeoutSec': 10},
          'error': {
            'type': e.runtimeType.toString(),
            'message': e.toString(),
          },
          'stack': st.toString(),
          'tags': ['plates', 'update', 'prefetch', 'timeout', 'error'],
        }, level: 'error');
      } catch (_) {}
      rethrow;
    }

    final fields = _enforceZeroFeeLock(
      Map<String, dynamic>.from(updatedFields),
      existing: current,
    );

    if (log != null) {
      fields['logs'] = FieldValue.arrayUnion([log.toMap()]);
    }

    try {
      await docRef.update(fields);
      debugPrint("✅ 문서 업데이트 완료: $documentId");
    } on FirebaseException catch (e, st) {
      debugPrint("🔥 문서 업데이트 실패: $e");
      try {
        await DebugFirestoreLogger().log({
          'op': 'plates.update',
          'collection': 'plates',
          'docPath': docRef.path,
          'docId': documentId,
          'fieldsPreview': {
            'keys': fields.keys.take(30).toList(),
            'len': fields.length,
            'hasLog': log != null,
          },
          'error': {
            'type': e.runtimeType.toString(),
            'code': e.code,
            'message': e.toString(),
          },
          'stack': st.toString(),
          'tags': ['plates', 'update', 'error'],
        }, level: 'error');
      } catch (_) {}
      rethrow;
    } catch (e, st) {
      debugPrint("🔥 문서 업데이트 실패: $e");
      try {
        await DebugFirestoreLogger().log({
          'op': 'plates.update.unknown',
          'collection': 'plates',
          'docPath': docRef.path,
          'docId': documentId,
          'fieldsPreview': {
            'keys': fields.keys.take(30).toList(),
            'len': fields.length,
            'hasLog': log != null,
          },
          'error': {
            'type': e.runtimeType.toString(),
            'message': e.toString(),
          },
          'stack': st.toString(),
          'tags': ['plates', 'update', 'error'],
        }, level: 'error');
      } catch (_) {}
      rethrow;
    }
  }

  Future<void> deletePlate(String documentId) async {
    final docRef = _firestore.collection('plates').doc(documentId);

    try {
      await docRef.delete();
      dev.log("🗑️ 문서 삭제 완료: $documentId", name: "Firestore");
    } on FirebaseException catch (e, st) {
      if (e.code == 'not-found') {
        debugPrint("⚠️ 삭제 시 문서 없음 (무시): $documentId");
        return;
      }
      dev.log("🔥 문서 삭제 실패: $e", name: "Firestore");
      try {
        await DebugFirestoreLogger().log({
          'op': 'plates.delete',
          'collection': 'plates',
          'docPath': docRef.path,
          'docId': documentId,
          'error': {
            'type': e.runtimeType.toString(),
            'code': e.code,
            'message': e.toString(),
          },
          'stack': st.toString(),
          'tags': ['plates', 'delete', 'error'],
        }, level: 'error');
      } catch (_) {}
      rethrow;
    } catch (e, st) {
      try {
        await DebugFirestoreLogger().log({
          'op': 'plates.delete.unknown',
          'collection': 'plates',
          'docPath': docRef.path,
          'docId': documentId,
          'error': {
            'type': e.runtimeType.toString(),
            'message': e.toString(),
          },
          'stack': st.toString(),
          'tags': ['plates', 'delete', 'error'],
        }, level: 'error');
      } catch (_) {}
      rethrow;
    }
  }

  Future<void> recordWhoPlateClick(
      String id,
      bool isSelected, {
        String? selectedBy,
      }) async {
    final docRef = _firestore.collection('plates').doc(id);

    try {
      await docRef.update({
        'isSelected': isSelected,
        'selectedBy': isSelected ? selectedBy : null,
      });
    } on FirebaseException catch (e, st) {
      if (e.code == 'not-found') {
        debugPrint("번호판 문서를 찾을 수 없습니다: $id");
        return;
      }
      debugPrint("DB 에러 (recordWhoPlateClick): $e");
      try {
        await DebugFirestoreLogger().log({
          'op': 'plates.recordWhoClick',
          'collection': 'plates',
          'docPath': docRef.path,
          'docId': id,
          'inputs': {
            'isSelected': isSelected,
            'hasSelectedBy': selectedBy != null,
          },
          'error': {
            'type': e.runtimeType.toString(),
            'code': e.code,
            'message': e.toString(),
          },
          'stack': st.toString(),
          'tags': ['plates', 'update', 'recordWhoClick', 'error'],
        }, level: 'error');
      } catch (_) {}
      throw Exception("DB 업데이트 실패: $e");
    } catch (e, st) {
      debugPrint("DB 에러 (recordWhoPlateClick): $e");
      try {
        await DebugFirestoreLogger().log({
          'op': 'plates.recordWhoClick.unknown',
          'collection': 'plates',
          'docPath': docRef.path,
          'docId': id,
          'inputs': {
            'isSelected': isSelected,
            'hasSelectedBy': selectedBy != null,
          },
          'error': {
            'type': e.runtimeType.toString(),
            'message': e.toString(),
          },
          'stack': st.toString(),
          'tags': ['plates', 'update', 'recordWhoClick', 'error'],
        }, level: 'error');
      } catch (_) {}
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
