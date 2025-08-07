import 'package:cloud_firestore/cloud_firestore.dart';
import '../../screens/type_pages/debugs/firestore_logger.dart';

class PlateStatusService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// 🔍 plate_status 조회
  Future<Map<String, dynamic>?> getPlateStatus(String plateNumber, String area) async {
    final docId = '${plateNumber}_$area';
    await FirestoreLogger().log('getPlateStatus called: $docId');

    try {
      final doc = await _firestore.collection('plate_status').doc(docId).get();

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
  Future<void> setPlateStatus({
    required String plateNumber,
    required String area,
    required String customStatus,
    required List<String> statusList,
    required String createdBy,
  }) async {
    final docId = '${plateNumber}_$area';
    final now = DateTime.now();
    final expireAt = Timestamp.fromDate(now.add(const Duration(days: 1)));

    await FirestoreLogger().log('setPlateStatus called: $docId');

    try {
      await _firestore.collection('plate_status').doc(docId).set({
        'customStatus': customStatus,
        'statusList': statusList,
        'updatedAt': Timestamp.fromDate(now),
        'expireAt': expireAt,
        'createdBy': createdBy,
        'area': area,
      }, SetOptions(merge: true));

      await FirestoreLogger().log('setPlateStatus success: $docId');
    } catch (e) {
      await FirestoreLogger().log('setPlateStatus error: $e');
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
    String? specialNote, // ✅ 추가
    bool? isExtended, // ✅ 추가
  }) async {
    final docId = '${plateNumber}_$area';
    final now = DateTime.now();
    final expireAt = Timestamp.fromDate(now.add(const Duration(days: 1)));

    await FirestoreLogger().log('📥 setMonthlyPlateStatus called: $docId');

    try {
      final data = {
        'customStatus': customStatus,
        'statusList': statusList,
        'updatedAt': Timestamp.fromDate(now),
        'expireAt': expireAt,
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
        if (specialNote != null) 'specialNote': specialNote, // ✅ null 체크 후 저장
        if (isExtended != null) 'isExtended': isExtended, // ✅ null 체크 후 저장
      };

      await _firestore.collection('plate_status').doc(docId).set(
            data,
            SetOptions(merge: true),
          );

      await FirestoreLogger().log('✅ setMonthlyPlateStatus success: $docId');
    } catch (e) {
      await FirestoreLogger().log('❌ setMonthlyPlateStatus error: $e');
      rethrow;
    }
  }

  Future<void> addPaymentHistory({
    required String plateNumber,
    required String area,
    required String paidAt,
    required String paidBy,
    required int amount,
    required String note,
    required bool extended,
  }) async {
    final docId = '${plateNumber}_$area';
    final now = DateTime.now();

    await FirestoreLogger().log('📄 결제 내역 기록: $docId');

    try {
      await _firestore.collection('plate_status').doc(docId).collection('payment_history').add({
        'paidAt': paidAt,
        'paidBy': paidBy,
        'amount': amount,
        'note': note,
        'extended': extended,
        'createdAt': now,
      });

      await FirestoreLogger().log('✅ 결제 내역 저장 완료');
    } catch (e) {
      await FirestoreLogger().log('❌ 결제 내역 저장 실패: $e');
      rethrow;
    }
  }

  /// ❌ plate_status 삭제
  Future<void> deletePlateStatus(String plateNumber, String area) async {
    final docId = '${plateNumber}_$area';
    await FirestoreLogger().log('deletePlateStatus called: $docId');

    try {
      await _firestore.collection('plate_status').doc(docId).delete();
      await FirestoreLogger().log('deletePlateStatus success: $docId');
    } catch (e) {
      await FirestoreLogger().log('deletePlateStatus error: $e');
      rethrow;
    }
  }
}
