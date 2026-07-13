import 'package:cloud_firestore/cloud_firestore.dart';
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
    final indexError = _looksLikeIndexError(error);
    final developerMode = await DevAuth.isDeveloperLoggedIn();
    if (!context.mounted) return;
    final indexUrl = _extractIndexUrl(error);
    final log = buildLog(
      operation: operation,
      error: error,
      stackTrace: stackTrace,
      details: details,
    );
    final copyText = indexError && developerMode && indexUrl.isNotEmpty
        ? indexUrl
        : developerMode
            ? log
            : null;
    final copyLabel = indexError && developerMode && indexUrl.isNotEmpty
        ? '인덱스 링크 복사'
        : '로그 복사';
    await StatusDialog.showFailure(
      context,
      title: title,
      description: _description(error, developerMode: developerMode),
      copyText: copyText,
      copyButtonLabel: copyLabel,
      visibleDuration: copyText == null
          ? const Duration(seconds: 5)
          : const Duration(seconds: 60),
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
      buffer.writeln('errorType: ${error.runtimeType}');
      if (error is FirebaseException) {
        buffer
          ..writeln('firebasePlugin: ${error.plugin}')
          ..writeln('firebaseCode: ${error.code}')
          ..writeln('firebaseMessage: ${error.message ?? ''}');
      } else {
        buffer.writeln('error: $error');
      }
    }
    final indexUrl = _extractIndexUrl(error);
    if (indexUrl.isNotEmpty) buffer.writeln('indexUrl: $indexUrl');
    if (_looksLikeIndexError(error)) {
      buffer
        ..writeln('indexHint: Firestore 복합 인덱스가 필요합니다.')
        ..writeln('indexAction: 개발자 모드에서 인덱스 링크를 복사해 Firebase Console에서 생성하세요.');
    }
    if (stackTrace != null) {
      buffer
        ..writeln('stackTrace:')
        ..writeln(stackTrace.toString());
    }
    return buffer.toString().trim();
  }

  static String _description(Object? error, {required bool developerMode}) {
    if (_looksLikeIndexError(error)) {
      if (developerMode) {
        final url = _extractIndexUrl(error);
        return url.isNotEmpty
            ? 'Firestore 복합 인덱스가 필요합니다. 아래 버튼으로 생성 링크를 클립보드에 복사하세요.'
            : 'Firestore 복합 인덱스가 필요합니다. 로그를 복사해 쿼리 조건을 확인하세요.';
      }
      return '달력 검색 또는 조회 준비가 아직 완료되지 않았습니다. 관리자에게 문의해 주세요.';
    }
    if (error is FirebaseException) {
      switch (error.code) {
        case 'unavailable':
        case 'network-request-failed':
          return '네트워크 연결을 확인한 뒤 다시 시도해 주세요.';
        case 'deadline-exceeded':
          return '요청 시간이 초과되었습니다. 잠시 후 다시 시도해 주세요.';
        case 'resource-exhausted':
          return '요청이 많습니다. 잠시 후 다시 시도해 주세요.';
        case 'permission-denied':
          return '달력 데이터에 접근하지 못했습니다.';
      }
    }
    return '본사 달력 작업을 완료하지 못했습니다. 다시 시도해 주세요.';
  }

  static bool _looksLikeIndexError(Object? error) {
    final text = error is FirebaseException
        ? '${error.code} ${error.message ?? ''}'.toLowerCase()
        : error.toString().toLowerCase();
    return text.contains('index') ||
        text.contains('failed-precondition') ||
        text.contains('requires an index');
  }

  static String _extractIndexUrl(Object? error) {
    final text = error is FirebaseException
        ? error.message ?? ''
        : error?.toString() ?? '';
    final matches = RegExp(r'''https?://[^\s<>"']+''').allMatches(text);
    for (final match in matches) {
      var value = match.group(0) ?? '';
      while (value.endsWith('.') ||
          value.endsWith(',') ||
          value.endsWith(')') ||
          value.endsWith(']')) {
        value = value.substring(0, value.length - 1);
      }
      if (value.contains('console.firebase.google.com')) return value;
    }
    return '';
  }
}
