import 'sprint_models.dart';

class SprintSchedulingEngine {
  const SprintSchedulingEngine();

  SprintPlacementValidation validatePlacement({
    required DateTime start,
    required DateTime end,
    String? ignoringBlockId,
    String? projectId,
    String? taskId,
    DateTime? notBefore,
    bool allowPastDate = false,
  }) {
    final startDay = _day(start);
    final endDay = _exclusiveEndToInclusiveDay(end);
    final today = _day(DateTime.now());
    final conflicts = <SprintScheduleConflict>[];
    if (endDay.isBefore(startDay)) {
      conflicts.add(
        SprintScheduleConflict(
          id: _conflictId('range', ignoringBlockId, startDay, endDay),
          type: SprintConflictType.invalidDateRange,
          title: '날짜 범위 오류',
          description: '종료일은 시작일보다 빠를 수 없습니다.',
          projectId: projectId,
          taskId: taskId,
          blockId: ignoringBlockId,
        ),
      );
    }
    if (!allowPastDate && startDay.isBefore(today)) {
      conflicts.add(
        SprintScheduleConflict(
          id: _conflictId('past-date', ignoringBlockId, startDay, endDay),
          type: SprintConflictType.pastDate,
          title: '과거 날짜',
          description: '오늘보다 이전 날짜에는 새 업무를 배치할 수 없습니다.',
          projectId: projectId,
          taskId: taskId,
          blockId: ignoringBlockId,
        ),
      );
    }
    if (notBefore != null && startDay.isBefore(_day(notBefore))) {
      conflicts.add(
        SprintScheduleConflict(
          id: _conflictId('project-start', ignoringBlockId, startDay, endDay),
          type: SprintConflictType.beforeProjectStart,
          title: '프로젝트 시작일 이전',
          description: '프로젝트 목표 시작일 이후의 날짜를 선택하세요.',
          projectId: projectId,
          taskId: taskId,
          blockId: ignoringBlockId,
          suggestedStart: _day(notBefore),
        ),
      );
    }
    return SprintPlacementValidation(
      valid: conflicts.isEmpty,
      conflicts: conflicts,
    );
  }



  DateTime _day(DateTime value) {
    return DateTime(value.year, value.month, value.day);
  }

  DateTime _exclusiveEndToInclusiveDay(DateTime value) {
    final normalized = _day(value);
    if (value == normalized) {
      return normalized.subtract(const Duration(days: 1));
    }
    return normalized;
  }

  String _conflictId(
    String prefix,
    String? blockId,
    DateTime start,
    DateTime end,
  ) {
    return <String>[
      prefix,
      blockId ?? 'new',
      '${start.millisecondsSinceEpoch}',
      '${end.millisecondsSinceEpoch}',
    ].join('-');
  }
}
