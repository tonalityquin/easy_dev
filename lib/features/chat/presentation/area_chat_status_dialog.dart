import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../app/utils/status_dialog.dart';
import '../../selector/application/dev_auth.dart';
import '../application/chat_failure.dart';

class AreaChatStatusDialog {
  const AreaChatStatusDialog._();

  static Future<void> showIndexFailure(
    BuildContext context, {
    required ChatFailure failure,
    Map<String, Object?> details = const <String, Object?>{},
  }) async {
    if (!context.mounted || !failure.isIndexRequired) return;
    final developerMode = await DevAuth.isDeveloperLoggedIn();
    if (!developerMode || !context.mounted) return;

    final indexUrl = extractIndexUrl(failure.cause);
    final log = buildLog(
      failure: failure,
      details: details,
      indexUrl: indexUrl,
    );
    final hasIndexUrl = indexUrl != null && indexUrl.isNotEmpty;

    await StatusDialog.showFailure(
      context,
      title: '채팅 복합 인덱스 필요',
      description: hasIndexUrl
          ? '오류에서 Firebase Console 복합 인덱스 생성 링크를 찾았습니다. 링크를 복사해 브라우저에서 열고 인덱스를 생성하세요.'
          : 'Firestore 복합 인덱스가 필요합니다. 로그를 복사해 Firebase Console의 인덱스 설정과 쿼리 조건을 확인하세요.',
      copyText: hasIndexUrl ? indexUrl : log,
      copyButtonLabel: hasIndexUrl ? '인덱스 링크 복사' : '로그 복사',
      visibleDuration: const Duration(seconds: 90),
    );
  }

  static String buildLog({
    required ChatFailure failure,
    Map<String, Object?> details = const <String, Object?>{},
    String? indexUrl,
  }) {
    final buffer = StringBuffer()
      ..writeln('[채팅 상태 로그]')
      ..writeln('operation: ${failure.operation.name}')
      ..writeln('failureKind: ${failure.kind.name}')
      ..writeln('time: ${DateTime.now().toIso8601String()}')
      ..writeln('retryable: ${failure.retryable}');

    if (details.isNotEmpty) {
      buffer.writeln('details:');
      for (final entry in details.entries) {
        buffer.writeln('- ${entry.key}: ${entry.value}');
      }
    }

    final error = failure.cause;
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

    if (indexUrl != null && indexUrl.isNotEmpty) {
      buffer.writeln('indexUrl: $indexUrl');
    }

    buffer
      ..writeln('indexHint: Firestore 복합 인덱스가 필요합니다.')
      ..writeln('indexAction: 오류의 생성 링크를 사용하거나 Firebase Console > Firestore > Indexes에서 필요한 인덱스를 생성하세요.');

    final stackTrace = failure.stackTrace;
    if (stackTrace != null) {
      buffer
        ..writeln('stackTrace:')
        ..writeln(stackTrace.toString());
    }

    return buffer.toString().trim();
  }

  static String? extractIndexUrl(Object? error) {
    final source = error is FirebaseException
        ? '${error.message ?? ''} $error'
        : error?.toString() ?? '';
    if (source.isEmpty) return null;

    final matches = RegExp(r'''https?://[^\s<>"']+''').allMatches(source);
    for (final match in matches) {
      var value = match.group(0)?.trim() ?? '';
      while (value.isNotEmpty &&
          (value.endsWith(')') ||
              value.endsWith(']') ||
              value.endsWith('}') ||
              value.endsWith('.') ||
              value.endsWith(','))) {
        value = value.substring(0, value.length - 1);
      }
      if (value.contains('firestore') &&
          (value.contains('create_composite') ||
              value.contains('/indexes'))) {
        return value;
      }
    }
    return null;
  }
}
