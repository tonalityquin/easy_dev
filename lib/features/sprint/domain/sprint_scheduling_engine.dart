import 'dart:math' as math;

import 'sprint_models.dart';

class SprintSchedulingEngine {
  const SprintSchedulingEngine({
    this.workdayStartHour = 9,
    this.workdayEndHour = 18,
    this.lunchStartHour = 12,
    this.lunchEndHour = 13,
    this.slotMinutes = 30,
    this.minimumBlockMinutes = 20,
  });

  final int workdayStartHour;
  final int workdayEndHour;
  final int lunchStartHour;
  final int lunchEndHour;
  final int slotMinutes;
  final int minimumBlockMinutes;

  SprintPlacementValidation validatePlacement({
    required DateTime start,
    required DateTime end,
    required List<SprintScheduleBlock> blocks,
    required List<SprintExternalEvent> externalEvents,
    String? ignoringBlockId,
    String? projectId,
    String? taskId,
    DateTime? notBefore,
  }) {
    final conflicts = <SprintScheduleConflict>[];
    final now = DateTime.now();
    if (!start.isAfter(now)) {
      conflicts.add(
        SprintScheduleConflict(
          id: _conflictId(
            'past',
            ignoringBlockId,
            start,
            end,
          ),
          type: SprintConflictType.pastTime,
          title: '과거 시간',
          description: '현재 시각보다 이전에는 새 일정을 배치할 수 없습니다.',
          projectId: projectId,
          taskId: taskId,
          blockId: ignoringBlockId,
        ),
      );
    }
    if (notBefore != null && start.isBefore(notBefore)) {
      conflicts.add(
        SprintScheduleConflict(
          id: _conflictId(
            'project-start',
            ignoringBlockId,
            start,
            end,
            otherStart: notBefore,
          ),
          type: SprintConflictType.beforeProjectStart,
          title: '프로젝트 시작일 이전',
          description:
              '이 프로젝트는 ${_formatDate(notBefore)}부터 일정을 배치할 수 있습니다.',
          projectId: projectId,
          taskId: taskId,
          blockId: ignoringBlockId,
          suggestedStart: notBefore,
        ),
      );
    }
    if (start.weekday > DateTime.friday ||
        start.hour < workdayStartHour ||
        end.hour > workdayEndHour ||
        (end.hour == workdayEndHour && end.minute > 0) ||
        !_sameDay(start, end.subtract(const Duration(microseconds: 1)))) {
      conflicts.add(
        SprintScheduleConflict(
          id: _conflictId(
            'working',
            ignoringBlockId,
            start,
            end,
          ),
          type: SprintConflictType.outsideWorkingHours,
          title: '업무 가능 시간 밖',
          description: '평일 09:00–18:00 안에서 일정을 배치하는 것을 권장합니다.',
          projectId: projectId,
          taskId: taskId,
          blockId: ignoringBlockId,
        ),
      );
    }
    final lunchStart = DateTime(
      start.year,
      start.month,
      start.day,
      lunchStartHour,
    );
    final lunchEnd = DateTime(
      start.year,
      start.month,
      start.day,
      lunchEndHour,
    );
    if (_overlaps(start, end, lunchStart, lunchEnd)) {
      conflicts.add(
        SprintScheduleConflict(
          id: _conflictId(
            'lunch',
            ignoringBlockId,
            start,
            end,
          ),
          type: SprintConflictType.lunchBreak,
          title: '점심시간과 겹침',
          description: '12:00–13:00은 자동 배치에서 제외되는 시간입니다.',
          projectId: projectId,
          taskId: taskId,
          blockId: ignoringBlockId,
        ),
      );
    }
    for (final block in blocks) {
      if (block.id == ignoringBlockId ||
          block.status != SprintScheduleBlockStatus.planned) {
        continue;
      }
      if (_overlaps(start, end, block.start, block.end)) {
        conflicts.add(
          SprintScheduleConflict(
            id: _conflictId(
              'internal',
              ignoringBlockId,
              start,
              end,
              otherId: block.id,
              otherStart: block.start,
              otherEnd: block.end,
            ),
            type: SprintConflictType.internalOverlap,
            title: '내부 일정과 겹침',
            description: '같은 시간대에 다른 스프린트 일정이 있습니다.',
            projectId: projectId,
            taskId: taskId,
            blockId: ignoringBlockId,
          ),
        );
      }
    }
    for (final event in externalEvents) {
      if (!event.blocksTime) continue;
      if (_overlaps(start, end, event.start, event.end)) {
        conflicts.add(
          SprintScheduleConflict(
            id: _conflictId(
              'external',
              ignoringBlockId,
              start,
              end,
              otherId: event.id,
              otherStart: event.start,
              otherEnd: event.end,
            ),
            type: SprintConflictType.externalCalendar,
            title: 'Google 일정과 겹침',
            description: event.title,
            projectId: projectId,
            taskId: taskId,
            blockId: ignoringBlockId,
            externalEventId: event.id,
          ),
        );
      }
    }
    return SprintPlacementValidation(
      valid: conflicts.isEmpty,
      conflicts: conflicts,
    );
  }

  DateTime findNextAvailableStart({
    required DateTime anchor,
    required int durationMinutes,
    required List<SprintScheduleBlock> blocks,
    required List<SprintExternalEvent> externalEvents,
    Set<String> ignoredBlockIds = const <String>{},
    DateTime? notBefore,
  }) {
    final safeDuration = math.max(minimumBlockMinutes, durationMinutes);
    var effectiveAnchor = anchor;
    if (notBefore != null && effectiveAnchor.isBefore(notBefore)) {
      effectiveAnchor = notBefore;
    }
    var cursor = ceilToSlot(effectiveAnchor);
    if (!cursor.isAfter(DateTime.now())) {
      cursor = ceilToSlot(DateTime.now().add(const Duration(minutes: 1)));
      if (notBefore != null && cursor.isBefore(notBefore)) {
        cursor = ceilToSlot(notBefore);
      }
    }
    for (var dayOffset = 0; dayOffset < 370; dayOffset++) {
      if (cursor.weekday > DateTime.friday) {
        cursor = _nextWorkdayStart(cursor);
        continue;
      }
      final workStart = DateTime(
        cursor.year,
        cursor.month,
        cursor.day,
        workdayStartHour,
      );
      final workEnd = DateTime(
        cursor.year,
        cursor.month,
        cursor.day,
        workdayEndHour,
      );
      if (cursor.isBefore(workStart)) cursor = workStart;
      if (!cursor.isBefore(workEnd)) {
        cursor = _nextWorkdayStart(cursor.add(const Duration(days: 1)));
        continue;
      }
      final lunchStart = DateTime(
        cursor.year,
        cursor.month,
        cursor.day,
        lunchStartHour,
      );
      final lunchEnd = DateTime(
        cursor.year,
        cursor.month,
        cursor.day,
        lunchEndHour,
      );
      while (cursor.isBefore(workEnd)) {
        final end = cursor.add(Duration(minutes: safeDuration));
        if (end.isAfter(workEnd)) break;
        if (_overlaps(cursor, end, lunchStart, lunchEnd)) {
          cursor = lunchEnd;
          continue;
        }
        final internalBusy = blocks.any((block) {
          return !ignoredBlockIds.contains(block.id) &&
              block.status == SprintScheduleBlockStatus.planned &&
              _overlaps(cursor, end, block.start, block.end);
        });
        final externalBusy = externalEvents.any((event) {
          return event.blocksTime &&
              _overlaps(cursor, end, event.start, event.end);
        });
        if (!internalBusy && !externalBusy) return cursor;
        cursor = cursor.add(Duration(minutes: slotMinutes));
      }
      cursor = _nextWorkdayStart(cursor.add(const Duration(days: 1)));
    }
    return cursor;
  }

  List<SprintScheduleConflict> detectConflicts({
    required List<SprintScheduleBlock> blocks,
    required List<SprintTask> tasks,
    required List<SprintExternalEvent> externalEvents,
    Map<String, DateTime> projectStartBounds = const <String, DateTime>{},
  }) {
    final conflicts = <SprintScheduleConflict>[];
    for (final block in blocks) {
      if (block.status != SprintScheduleBlockStatus.planned) continue;
      SprintTask? task;
      for (final candidate in tasks) {
        if (candidate.id == block.taskId) {
          task = candidate;
          break;
        }
      }
      if (task == null ||
          task.state == SprintTaskState.completed ||
          task.state == SprintTaskState.cancelled) {
        continue;
      }
      final notBefore = task.projectId == null
          ? null
          : projectStartBounds[task.projectId!];
      final validation = validatePlacement(
        start: block.start,
        end: block.end,
        blocks: blocks,
        externalEvents: externalEvents,
        ignoringBlockId: block.id,
        projectId: task.projectId,
        taskId: task.id,
        notBefore: notBefore,
      );
      for (final conflict in validation.conflicts) {
        final suggestion = findNextAvailableStart(
          anchor: block.start,
          durationMinutes: block.durationMinutes,
          blocks: blocks,
          externalEvents: externalEvents,
          ignoredBlockIds: <String>{block.id},
          notBefore: notBefore,
        );
        conflicts.add(
          SprintScheduleConflict(
            id: conflict.id,
            type: conflict.type,
            title: conflict.title,
            description: conflict.description,
            projectId: conflict.projectId,
            taskId: conflict.taskId,
            blockId: conflict.blockId,
            externalEventId: conflict.externalEventId,
            suggestedStart: suggestion,
          ),
        );
      }
    }
    return conflicts;
  }

  DateTime ceilToSlot(DateTime value) {
    final remainder = value.minute % slotMinutes;
    final hasSubMinute = value.second != 0 ||
        value.millisecond != 0 ||
        value.microsecond != 0;
    final addMinutes = remainder == 0
        ? (hasSubMinute ? slotMinutes : 0)
        : slotMinutes - remainder;
    return DateTime(
      value.year,
      value.month,
      value.day,
      value.hour,
      value.minute,
    ).add(Duration(minutes: addMinutes));
  }

  DateTime _nextWorkdayStart(DateTime value) {
    var date = DateTime(
      value.year,
      value.month,
      value.day,
      workdayStartHour,
    );
    while (date.weekday > DateTime.friday) {
      date = date.add(const Duration(days: 1));
    }
    return date;
  }

  bool _sameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  bool _overlaps(
    DateTime firstStart,
    DateTime firstEnd,
    DateTime secondStart,
    DateTime secondEnd,
  ) {
    return firstStart.isBefore(secondEnd) && secondStart.isBefore(firstEnd);
  }

  String _formatDate(DateTime value) {
    return '${value.year}년 ${value.month}월 ${value.day}일';
  }

  String _conflictId(
    String prefix,
    String? blockId,
    DateTime start,
    DateTime end, {
    String? otherId,
    DateTime? otherStart,
    DateTime? otherEnd,
  }) {
    return <String>[
      prefix,
      blockId ?? 'new',
      '${start.millisecondsSinceEpoch}',
      '${end.millisecondsSinceEpoch}',
      otherId ?? '',
      '${otherStart?.millisecondsSinceEpoch ?? 0}',
      '${otherEnd?.millisecondsSinceEpoch ?? 0}',
    ].join('-');
  }
}
