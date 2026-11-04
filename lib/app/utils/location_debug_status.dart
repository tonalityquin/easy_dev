import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../features/selector/application/dev_auth.dart';
import '../init/app_navigator.dart';
import 'status_dialog.dart';

class LocationDebugStatus {
  const LocationDebugStatus._();

  static bool _showing = false;

  static void report({
    BuildContext? context,
    required String title,
    required String operation,
    Object? error,
    StackTrace? stackTrace,
    Map<String, Object?> details = const <String, Object?>{},
  }) {
    final log = _buildLog(
      operation: operation,
      error: error,
      stackTrace: stackTrace,
      details: details,
    );
    debugPrint(log);
    unawaited(_show(
      context: context,
      title: title,
      log: log,
    ));
  }

  static String _buildLog({
    required String operation,
    Object? error,
    StackTrace? stackTrace,
    required Map<String, Object?> details,
  }) {
    final buffer = StringBuffer()
      ..writeln('timestamp=${DateTime.now().toIso8601String()}')
      ..writeln('operation=$operation');

    for (final entry in details.entries) {
      buffer.writeln('${entry.key}=${entry.value}');
    }

    if (error != null) {
      buffer.writeln('error=$error');
    }

    if (stackTrace != null) {
      buffer
        ..writeln('stackTrace=')
        ..writeln(stackTrace);
    }

    return buffer.toString().trimRight();
  }

  static Future<void> _show({
    BuildContext? context,
    required String title,
    required String log,
  }) async {
    if (_showing) return;
    _showing = true;

    try {
      final enabled = await DevAuth.isDeveloperLoggedIn();
      if (!enabled) return;

      final target = context != null && context.mounted
          ? context
          : AppNavigator.context;
      if (target == null || !target.mounted) return;

      await StatusDialog.showFailure(
        target,
        title: title,
        description: log,
        copyText: log,
        copyButtonLabel: '로그 복사',
        visibleDuration: const Duration(seconds: 60),
        useCommonUi: true,
      );
    } finally {
      _showing = false;
    }
  }
}
