import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../../models/plate_log_model.dart';
import 'plate_log_repository.dart';

class FirestorePlateLogRepository implements PlateLogRepository {
  final _collection = FirebaseFirestore.instance
      .collection('logs')
      .doc('plate_movements')
      .collection('entries');

  @override
  Future<void> savePlateLog(PlateLogModel log) async {
    final normalizedPlate = log.plateNumber.replaceAll(RegExp(r'[\s]'), '');
    final safeTimestamp = log.timestamp.toIso8601String().replaceAll(RegExp(r'[:.]'), '_');
    final docId = '${normalizedPlate}_$safeTimestamp${log.area}_${log.performedBy}';

    await _collection.doc(docId).set(log.toMap());

    debugPrint('✅ 로그 저장 완료: $docId');
  }

}
