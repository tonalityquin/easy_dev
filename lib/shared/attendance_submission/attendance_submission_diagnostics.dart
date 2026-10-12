import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../app/utils/status_dialog.dart';
import '../../features/selector/application/dev_auth.dart';

class AttendanceSubmissionDiagnostics {
  AttendanceSubmissionDiagnostics._();

  static const int _limit = 360;
  static final List<String> _lines = <String>[];

  static void log(String scope, String message) {
    final normalizedScope = scope.trim().isEmpty ? 'general' : scope.trim();
    final normalizedMessage = message.trim();
    if (normalizedMessage.isEmpty) return;
    final line =
        '[ATTENDANCE_REVIEW][$normalizedScope][${DateTime.now().toIso8601String()}] $normalizedMessage';
    _lines.add(line);
    if (_lines.length > _limit) {
      _lines.removeRange(0, _lines.length - _limit);
    }
    debugPrint(line);
  }

  static String get debugPrintCode {
    if (_lines.isEmpty) {
      return 'debugPrint(${jsonEncode('[ATTENDANCE_REVIEW] 기록된 로그가 없습니다.')});';
    }
    return _lines
        .map((line) => 'debugPrint(${jsonEncode(line)});')
        .join('\n');
  }

  static Future<void> showStatus(
    BuildContext context, {
    String title = '기록 제출 Review 상태',
    bool failure = false,
  }) async {
    final enabled = await DevAuth.isDevModeEnabled();
    if (!enabled || !context.mounted) return;
    log('status', 'open title=$title failure=$failure lines=${_lines.length}');
    final copyText = debugPrintCode;
    if (failure) {
      await StatusDialog.showFailure(
        context,
        title: title,
        description: '출퇴근 및 휴게시간 Review 상태 로그',
        copyText: copyText,
        copyButtonLabel: 'debugPrint 코드 복사',
        visibleDuration: Duration.zero,
        useCommonUi: true,
        awaitManualClose: true,
      );
      return;
    }
    await StatusDialog.showSuccess(
      context,
      title: title,
      description: '출퇴근 및 휴게시간 Review 상태 로그',
      copyText: copyText,
      copyButtonLabel: 'debugPrint 코드 복사',
      visibleDuration: Duration.zero,
      useCommonUi: true,
      awaitManualClose: true,
    );
  }
}
