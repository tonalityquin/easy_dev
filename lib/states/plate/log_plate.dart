import 'package:easydev/utils/gcs_json_uploader.dart';
import 'package:flutter/material.dart';
import '../../../models/plate_log_model.dart';

class LogPlateState with ChangeNotifier {
  final GcsJsonUploader _uploader = GcsJsonUploader();

  Future<void> saveLog(PlateLogModel log, {required String division, required String area}) async {
    try {
      final logMap = log.toMap()..removeWhere((key, value) => value == null);
      final plateNumber = log.plateNumber;

      await _uploader.uploadForPlateLogTypeJson(logMap, plateNumber, division, area);
      debugPrint("✅ 로그가 GCS에 저장되었습니다.");
    } catch (e) {
      debugPrint("❌ GCS 로그 저장 실패: $e");
    }
  }
}
