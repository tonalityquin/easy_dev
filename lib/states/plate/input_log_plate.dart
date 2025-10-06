import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../../../models/plate_log_model.dart';

// import '../../utils/usage_reporter.dart';

class InputLogPlate with ChangeNotifier {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Future<void> saveLog(
      PlateLogModel log, {
        required String area,
      }) async {
    try {
      final logMap = log.toMap()..removeWhere((key, value) => value == null);
      final plateNumber = log.plateNumber;
      final documentId = '${plateNumber}_$area';

      // 🔵 WRITE: plates/{id}.update logs arrayUnion
      await _firestore.collection('plates').doc(documentId).update({
        'logs': FieldValue.arrayUnion([logMap]),
      });

      // 🧭 UsageReporter: Firestore 쓰기 1회 기록
      /*UsageReporter.instance.report(
        area: area,
        action: 'write',
        n: 1,
        source: 'InputLogPlate.saveLog',
      );*/

      debugPrint("✅ 로그가 Firestore에 저장되었습니다.");
    } catch (e) {
      debugPrint("❌ Firestore 로그 저장 실패: $e");
    }
  }
}
