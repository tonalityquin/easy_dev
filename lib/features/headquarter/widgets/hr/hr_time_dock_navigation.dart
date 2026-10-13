import 'package:flutter/material.dart';



class HrTimeDockDebugLog {
  HrTimeDockDebugLog._();

  static const int _maxLines = 120;
  static final List<String> _lines = <String>[];

  static void record(String message) {
    final normalized = message.trim();
    if (normalized.isEmpty) return;
    final line = '[HrTimeDockCoordinator] $normalized';
    _lines.add(line);
    if (_lines.length > _maxLines) {
      _lines.removeRange(0, _lines.length - _maxLines);
    }
    debugPrint(line);
  }

  static List<String> snapshot() => List<String>.unmodifiable(_lines);
}

enum HrTimeDockTarget {
  attendance,
  breakTime,
}

class HrTimeDockSwitchRequest {
  const HrTimeDockSwitchRequest({
    required this.target,
    required this.focusedMonth,
  });

  final HrTimeDockTarget target;
  final DateTime focusedMonth;
}

enum HrTimePendingDecision {
  cancel,
  discard,
  save,
}

DateTime normalizeHrTimeMonth(DateTime value) => DateTime(value.year, value.month, 1);

Future<HrTimePendingDecision?> showHrTimePendingChangesDialog(
  BuildContext context, {
  required int dirtyCount,
  required String actionLabel,
}) {
  return showDialog<HrTimePendingDecision>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) {
      final theme = Theme.of(dialogContext);
      return AlertDialog(
        icon: const Icon(Icons.edit_calendar_rounded),
        title: const Text('저장하지 않은 변경사항'),
        content: Text(
          '변경된 날짜가 $dirtyCount건 있습니다. $actionLabel 전에 처리 방법을 선택해 주세요.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(HrTimePendingDecision.cancel),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(HrTimePendingDecision.discard),
            child: Text(
              actionLabel.contains('이동') ? '버리고 이동' : '버리고 닫기',
              style: TextStyle(color: theme.colorScheme.error),
            ),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(HrTimePendingDecision.save),
            child: Text(
              actionLabel.contains('이동') ? '저장 후 이동' : '저장 후 닫기',
            ),
          ),
        ],
      );
    },
  );
}
