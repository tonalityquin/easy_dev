import 'package:flutter/material.dart';
import '../../../models/plate_log_model.dart';
import '../../utils/gcs_uploader.dart';

class LogPlateState with ChangeNotifier {
  final GCSUploader _uploader = GCSUploader();

  Future<void> saveLog(PlateLogModel log, {required String division, required String area}) async {
    try {
      final logMap = log.toMap();
      final plateNumber = log.plateNumber;

      // ✅ 명확하게 매개변수 값 사용
      await _uploader.uploadLogJson(logMap, plateNumber, division, area);
      debugPrint("✅ 로그가 GCS에 저장되었습니다.");
    } catch (e) {
      debugPrint("❌ GCS 로그 저장 실패: $e");
    }
  }

  @override
  void dispose() {
    super.dispose();
  }
}
