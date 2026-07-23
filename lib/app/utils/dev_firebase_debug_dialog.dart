import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../features/selector/application/dev_auth.dart';
import '../init/app_navigator.dart';
import 'status_dialog.dart';

class DevFirebaseDebugDialog {
  DevFirebaseDebugDialog._();

  static bool _showing = false;

  static Future<void> show({
    BuildContext? context,
    required String operation,
    Object? error,
    StackTrace? stackTrace,
    Map<String, Object?> details = const <String, Object?>{},
    String title = 'Firebase 디버그',
    bool usePromptUi = false,
  }) async {
    final fullText = _buildFullText(
      operation: operation,
      error: error,
      stackTrace: stackTrace,
      details: details,
    );

    debugPrint(fullText);

    final enabled = await DevAuth.isDeveloperLoggedIn();
    if (!enabled) return;

    if (_showing) return;

    final ctx = _resolveContext(context);
    if (ctx == null || !ctx.mounted) return;

    _showing = true;
    try {
      await StatusDialog.showFailure(
        ctx,
        title: title,
        description: fullText,
        copyText: fullText,
        copyButtonLabel: '전문 복사',
        usePromptUi: usePromptUi,
      );
    } finally {
      _showing = false;
    }
  }

  static BuildContext? _resolveContext(BuildContext? context) {
    if (context != null && context.mounted) return context;
    final appContext = AppNavigator.context;
    if (appContext != null && appContext.mounted) return appContext;
    return null;
  }

  static String _buildFullText({
    required String operation,
    Object? error,
    StackTrace? stackTrace,
    Map<String, Object?> details = const <String, Object?>{},
  }) {
    final now = DateTime.now().toIso8601String();
    final b = StringBuffer()
      ..writeln('[Firebase Debug]')
      ..writeln('time: $now')
      ..writeln('operation: $operation');

    if (details.isNotEmpty) {
      b.writeln('details:');
      for (final entry in details.entries) {
        b.writeln('- ${entry.key}: ${_stringify(entry.value)}');
      }
    }

    if (error != null) {
      b.writeln('errorType: ${error.runtimeType}');
      if (error is FirebaseException) {
        b.writeln('firebase.plugin: ${error.plugin}');
        b.writeln('firebase.code: ${error.code}');
        if ((error.message ?? '').trim().isNotEmpty) {
          b.writeln('firebase.message: ${error.message}');
        }
      }
      b.writeln('error: $error');
    }

    if (stackTrace != null) {
      b.writeln('stackTrace:');
      b.writeln(stackTrace.toString());
    }

    return b.toString().trimRight();
  }

  static String _stringify(Object? value) {
    if (value == null) return 'null';
    if (value is Map) {
      return value.entries
          .map((entry) => '${entry.key}: ${_stringify(entry.value)}')
          .join(', ');
    }
    if (value is Iterable) {
      return value.map((entry) => _stringify(entry)).join(', ');
    }
    return value.toString();
  }
}
