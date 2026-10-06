import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../app/utils/status_dialog.dart';
import '../../selector/application/dev_auth.dart';

enum SensorDebugStatusTone {
  info,
  progress,
  success,
  warning,
  error,
}

@immutable
class SensorDebugStatusEvent {
  const SensorDebugStatusEvent({
    required this.sequence,
    required this.source,
    required this.event,
    required this.title,
    required this.detail,
    required this.tone,
    required this.sticky,
  });

  final int sequence;
  final String source;
  final String event;
  final String title;
  final String? detail;
  final SensorDebugStatusTone tone;
  final bool sticky;
}

class SensorDebugTrace {
  SensorDebugTrace._();

  static const int _maxLines = 800;
  static final List<String> _lines = <String>[];
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);
  static final ValueNotifier<SensorDebugStatusEvent?> currentStatus =
      ValueNotifier<SensorDebugStatusEvent?>(null);
  static bool _dialogShowing = false;
  static int _statusSequence = 0;

  static List<String> get lines => List<String>.unmodifiable(_lines);

  static void clear() {
    _lines.clear();
    currentStatus.value = null;
    revision.value++;
  }

  static void record(
    String source,
    String event, [
    Map<String, Object?> details = const <String, Object?>{},
  ]) {
    final buffer = StringBuffer()
      ..write('[$source] ')
      ..write(DateTime.now().toIso8601String())
      ..write(' event=')
      ..write(event);
    for (final entry in details.entries) {
      final value = entry.value;
      if (value == null) continue;
      buffer
        ..write(' ')
        ..write(entry.key)
        ..write('=')
        ..write(value);
    }
    final line = buffer.toString();
    _lines.add(line);
    if (_lines.length > _maxLines) {
      _lines.removeRange(0, _lines.length - _maxLines);
    }
    revision.value++;
    debugPrint(line);
  }

  static void publishStatus(
    String source,
    String event, {
    required String title,
    String? detail,
    SensorDebugStatusTone tone = SensorDebugStatusTone.info,
    bool sticky = false,
    Map<String, Object?> details = const <String, Object?>{},
  }) {
    final normalizedDetail = detail?.trim();
    final sequence = ++_statusSequence;
    record(
      source,
      event,
      <String, Object?>{
        ...details,
        'statusSequence': sequence,
        'statusTitle': title,
        'statusDetail': normalizedDetail == null || normalizedDetail.isEmpty
            ? null
            : normalizedDetail,
        'statusTone': tone.name,
        'statusSticky': sticky,
      },
    );
    currentStatus.value = SensorDebugStatusEvent(
      sequence: sequence,
      source: source,
      event: event,
      title: title,
      detail: normalizedDetail == null || normalizedDetail.isEmpty
          ? null
          : normalizedDetail,
      tone: tone,
      sticky: sticky,
    );
  }

  static String get debugPrintCode {
    if (_lines.isEmpty) {
      return 'debugPrint(${jsonEncode('[Sensor] 기록된 로그가 없습니다.')});';
    }
    return _lines
        .map((line) => 'debugPrint(${jsonEncode(line)});')
        .join('\n');
  }

  static Future<void> showStatusDialog(
    BuildContext context, {
    String title = '센서 개발자 상태',
  }) async {
    if (_dialogShowing || !context.mounted) return;
    final enabled = await DevAuth.isDevModeEnabled();
    if (!enabled || !context.mounted || _dialogShowing) return;
    _dialogShowing = true;
    try {
      final status = currentStatus.value;
      record(
        'SensorDebugTrace',
        'status_dialog_opened',
        <String, Object?>{
          'lineCount': _lines.length,
          'statusSequence': status?.sequence,
          'statusSource': status?.source,
          'statusEvent': status?.event,
          'statusTone': status?.tone.name,
        },
      );
      final description =
          _lines.isEmpty ? '기록된 센서 로그가 없습니다.' : _lines.join('\n');
      final copyCode = debugPrintCode;
      await StatusDialog.showSuccess(
        context,
        title: title,
        description: description,
        copyText: copyCode,
        copyButtonLabel: 'debugPrint 코드 복사',
        visibleDuration: Duration.zero,
        useCommonUi: true,
        awaitManualClose: true,
      );
    } finally {
      _dialogShowing = false;
    }
  }
}
