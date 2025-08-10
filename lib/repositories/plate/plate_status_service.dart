import 'package:cloud_firestore/cloud_firestore.dart';
import '../../screens/type_pages/debugs/firestore_logger.dart';

class PlateStatusService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  DocumentReference<Map<String, dynamic>> _docRef(String plateNumber, String area) =>
      _firestore.collection('plate_status').doc('${plateNumber}_$area');

  bool _isEmptyInput(String customStatus, List<String> statusList) =>
      customStatus.trim().isEmpty && statusList.isEmpty;

  /// 🔍 plate_status 조회
  Future<Map<String, dynamic>?> getPlateStatus(String plateNumber, String area) async {
    final docId = '${plateNumber}_$area';
    await FirestoreLogger().log('getPlateStatus called: $docId');

    try {
      final doc = await _docRef(plateNumber, area).get();
      if (doc.exists) {
        await FirestoreLogger().log('getPlateStatus success: $docId');
        return doc.data();
      } else {
        await FirestoreLogger().log('getPlateStatus not found: $docId');
        return null;
      }
    } catch (e) {
      await FirestoreLogger().log('getPlateStatus error: $e');
      rethrow;
    }
  }

  /// 📝 plate_status 저장 또는 업데이트
  /// - 입력(메모/상태)이 비어 있으면:
  ///   - deleteWhenEmpty=true: 기존 문서가 있으면 삭제, 없으면 no-op
  ///   - deleteWhenEmpty=false: 아무 것도 안 함
  Future<void> setPlateStatus({
    required String plateNumber,
    required String area,
    required String customStatus,
    required List<String> statusList,
    required String createdBy,
    bool deleteWhenEmpty = true,
    Map<String, dynamic>? extra, // 확장 필드(예: stage, billType)
  }) async {
    final docId = '${plateNumber}_$area';
    final ref = _docRef(plateNumber, area);
    await FirestoreLogger().log('setPlateStatus called: $docId');

    try {
      // 🚧 빈 입력 가드
      if (_isEmptyInput(customStatus, statusList)) {
        if (deleteWhenEmpty) {
          final snap = await ref.get();
          if (snap.exists) {
            await ref.delete();
            await FirestoreLogger().log('setPlateStatus deleted (empty input): $docId');
          } else {
            await FirestoreLogger().log('setPlateStatus skipped (empty input, not exists): $docId');
          }
        } else {
          await FirestoreLogger().log('setPlateStatus skipped (empty input, deleteWhenEmpty=false): $docId');
        }
        return;
      }

      // ✅ 생성/갱신 (createdAt은 최초 생성 시에만)
      final data = <String, dynamic>{
        'customStatus': customStatus.trim(),
        'statusList': statusList,
        'updatedAt': FieldValue.serverTimestamp(),
        'expireAt': Timestamp.fromDate(DateTime.now().add(const Duration(days: 1))), // 유지 시 로컬 계산
        'createdBy': createdBy,
        'area': area,
        ...?extra,
      };

      await _firestore.runTransaction((tx) async {
        final snap = await tx.get(ref);
        if (!snap.exists) {
          data['createdAt'] = FieldValue.serverTimestamp();
        }
        tx.set(ref, data, SetOptions(merge: true));
      });

      await FirestoreLogger().log('setPlateStatus success: $docId');
    } catch (e) {
      await FirestoreLogger().log('setPlateStatus error: $e');
      rethrow;
    }
  }

  /// 🗓️ 정기(월정기 등) plate_status 저장/업데이트
  /// - 동일 가드 적용(비어 있으면 삭제 or 생략)
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
    final docId = '${plateNumber}_$area';
    final ref = _docRef(plateNumber, area);
    await FirestoreLogger().log('📥 setMonthlyPlateStatus called: $docId');

    try {
      // 🚧 빈 입력 가드
      if (_isEmptyInput(customStatus, statusList)) {
        if (deleteWhenEmpty) {
          final snap = await ref.get();
          if (snap.exists) {
            await ref.delete();
            await FirestoreLogger().log('setMonthlyPlateStatus deleted (empty input): $docId');
          } else {
            await FirestoreLogger().log('setMonthlyPlateStatus skipped (empty input, not exists): $docId');
          }
        } else {
          await FirestoreLogger().log('setMonthlyPlateStatus skipped (empty input, deleteWhenEmpty=false): $docId');
        }
        return;
      }

      final base = <String, dynamic>{
        'customStatus': customStatus.trim(),
        'statusList': statusList,
        'updatedAt': FieldValue.serverTimestamp(),
        'expireAt': Timestamp.fromDate(DateTime.now().add(const Duration(days: 1))),
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

      await _firestore.runTransaction((tx) async {
        final snap = await tx.get(ref);
        if (!snap.exists) {
          base['createdAt'] = FieldValue.serverTimestamp();
        }
        tx.set(ref, base, SetOptions(merge: true));
      });

      await FirestoreLogger().log('✅ setMonthlyPlateStatus success: $docId');
    } catch (e) {
      await FirestoreLogger().log('❌ setMonthlyPlateStatus error: $e');
      rethrow;
    }
  }

  /// ❌ plate_status 삭제
  Future<void> deletePlateStatus(String plateNumber, String area) async {
    final docId = '${plateNumber}_$area';
    await FirestoreLogger().log('deletePlateStatus called: $docId');

    try {
      await _docRef(plateNumber, area).delete();
      await FirestoreLogger().log('deletePlateStatus success: $docId');
    } catch (e) {
      await FirestoreLogger().log('deletePlateStatus error: $e');
      rethrow;
    }
  }
}