import '../../../../app/firebase_activity/firebase_activity_monitor.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/models/bill_model.dart';
import '../../domain/models/regular_bill_model.dart';

class BillWriteService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Future<String> _companyForArea(String area) async {
    final prefs = await SharedPreferences.getInstance();
    final company = (prefs.getString('division') ?? '').trim();
    if (company.isEmpty || area.trim().isEmpty) {
      throw StateError('BILL_COMPANY_AREA_REQUIRED');
    }
    return company;
  }

  Future<void> addNormalBill(BillModel bill) async {
    final docRef = _firestore.collection('bill').doc(bill.id);
    final data = bill.toFirestoreMap()..putIfAbsent('type', () => '변동');
    data['companyId'] = await _companyForArea(bill.area);

    data.removeWhere(
        (key, value) => value == null || value.toString().trim().isEmpty);

    try {
      await FirebaseActivityMonitor.track(FirebaseActivityKind.set, () => docRef.set(data), source: 'bill_write_service.set');
      debugPrint("✅ 일반 정산 저장 성공: ${bill.id}");
    } catch (e, st) {
      debugPrint("🔥 일반 정산 저장 실패: $e");
      debugPrint("stack: $st");
      rethrow;
    }
  }

  Future<void> addRegularBill(RegularBillModel bill) async {
    final docRef = _firestore.collection('bill').doc(bill.id);
    final data = bill.toFirestoreMap();
    data['companyId'] = await _companyForArea(bill.area);

    data.removeWhere(
        (key, value) => value == null || value.toString().trim().isEmpty);

    try {
      await FirebaseActivityMonitor.track(FirebaseActivityKind.set, () => docRef.set(data), source: 'bill_write_service.set');
      debugPrint("✅ 정기 정산 저장 성공: ${bill.id}");
    } catch (e, st) {
      debugPrint("🔥 정기 정산 저장 실패: $e");
      debugPrint("stack: $st");
      rethrow;
    }
  }
}
