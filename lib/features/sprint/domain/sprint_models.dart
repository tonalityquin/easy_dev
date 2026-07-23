import 'package:flutter/material.dart';

enum SprintTaskState {
  blocked,
  ready,
  scheduled,
  completed,
  cancelled,
}

enum SprintTaskPriority {
  high,
  normal,
  low,
}

enum SprintPlacementMode {
  automatic,
  manual,
}

enum SprintCalendarConnectionState {
  notConnected,
  cached,
  reauthenticationRequired,
  switching,
  syncing,
  connected,
  failed,
}

enum SprintCalendarProfileRole {
  primary,
  secondary,
}

enum SprintGoogleSyncState {
  none,
  pendingCreate,
  pendingUpdate,
  pendingDelete,
  synced,
  failed,
}

enum SprintPostponeType {
  tomorrow,
  nextWeek,
}

enum SprintWorkspaceScopeType {
  all,
  project,
}

enum SprintProjectStatus {
  active,
  completed,
  archived,
}

enum SprintScheduleBlockStatus {
  planned,
  executed,
  skipped,
  cancelled,
}

enum SprintConflictType {
  pastDate,
  invalidDateRange,
  beforeProjectStart,
  afterProjectTargetDate,
  targetDateRisk,
}

enum SprintConflictResolutionType {
  moved,
  kept,
  adjusted,
}

enum SprintActivityEventType {
  projectCreated,
  projectUpdated,
  projectCompleted,
  projectArchived,
  projectReopened,
  taskCreated,
  taskUpdated,
  taskCancelled,
  taskDeleted,
  taskCompleted,
  taskPostponed,
  blockCreated,
  blockMoved,
  blockResized,
  blockUnscheduled,
  conflictResolved,
}


class SprintGoogleAccount {
  SprintGoogleAccount({
    required this.id,
    this.googleUserId,
    required this.email,
    required this.displayName,
    this.requiresReauthentication = false,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  final String id;
  String? googleUserId;
  String email;
  String displayName;
  bool requiresReauthentication;
  DateTime createdAt;
  DateTime updatedAt;

  String get normalizedEmail => email.trim().toLowerCase();
}

class SprintCalendarProfile {
  SprintCalendarProfile({
    required this.id,
    required this.accountId,
    required this.calendarId,
    required this.label,
    this.role = SprintCalendarProfileRole.secondary,
    this.locked = false,
    this.enabled = true,
    this.sortOrder = 0,
    this.lastSyncedAt,
    this.lastSyncError,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  final String id;
  final String accountId;
  SprintCalendarProfileRole role;
  String calendarId;
  String label;
  bool locked;
  bool enabled;
  int sortOrder;
  DateTime? lastSyncedAt;
  String? lastSyncError;
  DateTime createdAt;
  DateTime updatedAt;

  bool get isPrimary => role == SprintCalendarProfileRole.primary;
  bool get isSecondary => role == SprintCalendarProfileRole.secondary;
}

class SprintWorkspaceScope {
  const SprintWorkspaceScope._({
    required this.type,
    this.projectId,
  });

  const SprintWorkspaceScope.all()
      : this._(type: SprintWorkspaceScopeType.all);

  const SprintWorkspaceScope.project(String projectId)
      : this._(
          type: SprintWorkspaceScopeType.project,
          projectId: projectId,
        );

  final SprintWorkspaceScopeType type;
  final String? projectId;

  String get storageValue {
    switch (type) {
      case SprintWorkspaceScopeType.all:
        return 'all';
      case SprintWorkspaceScopeType.project:
        return 'project:${projectId ?? ''}';
    }
  }

  static SprintWorkspaceScope fromStorageValue(String? value) {
    final normalized = value?.trim() ?? '';
    if (normalized == 'unassigned') {
      return const SprintWorkspaceScope.all();
    }
    if (normalized.startsWith('project:')) {
      final projectId = normalized.substring('project:'.length).trim();
      if (projectId.isNotEmpty) {
        return SprintWorkspaceScope.project(projectId);
      }
    }
    return const SprintWorkspaceScope.all();
  }

  @override
  bool operator ==(Object other) {
    return other is SprintWorkspaceScope &&
        other.type == type &&
        other.projectId == projectId;
  }

  @override
  int get hashCode => Object.hash(type, projectId);
}

const Map<String, IconData> sprintProjectIcons = <String, IconData>{
  'folder': Icons.folder_rounded,
  'rocket': Icons.rocket_launch_rounded,
  'school': Icons.school_rounded,
  'fitness': Icons.fitness_center_rounded,
  'work': Icons.work_rounded,
  'target': Icons.track_changes_rounded,
};

class SprintProject {
  SprintProject({
    required this.id,
    required this.name,
    required this.iconKey,
    this.targetStartDate,
    this.targetDate,
    this.custom = true,
    this.status = SprintProjectStatus.active,
    this.googleColorId = '',
    this.calendarSyncEnabled = true,
    DateTime? createdAt,
    this.completedAt,
    this.archivedAt,
    this.reopenedAt,
  }) : createdAt = createdAt ?? DateTime.now();

  final String id;
  String name;
  String iconKey;
  DateTime? targetStartDate;
  DateTime? targetDate;
  final bool custom;
  SprintProjectStatus status;
  String googleColorId;
  bool calendarSyncEnabled;
  DateTime createdAt;
  DateTime? completedAt;
  DateTime? archivedAt;
  DateTime? reopenedAt;

  IconData get icon => sprintProjectIcons[iconKey] ?? Icons.folder_rounded;
  bool get isActive => status == SprintProjectStatus.active;
  bool get isCompleted => status == SprintProjectStatus.completed;
  bool get isArchived => status == SprintProjectStatus.archived;
  bool get isIndefinite => targetStartDate == null && targetDate == null;

  bool get hasNotStarted {
    final start = targetStartDate;
    if (start == null) return false;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final startDay = DateTime(start.year, start.month, start.day);
    return startDay.isAfter(today);
  }

  int get daysUntilStart {
    final start = targetStartDate;
    if (start == null) return 0;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final startDay = DateTime(start.year, start.month, start.day);
    return startDay.isAfter(today) ? startDay.difference(today).inDays : 0;
  }
}

class SprintTask {
  SprintTask({
    required this.id,
    required this.title,
    this.description = '',
    required this.projectId,
    required this.priority,
    required this.startDate,
    required this.endDate,
    required this.order,
    required this.state,
    this.placementMode = SprintPlacementMode.automatic,
    this.googleEventId,
    this.googleCalendarId,
    this.googleCalendarProfileId,
    this.googleSyncState = SprintGoogleSyncState.none,
    this.googleSyncError,
    this.deleteAfterSync = false,
  });

  final String id;
  String title;
  String description;
  String? projectId;
  SprintTaskPriority priority;
  DateTime startDate;
  DateTime endDate;
  int order;
  SprintTaskState state;
  SprintPlacementMode placementMode;
  String? googleEventId;
  String? googleCalendarId;
  String? googleCalendarProfileId;
  SprintGoogleSyncState googleSyncState;
  String? googleSyncError;
  bool deleteAfterSync;

  bool get allDay => true;
  bool get hasGoogleEvent =>
      googleEventId != null && googleEventId!.trim().isNotEmpty;
  bool get hasPendingGoogleSync =>
      googleSyncState == SprintGoogleSyncState.pendingCreate ||
      googleSyncState == SprintGoogleSyncState.pendingUpdate ||
      googleSyncState == SprintGoogleSyncState.pendingDelete ||
      googleSyncState == SprintGoogleSyncState.failed;
  int get durationDays => endDate.difference(startDate).inDays + 1;

  bool spans(DateTime date) {
    final day = DateTime(date.year, date.month, date.day);
    final start = DateTime(startDate.year, startDate.month, startDate.day);
    final end = DateTime(endDate.year, endDate.month, endDate.day);
    return !day.isBefore(start) && !day.isAfter(end);
  }
}

class SprintScheduleBlock {
  SprintScheduleBlock({
    required this.id,
    required this.taskId,
    required this.start,
    required this.end,
    this.allDay = true,
    this.completed = false,
    this.status = SprintScheduleBlockStatus.planned,
    this.locked = false,
  });

  final String id;
  final String taskId;
  DateTime start;
  DateTime end;
  bool allDay;
  bool completed;
  SprintScheduleBlockStatus status;
  bool locked;

  DateTime get startDate => DateTime(start.year, start.month, start.day);
  DateTime get endDate => DateTime(
        end.subtract(const Duration(days: 1)).year,
        end.subtract(const Duration(days: 1)).month,
        end.subtract(const Duration(days: 1)).day,
      );

  bool spans(DateTime date) {
    final day = DateTime(date.year, date.month, date.day);
    return !day.isBefore(startDate) && !day.isAfter(endDate);
  }
}

class SprintExternalEvent {
  SprintExternalEvent({
    required this.id,
    required this.googleEventId,
    required this.calendarProfileId,
    required this.title,
    required this.start,
    required this.end,
    required this.allDay,
    required this.blocksTime,
    this.sourceUrl,
    this.colorId,
    this.managedBySprint = false,
    this.linkedTaskId,
    this.linkedProjectId,
  });

  final String id;
  final String googleEventId;
  final String calendarProfileId;
  final String title;
  final DateTime start;
  final DateTime end;
  final bool allDay;
  final bool blocksTime;
  final String? sourceUrl;
  final String? colorId;
  final bool managedBySprint;
  final String? linkedTaskId;
  final String? linkedProjectId;
}

class SprintAttentionItem {
  SprintAttentionItem({
    required this.id,
    required this.title,
    required this.description,
    required this.projectId,
    this.taskId,
    this.blockId,
    this.conflictType,
    this.suggestedStart,
  });

  final String id;
  final String title;
  final String description;
  final String? projectId;
  final String? taskId;
  final String? blockId;
  final SprintConflictType? conflictType;
  final DateTime? suggestedStart;
}

class SprintScheduleConflict {
  const SprintScheduleConflict({
    required this.id,
    required this.type,
    required this.title,
    required this.description,
    this.projectId,
    this.taskId,
    this.blockId,
    this.externalEventId,
    this.suggestedStart,
  });

  final String id;
  final SprintConflictType type;
  final String title;
  final String description;
  final String? projectId;
  final String? taskId;
  final String? blockId;
  final String? externalEventId;
  final DateTime? suggestedStart;
}

class SprintConflictResolution {
  const SprintConflictResolution({
    required this.id,
    required this.conflictKey,
    required this.type,
    required this.resolvedAt,
    this.blockId,
  });

  final String id;
  final String conflictKey;
  final SprintConflictResolutionType type;
  final DateTime resolvedAt;
  final String? blockId;
}

class SprintActivityEvent {
  const SprintActivityEvent({
    required this.id,
    required this.type,
    required this.occurredAt,
    this.projectId,
    this.taskId,
    this.blockId,
    this.payload = const <String, String>{},
  });

  final String id;
  final SprintActivityEventType type;
  final DateTime occurredAt;
  final String? projectId;
  final String? taskId;
  final String? blockId;
  final Map<String, String> payload;
}

class SprintProjectReport {
  const SprintProjectReport({
    required this.id,
    required this.projectId,
    required this.completedAt,
    required this.completedTaskCount,
    required this.cancelledTaskCount,
    required this.postponeCount,
    required this.conflictCount,
    required this.resolvedConflictCount,
    required this.targetDeltaDays,
    this.totalTaskCount = 0,
    this.highPriorityCompletedCount = 0,
    this.onTimeCompletedCount = 0,
    this.overdueCompletedCount = 0,
    this.reviewNote,
  });

  final String id;
  final String projectId;
  final DateTime completedAt;
  final int totalTaskCount;
  final int completedTaskCount;
  final int cancelledTaskCount;
  final int highPriorityCompletedCount;
  final int onTimeCompletedCount;
  final int overdueCompletedCount;
  final int postponeCount;
  final int conflictCount;
  final int resolvedConflictCount;
  final int targetDeltaDays;
  final String? reviewNote;
}

class SprintPlacementValidation {
  const SprintPlacementValidation({
    required this.valid,
    required this.conflicts,
  });

  final bool valid;
  final List<SprintScheduleConflict> conflicts;
}

class SprintTaskCreationPreview {
  const SprintTaskCreationPreview({
    required this.title,
    required this.description,
    required this.projectId,
    required this.calendarProfileId,
    required this.priority,
    required this.startDate,
    required this.endDate,
    required this.conflicts,
  });

  final String title;
  final String description;
  final String projectId;
  final String? calendarProfileId;
  final SprintTaskPriority priority;
  final DateTime startDate;
  final DateTime endDate;
  final List<SprintScheduleConflict> conflicts;

  bool get hasConflicts => conflicts.isNotEmpty;
  bool get hasHardConflict => conflicts.any(
        (conflict) => conflict.type == SprintConflictType.invalidDateRange,
      );
}

class SprintOperationResult {
  const SprintOperationResult({
    required this.success,
    required this.message,
    this.conflicts = const <SprintScheduleConflict>[],
  });

  final bool success;
  final String message;
  final List<SprintScheduleConflict> conflicts;
}

class SprintBulkDeleteResult {
  const SprintBulkDeleteResult({
    required this.requestedCount,
    required this.deletedCount,
    required this.pendingRemoteDeleteCount,
    required this.skippedCount,
  });

  final int requestedCount;
  final int deletedCount;
  final int pendingRemoteDeleteCount;
  final int skippedCount;

  int get processedCount => deletedCount + pendingRemoteDeleteCount;
}

class SprintDayLoad {
  SprintDayLoad({
    required this.date,
    required this.taskCount,
    required this.highPriorityCount,
    required this.priorityScore,
  });

  final DateTime date;
  final int taskCount;
  final int highPriorityCount;
  final int priorityScore;

  double get ratio => (priorityScore / 12).clamp(0, 1).toDouble();
  bool get overloaded => taskCount >= 7 || priorityScore >= 12;
}

class SprintProjectSummary {
  SprintProjectSummary({
    required this.project,
    required this.totalTaskCount,
    required this.completedTaskCount,
    required this.todayTaskCount,
    required this.attentionCount,
    required this.highPriorityRemainingCount,
    required this.plannedCompletion,
    required this.workload,
    required this.todayTasks,
    required this.pathTasks,
  });

  final SprintProject project;
  final int totalTaskCount;
  final int completedTaskCount;
  final int todayTaskCount;
  final int attentionCount;
  final int highPriorityRemainingCount;
  final DateTime plannedCompletion;
  final List<SprintDayLoad> workload;
  final List<SprintTask> todayTasks;
  final List<SprintTask> pathTasks;

  double get progressRatio {
    if (totalTaskCount <= 0) return 0;
    return (completedTaskCount / totalTaskCount).clamp(0, 1).toDouble();
  }

  bool get isLate {
    final target = project.targetDate;
    if (target == null) return false;
    final estimateDay = DateTime(
      plannedCompletion.year,
      plannedCompletion.month,
      plannedCompletion.day,
    );
    final targetDay = DateTime(target.year, target.month, target.day);
    return estimateDay.isAfter(targetDay);
  }

  int get delayDays {
    final target = project.targetDate;
    if (target == null || !isLate) return 0;
    final estimateDay = DateTime(
      plannedCompletion.year,
      plannedCompletion.month,
      plannedCompletion.day,
    );
    final targetDay = DateTime(target.year, target.month, target.day);
    return estimateDay.difference(targetDay).inDays;
  }
}

class SprintTimelineEntry {
  SprintTimelineEntry.task({
    required this.block,
    required this.task,
    required this.project,
  })  : externalEvent = null,
        isExternal = false;

  SprintTimelineEntry.external({
    required this.externalEvent,
  })  : block = null,
        task = null,
        project = null,
        isExternal = true;

  final SprintScheduleBlock? block;
  final SprintTask? task;
  final SprintProject? project;
  final SprintExternalEvent? externalEvent;
  final bool isExternal;

  DateTime get start {
    if (isExternal) return externalEvent!.start;
    return block!.start;
  }

  DateTime get end {
    if (isExternal) return externalEvent!.end;
    return block!.end;
  }
}
