import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';

class PlateStatusService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  DocumentReference<Map<String, dynamic>> _docRef(String plateNumber, String area) =>
      _firestore.collection('plate_status').doc('${plateNumber}_$area');

  bool _isEmptyInput(String customStatus, List<String> statusList) => customStatus.trim().isEmpty && statusList.isEmpty;

  Future<void> setPlateStatus({
    required String plateNumber,
    required String area,
    required String customStatus,
    required List<String> statusList,
    required String createdBy,
    bool deleteWhenEmpty = true,
    Map<String, dynamic>? extra,
  }) async {
    final ref = _docRef(plateNumber, area);

    try {
      if (_isEmptyInput(customStatus, statusList)) {
        if (deleteWhenEmpty) {
          final snap = await ref.get().timeout(const Duration(seconds: 10));
          if (snap.exists) {
            await ref.delete().timeout(const Duration(seconds: 10));
          }
        }
        return;
      }

      // upsert payload (extra 먼저 전개 → 보호 필드가 최종 우선권)
      final data = <String, dynamic>{
        ...?extra,
        'customStatus': customStatus.trim(),
        'statusList': statusList,
        'updatedAt': FieldValue.serverTimestamp(),
        'createdBy': createdBy,
        'area': area,
        // expireAt는 Cloud Functions에서 설정
      };

      // 트랜잭션 upsert + 타임아웃
      await _firestore.runTransaction((tx) async {
        final snap = await tx.get(ref).timeout(const Duration(seconds: 10));
        if (!snap.exists) {
          data['createdAt'] = FieldValue.serverTimestamp();
        }
        tx.set(ref, data, SetOptions(merge: true));
      }).timeout(const Duration(seconds: 10));
    } on FirebaseException {
      rethrow;
    } on TimeoutException {
      rethrow;
    } catch (_) {
      rethrow;
    }
  }

  Future<void> setMonthlyPlateStatus({
    required String plateNumber,
    required String area,
    required String createdBy,
    required String customStatus,
    required List<String> statusList,
    required String countType,
    required int regularAmount,
    required int regularDurationHours,
    required String regularType,
    required String startDate,
    required String endDate,
    required String periodUnit,
    String? specialNote,
    bool? isExtended,
    bool deleteWhenEmpty = true,
  }) async {
    final ref = _docRef(plateNumber, area);

    try {
      // ── 빈 입력 처리 ─────────────────────────────────────────
      if (_isEmptyInput(customStatus, statusList)) {
        if (deleteWhenEmpty) {
          final snap = await ref.get().timeout(const Duration(seconds: 10));
          if (snap.exists) {
            await ref.delete().timeout(const Duration(seconds: 10));
          }
        }
        return;
      }

      // ── 업서트 payload ───────────────────────────────────────
      // ⚠️ expireAt는 클라이언트에서 설정하지 않습니다. (Cloud Functions에서 설정)
      final base = <String, dynamic>{
        'customStatus': customStatus.trim(),
        'statusList': statusList,
        'updatedAt': FieldValue.serverTimestamp(),
        'createdBy': createdBy,
        'type': '정기',
        'countType': countType,
        'regularAmount': regularAmount,
        'regularDurationHours': regularDurationHours,
        'regularType': regularType,
        'startDate': startDate,
        'endDate': endDate,
        'periodUnit': periodUnit,
        'area': area,
        if (specialNote != null) 'specialNote': specialNote,
        if (isExtended != null) 'isExtended': isExtended,
      };

      // ── 트랜잭션 upsert + 타임아웃 ───────────────────────────
      await _firestore.runTransaction((tx) async {
        final snap = await tx.get(ref).timeout(const Duration(seconds: 10));
        if (!snap.exists) {
          base['createdAt'] = FieldValue.serverTimestamp();
        }
        tx.set(ref, base, SetOptions(merge: true));
      }).timeout(const Duration(seconds: 10));
    } on FirebaseException {
      rethrow;
    } on TimeoutException {
      rethrow;
    } catch (_) {
      rethrow;
    }
  }

  Future<void> deletePlateStatus(String plateNumber, String area) async {
    try {
      await _docRef(plateNumber, area).delete();
    } catch (e) {
      rethrow;
    }
  }
}
