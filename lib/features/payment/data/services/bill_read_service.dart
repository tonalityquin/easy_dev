import '../../../../shared/area_remote_settings/application/area_snapshot_scope.dart';
import '../../../location/data/services/location_company_scope.dart';
import '../../../../app/utils/status_dialog.dart';
import '../../../../app/firebase_activity/firebase_activity_monitor.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../app/utils/dev_firebase_debug_dialog.dart';

import '../../domain/models/bill_model.dart';
import '../../domain/models/regular_bill_model.dart';

class BillReadService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Future<
      ({
        List<BillModel> generalBills,
        List<RegularBillModel> regularBills,
      })> getBillOnce(String area) async {
    QuerySnapshot<Map<String, dynamic>> snapshot;

    try {
      final prefs = await SharedPreferences.getInstance();
      final cachedCompany = (prefs.getString('division') ?? '').trim();
      final company = AreaSnapshotScope.isBound && AreaSnapshotScope.area == area.trim()
          ? AreaSnapshotScope.division.trim()
          : (await LocationCompanyScope.resolve(_firestore) ?? '').trim();
      if (company.isEmpty || (cachedCompany.isNotEmpty && cachedCompany != company)) {
        throw StateError('BILL_COMPANY_SESSION_MISMATCH');
      }
      StatusDialog.recordDebugOperation('bill.read', 'company_scoped', details: {'companyId': company, 'area': area});
      snapshot = await FirebaseActivityMonitor.track(FirebaseActivityKind.read, () => _firestore
          .collection('bill')
          .where('companyId', isEqualTo: company)
          .where('area', isEqualTo: area)
          .get(), source: 'bill_read_service.get');
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('❌ Firestore bill.read 실패(area=$area): $e');
        debugPrint('stack: $st');
      }
      await DevFirebaseDebugDialog.show(
        operation: 'personal.bill.read',
        error: e,
        stackTrace: st,
        details: <String, Object?>{
          'collection': 'bill',
          'area': area,
          'companyId': (await SharedPreferences.getInstance()).getString('division') ?? '',
          'query': 'where(companyId == division).where(area == $area)',
          'filters': 'companyId == division AND area == $area',
          'orderBy': 'none',
          'queryShape': 'two-field-equality',
          'compositeIndex': 'check-firestore-index-status',
        },
      );
      rethrow;
    }

    final List<BillModel> generalBills = [];
    final List<RegularBillModel> regularBills = [];

    Future<T?> tryParse<T>(
      T Function() parse, {
      required String id,
      required String model,
      Map<String, dynamic>? raw,
    }) async {
      try {
        return parse();
      } catch (e, st) {
        if (kDebugMode) {
          debugPrint('⚠️ Bill parse 실패(id=$id, model=$model, area=$area): $e');
          debugPrint('stack: $st');
          if (raw != null) {
            debugPrint('rawKeys(<=20): ${raw.keys.take(20).toList()}');
          }
        }
        await DevFirebaseDebugDialog.show(
          operation: 'personal.bill.parse',
          error: e,
          stackTrace: st,
          details: <String, Object?>{
            'collection': 'bill',
            'docId': id,
            'model': model,
            'area': area,
            'rawKeys': raw?.keys.take(40).toList(growable: false),
          },
        );
        return null;
      }
    }

    for (final doc in snapshot.docs) {
      final data = doc.data();
      final type = (data['type'] as String?) ?? '변동';

      if (type == '정기') {
        final item = await tryParse<RegularBillModel>(
          () => RegularBillModel.fromMap(doc.id, data),
          id: doc.id,
          model: 'RegularBillModel',
          raw: data,
        );
        if (item != null) regularBills.add(item);
      } else {
        final item = await tryParse<BillModel>(
          () => BillModel.fromMap(doc.id, data),
          id: doc.id,
          model: 'BillModel',
          raw: data,
        );
        if (item != null) generalBills.add(item);
      }
    }

    return (generalBills: generalBills, regularBills: regularBills);
  }
}
