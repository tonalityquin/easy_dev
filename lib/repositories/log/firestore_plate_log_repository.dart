import 'package:flutter/material.dart';
import 'plate_log_repository.dart';

class FirestorePlateLogRepository implements PlateLogRepository {
  // 🔕 로그 저장 기능은 비활성화됨 (2025-04 정책 변경)

  @override
  Future<void> savePlateLog(dynamic log) async {
    debugPrint('⚠️ 로그 저장은 현재 비활성화 상태입니다.');
    // noop
  }
}
