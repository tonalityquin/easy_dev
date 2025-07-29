import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../../../models/plate_log_model.dart';

class InputLogPlate with ChangeNotifier {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  Future<void> saveLog(PlateLogModel log, {
    required String division,
    required String area,
  }) async {
    try {
      final logMap = log.toMap()..removeWhere((key, value) => value == null);
      final plateNumber = log.plateNumber;
      final documentId = '${plateNumber}_$area';

      await _firestore.collection('plates').doc(documentId).update({
        'logs': FieldValue.arrayUnion([logMap])
      });

      debugPrint("✅ 로그가 Firestore에 저장되었습니다.");
    } catch (e) {
      debugPrint("❌ Firestore 로그 저장 실패: $e");
    }
  }
}
