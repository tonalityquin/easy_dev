import 'package:flutter/material.dart';

import '../../../app/utils/status_dialog.dart';
import '../../selector/application/dev_auth.dart';

class HeadquarterCalendarStatusDialog {
  const HeadquarterCalendarStatusDialog._();

  static Future<void> showFailure(
    BuildContext context, {
    required String title,
    required String operation,
    Object? error,
    StackTrace? stackTrace,
    Map<String, Object?> details = const <String, Object?>{},
  }) async {
    if (!context.mounted) return;
    final developerMode = await DevAuth.isDeveloperLoggedIn();
    if (!context.mounted) return;
    final log = buildLog(
      operation: operation,
      error: error,
      stackTrace: stackTrace,
      details: details,
    );
    await StatusDialog.showFailure(
      context,
      title: title,
      description: '본사 달력 작업을 완료하지 못했습니다. 다시 시도해 주세요.',
      copyText: developerMode ? log : null,
      copyButtonLabel: '로그 복사',
      visibleDuration: developerMode
          ? const Duration(seconds: 60)
          : const Duration(seconds: 5),
    );
  }

  static String buildLog({
    required String operation,
    Object? error,
    StackTrace? stackTrace,
    Map<String, Object?> details = const <String, Object?>{},
  }) {
    final buffer = StringBuffer()
      ..writeln('[본사 달력 상태 로그]')
      ..writeln('operation: $operation')
      ..writeln('time: ${DateTime.now().toIso8601String()}');
    if (details.isNotEmpty) {
      buffer.writeln('details:');
      for (final entry in details.entries) {
        buffer.writeln('- ${entry.key}: ${entry.value}');
      }
    }
    if (error != null) {
      buffer
        ..writeln('errorType: ${error.runtimeType}')
        ..writeln('error: $error');
    }
    if (stackTrace != null) {
      buffer
        ..writeln('stackTrace:')
        ..writeln(stackTrace.toString());
    }
    return buffer.toString().trim();
  }
}
