import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:googleapis/calendar/v3.dart' as gcal;

import '../../headquarter/widgets/calendar/google_calendar_service.dart';
import '../data/sprint_database.dart';
import '../domain/sprint_models.dart';
import '../domain/sprint_scheduling_engine.dart';

class SprintModeStore extends ChangeNotifier {
  SprintModeStore({
    GoogleCalendarService? calendarService,
    SprintDatabase? database,
    SprintSchedulingEngine? schedulingEngine,
  })  : _calendarService = calendarService ?? GoogleCalendarService(),
        _database = database ?? SprintDatabase.instance,
        _schedulingEngine = schedulingEngine ?? const SprintSchedulingEngine();

  final GoogleCalendarService _calendarService;
  final SprintDatabase _database;
  final SprintSchedulingEngine _schedulingEngine;
  final List<SprintProject> _projects = <SprintProject>[];
  final List<SprintTask> _tasks = <SprintTask>[];
  final List<SprintScheduleBlock> _blocks = <SprintScheduleBlock>[];
  final List<SprintExternalEvent> _externalEvents = <SprintExternalEvent>[];
  final List<SprintAttentionItem> _attentionItems = <SprintAttentionItem>[];
  final List<SprintProjectReport> _projectReports = <SprintProjectReport>[];
  final List<SprintActivityEvent> _activityEvents = <SprintActivityEvent>[];
  final List<SprintConflictResolution> _conflictResolutions =
      <SprintConflictResolution>[];

  DateTime _selectedDate = _day(DateTime.now());
  SprintWorkspaceScope _workspaceScope = const SprintWorkspaceScope.all();
  bool _weekMode = false;
  SprintCalendarConnectionState _calendarState =
      SprintCalendarConnectionState.notConnected;
  String? _calendarError;
  String? _taskInputError;
  int _sequence = DateTime.now().microsecondsSinceEpoch;
  bool _initialized = false;
  bool _initializing = false;
  bool _accountOperationInProgress = false;
  String _googleCalendarId = 'primary';
  bool _googleCalendarIdLocked = false;
  Future<void> _writeQueue = Future<void>.value();

  List<SprintProject> get projects => List<SprintProject>.unmodifiable(
        _projects.where((project) => project.status == SprintProjectStatus.active),
      );
  List<SprintProject> get allProjects =>
      List<SprintProject>.unmodifiable(_projects);
  List<SprintProject> get completedProjects => List<SprintProject>.unmodifiable(
        _projects.where((project) => project.status == SprintProjectStatus.completed),
      );
  List<SprintProject> get archivedProjects => List<SprintProject>.unmodifiable(
        _projects.where((project) => project.status == SprintProjectStatus.archived),
      );
  List<SprintTask> get tasks => List<SprintTask>.unmodifiable(_tasks);
  List<SprintScheduleBlock> get blocks =>
      List<SprintScheduleBlock>.unmodifiable(_blocks);
  List<SprintExternalEvent> get externalEvents =>
      List<SprintExternalEvent>.unmodifiable(_externalEvents);
  List<SprintAttentionItem> get attentionItems =>
      List<SprintAttentionItem>.unmodifiable(_attentionItems);
  List<SprintProjectReport> get projectReports =>
      List<SprintProjectReport>.unmodifiable(_projectReports);
  List<SprintActivityEvent> get activityEvents =>
      List<SprintActivityEvent>.unmodifiable(_activityEvents);
  List<SprintConflictResolution> get conflictResolutions =>
      List<SprintConflictResolution>.unmodifiable(_conflictResolutions);
  DateTime get selectedDate => _selectedDate;
  SprintWorkspaceScope get workspaceScope => _workspaceScope;
  String? get selectedProjectId =>
      _workspaceScope.type == SprintWorkspaceScopeType.project
          ? _workspaceScope.projectId
          : null;
  bool get weekMode => _weekMode;
  SprintCalendarConnectionState get calendarState => _calendarState;
  String? get calendarError => _calendarError;
  String? get taskInputError => _taskInputError;
  bool get initialized => _initialized;
  bool get initializing => _initializing;
  bool get accountSaving => _accountOperationInProgress;
  bool get accountBusy => _accountOperationInProgress;
  String get googleCalendarId => _googleCalendarId;
  bool get googleCalendarIdLocked => _googleCalendarIdLocked;

  SprintProject? get selectedProject => projectById(selectedProjectId);


  String get scopeLabel {
    switch (_workspaceScope.type) {
      case SprintWorkspaceScopeType.all:
        return '전체 일정';
      case SprintWorkspaceScopeType.project:
        return selectedProject?.name ?? '전체 일정';
    }
  }

  IconData get scopeIcon {
    switch (_workspaceScope.type) {
      case SprintWorkspaceScopeType.all:
        return Icons.dashboard_rounded;
      case SprintWorkspaceScopeType.project:
        return selectedProject?.icon ?? Icons.folder_rounded;
    }
  }

  List<SprintAttentionItem> get currentScopeAttentionItems {
    return _attentionItems.where(_attentionMatchesScope).toList(growable: false);
  }

  Future<void> initialize() async {
    if (_initialized || _initializing) {
      while (_initializing && !_initialized) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      return;
    }
    _initializing = true;
    notifyListeners();
    try {
      final snapshot = await _database.loadSnapshot();
      _projects
        ..clear()
        ..addAll(snapshot.projects);
      _tasks
        ..clear()
        ..addAll(snapshot.tasks);
      _blocks
        ..clear()
        ..addAll(snapshot.blocks);
      _externalEvents
        ..clear()
        ..addAll(snapshot.externalEvents);
      _attentionItems
        ..clear()
        ..addAll(snapshot.attentionItems);
      _projectReports
        ..clear()
        ..addAll(snapshot.projectReports);
      _activityEvents
        ..clear()
        ..addAll(snapshot.activityEvents);
      _conflictResolutions
        ..clear()
        ..addAll(snapshot.conflictResolutions);
      _selectedDate = _day(snapshot.selectedDate);
      _weekMode = snapshot.weekMode;
      _googleCalendarId = snapshot.googleCalendarId;
      _googleCalendarIdLocked = snapshot.googleCalendarIdLocked;
      _calendarState = _externalEvents.isEmpty
          ? SprintCalendarConnectionState.notConnected
          : SprintCalendarConnectionState.connected;
      _workspaceScope = _validatedScope(snapshot.workspaceScope);
      _normalizeTaskStates();
      _refreshAttention();
      _sequence = _nextSequenceValue();
      _initialized = true;
      await _persistNow();
    } finally {
      _initializing = false;
      notifyListeners();
    }
  }

  Future<void> flush() async {
    await _writeQueue;
  }

  Future<SprintProject?> createProject({
    required String name,
    required String iconKey,
    DateTime? targetDate,
  }) async {
    final normalizedName = name.trim();
    if (normalizedName.isEmpty) return null;
    final project = SprintProject(
      id: _newId('project'),
      name: normalizedName,
      iconKey: sprintProjectIcons.containsKey(iconKey) ? iconKey : 'folder',
      targetDate: targetDate == null ? null : _day(targetDate),
      custom: true,
      status: SprintProjectStatus.active,
      createdAt: DateTime.now(),
    );
    _projects.add(project);
    _workspaceScope = SprintWorkspaceScope.project(project.id);
    _recordActivity(
      type: SprintActivityEventType.projectCreated,
      projectId: project.id,
    );
    _refreshAttention();
    notifyListeners();
    await _persistNow();
    return project;
  }

  Future<bool> updateProject({
    required String projectId,
    required String name,
    required String iconKey,
    DateTime? targetDate,
  }) async {
    final project = projectById(projectId);
    final normalizedName = name.trim();
    if (project == null ||
        !project.custom ||
        project.status != SprintProjectStatus.active ||
        normalizedName.isEmpty) {
      return false;
    }
    project
      ..name = normalizedName
      ..iconKey = sprintProjectIcons.containsKey(iconKey) ? iconKey : 'folder'
      ..targetDate = targetDate == null ? null : _day(targetDate);
    _recordActivity(
      type: SprintActivityEventType.projectUpdated,
      projectId: projectId,
    );
    _refreshAttention();
    notifyListeners();
    await _persistNow();
    return true;
  }

  Future<SprintProjectReport?> completeProject({
    required String projectId,
    String? reviewNote,
    bool cancelRemaining = false,
    bool acceptConflicts = false,
  }) async {
    final project = projectById(projectId);
    if (project == null || project.status != SprintProjectStatus.active) {
      return null;
    }
    final unresolvedConflictCount = conflictsForProject(projectId).length;
    if (unresolvedConflictCount > 0 && !acceptConflicts) return null;
    final projectTasks = _tasks
        .where((task) =>
            task.projectId == projectId &&
            task.state != SprintTaskState.cancelled)
        .toList(growable: false);
    final remainingTasks = projectTasks.where((task) {
      return task.state != SprintTaskState.completed &&
          task.state != SprintTaskState.cancelled;
    }).toList(growable: false);
    if (remainingTasks.isNotEmpty && !cancelRemaining) return null;
    for (final task in remainingTasks) {
      task.state = SprintTaskState.cancelled;
      for (final block in _blocks.where((block) => block.taskId == task.id)) {
        if (block.status == SprintScheduleBlockStatus.planned) {
          block.status = SprintScheduleBlockStatus.cancelled;
        }
      }
      _recordActivity(
        type: SprintActivityEventType.taskCancelled,
        projectId: projectId,
        taskId: task.id,
        payload: const <String, String>{'source': 'project_complete'},
      );
    }
    final completedAt = DateTime.now();
    project
      ..status = SprintProjectStatus.completed
      ..completedAt = completedAt
      ..archivedAt = null;
    final report = _buildProjectReport(
      project: project,
      completedAt: completedAt,
      reviewNote: reviewNote?.trim().isEmpty == true ? null : reviewNote?.trim(),
      conflictCount: unresolvedConflictCount,
    );
    _projectReports.add(report);
    _recordActivity(
      type: SprintActivityEventType.projectCompleted,
      projectId: projectId,
      payload: <String, String>{'reportId': report.id},
    );
    if (_workspaceScope.projectId == projectId) {
      _workspaceScope = const SprintWorkspaceScope.all();
    }
    _refreshAttention();
    notifyListeners();
    await _persistNow();
    return report;
  }

  Future<bool> archiveProject(String projectId) async {
    final project = projectById(projectId);
    if (project == null || project.status != SprintProjectStatus.completed) {
      return false;
    }
    project
      ..status = SprintProjectStatus.archived
      ..archivedAt = DateTime.now();
    _recordActivity(
      type: SprintActivityEventType.projectArchived,
      projectId: projectId,
    );
    if (_workspaceScope.projectId == projectId) {
      _workspaceScope = const SprintWorkspaceScope.all();
    }
    _refreshAttention();
    notifyListeners();
    await _persistNow();
    return true;
  }

  Future<bool> reopenProject(String projectId) async {
    final project = projectById(projectId);
    if (project == null || project.status == SprintProjectStatus.active) {
      return false;
    }
    project
      ..status = SprintProjectStatus.active
      ..reopenedAt = DateTime.now()
      ..archivedAt = null;
    _workspaceScope = SprintWorkspaceScope.project(projectId);
    _recordActivity(
      type: SprintActivityEventType.projectReopened,
      projectId: projectId,
    );
    _refreshAttention();
    notifyListeners();
    await _persistNow();
    return true;
  }

  SprintProjectReport? latestReportFor(String projectId) {
    final reports = _projectReports
        .where((report) => report.projectId == projectId)
        .toList(growable: false)
      ..sort((a, b) => b.completedAt.compareTo(a.completedAt));
    return reports.isEmpty ? null : reports.first;
  }

  Future<bool> deleteProject(String projectId) async {
    final project = projectById(projectId);
    if (project == null || !project.custom) return false;
    final taskIds = _tasks
        .where((task) => task.projectId == projectId)
        .map((task) => task.id)
        .toSet();
    final nextScope = _workspaceScope.type == SprintWorkspaceScopeType.project &&
            _workspaceScope.projectId == projectId
        ? const SprintWorkspaceScope.all()
        : _workspaceScope;
    final snapshot = SprintDatabaseSnapshot(
      projects: _projects
          .where((value) => value.id != projectId)
          .toList(growable: false),
      tasks: _tasks
          .where((task) => !taskIds.contains(task.id))
          .toList(growable: false),
      blocks: _blocks
          .where((block) => !taskIds.contains(block.taskId))
          .toList(growable: false),
      externalEvents: List<SprintExternalEvent>.from(_externalEvents),
      attentionItems: _attentionItems
          .where((item) => item.projectId != projectId)
          .toList(growable: false),
      projectReports: _projectReports
          .where((report) => report.projectId != projectId)
          .toList(growable: false),
      activityEvents: _activityEvents
          .where((event) => event.projectId != projectId)
          .toList(growable: false),
      conflictResolutions: _conflictResolutions
          .where((resolution) =>
              resolution.blockId == null ||
              !_blocks.any((block) =>
                  block.id == resolution.blockId &&
                  taskIds.contains(block.taskId)))
          .toList(growable: false),
      workspaceScope: nextScope,
      selectedDate: _selectedDate,
      weekMode: _weekMode,
      googleCalendarId: _googleCalendarId,
      googleCalendarIdLocked: _googleCalendarIdLocked,
    );
    _writeQueue = _writeQueue
        .catchError((_) {})
        .then((_) => _database.replaceSnapshot(snapshot));
    await _writeQueue;
    _blocks.removeWhere((block) => taskIds.contains(block.taskId));
    _tasks.removeWhere((task) => taskIds.contains(task.id));
    _attentionItems.removeWhere((item) => item.projectId == projectId);
    _projectReports.removeWhere((report) => report.projectId == projectId);
    _activityEvents.removeWhere((event) => event.projectId == projectId);
    _conflictResolutions.removeWhere((resolution) =>
        resolution.blockId != null &&
        !_blocks.any((block) => block.id == resolution.blockId));
    _projects.removeWhere((value) => value.id == projectId);
    _workspaceScope = nextScope;
    _refreshAttention();
    notifyListeners();
    return true;
  }

  Future<void> saveGoogleCalendarAccount({
    required String calendarId,
    required bool locked,
  }) async {
    if (_accountOperationInProgress) {
      throw StateError('account_operation_in_progress');
    }
    _accountOperationInProgress = true;
    notifyListeners();
    try {
      await _saveGoogleCalendarAccountInternal(
        calendarId: calendarId,
        locked: locked,
      );
    } finally {
      _accountOperationInProgress = false;
      notifyListeners();
    }
  }

  Future<void> saveGoogleCalendarAccountAndSync({
    required String calendarId,
    required bool locked,
  }) async {
    if (_accountOperationInProgress) return;
    _accountOperationInProgress = true;
    notifyListeners();
    try {
      await _saveGoogleCalendarAccountInternal(
        calendarId: calendarId,
        locked: locked,
      );
      await _syncGoogleCalendarInternal();
    } finally {
      _accountOperationInProgress = false;
      notifyListeners();
    }
  }

  Future<void> _saveGoogleCalendarAccountInternal({
    required String calendarId,
    required bool locked,
  }) async {
    final normalized = normalizeGoogleCalendarId(calendarId);
    if (normalized.isEmpty) {
      throw ArgumentError.value(calendarId, 'calendarId');
    }
    final changed = normalized != _googleCalendarId;
    _googleCalendarId = normalized;
    _googleCalendarIdLocked = locked;
    if (changed) {
      _externalEvents.clear();
      _calendarState = SprintCalendarConnectionState.notConnected;
      _calendarError = null;
      _refreshAttention();
    }
    await _persistNow();
    notifyListeners();
  }

  String normalizeGoogleCalendarId(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return '';
    final uri = Uri.tryParse(trimmed);
    final source = uri?.queryParameters['src'];
    if (source != null && source.trim().isNotEmpty) {
      return Uri.decodeComponent(source).trim();
    }
    return trimmed;
  }

  SprintProject? projectById(String? id) {
    if (id == null) return null;
    for (final project in _projects) {
      if (project.id == id) return project;
    }
    return null;
  }

  SprintTask? taskById(String? id) {
    if (id == null) return null;
    for (final task in _tasks) {
      if (task.id == id) return task;
    }
    return null;
  }

  SprintScheduleBlock? blockById(String? id) {
    if (id == null) return null;
    for (final block in _blocks) {
      if (block.id == id) return block;
    }
    return null;
  }

  DateTime normalizeScheduleStart(DateTime value) {
    return _schedulingEngine.ceilToSlot(value);
  }

  bool _taskBelongsToActiveProject(SprintTask task) {
    final project = projectById(task.projectId);
    return project != null && project.status == SprintProjectStatus.active;
  }

  void selectScope(SprintWorkspaceScope scope) {
    final validated = _validatedScope(scope);
    if (_workspaceScope == validated) return;
    _workspaceScope = validated;
    notifyListeners();
    _queuePersist();
  }

  void selectAll() {
    selectScope(const SprintWorkspaceScope.all());
  }

  void selectProject(String projectId) {
    final project = projectById(projectId);
    if (project == null || project.status != SprintProjectStatus.active) return;
    selectScope(SprintWorkspaceScope.project(projectId));
  }

  void selectDate(DateTime date) {
    final next = _day(date);
    if (_sameDay(_selectedDate, next)) return;
    _selectedDate = next;
    notifyListeners();
    _queuePersist();
  }

  void setWeekMode(bool value) {
    if (_weekMode == value) return;
    _weekMode = value;
    notifyListeners();
    _queuePersist();
  }

  List<DateTime> weekDates(DateTime anchor) {
    final date = _day(anchor);
    final monday = date.subtract(Duration(days: date.weekday - 1));
    return List<DateTime>.generate(
      7,
      (index) => monday.add(Duration(days: index)),
      growable: false,
    );
  }

  List<SprintTimelineEntry> timelineFor(DateTime date) {
    final day = _day(date);
    final entries = <SprintTimelineEntry>[];
    for (final block in _blocks) {
      if (block.status == SprintScheduleBlockStatus.cancelled ||
          !_sameDay(block.start, day)) {
        continue;
      }
      final task = taskById(block.taskId);
      if (task == null || task.state == SprintTaskState.cancelled) continue;
      if (!_taskMatchesScope(task)) continue;
      entries.add(
        SprintTimelineEntry.task(
          block: block,
          task: task,
          project: projectById(task.projectId),
        ),
      );
    }
    for (final event in _externalEvents) {
      if (_sameDay(event.start, day) ||
          (event.allDay && _intersectsDay(event.start, event.end, day))) {
        entries.add(SprintTimelineEntry.external(externalEvent: event));
      }
    }
    entries.sort((a, b) => a.start.compareTo(b.start));
    return entries;
  }

  List<SprintTask> unplacedTasks() {
    final placedTaskIds = _blocks
        .where((block) => block.status == SprintScheduleBlockStatus.planned)
        .map((block) => block.taskId)
        .toSet();
    return _tasks.where((task) {
      if (!_taskMatchesScope(task)) return false;
      if (task.state == SprintTaskState.completed ||
          task.state == SprintTaskState.cancelled) {
        return false;
      }
      return !placedTaskIds.contains(task.id);
    }).toList(growable: false);
  }

  SprintProjectSummary summaryFor(String projectId) {
    final project = projectById(projectId);
    if (project == null) {
      throw StateError('project_not_found');
    }
    final projectTasks = _tasks
        .where((task) =>
            task.projectId == projectId &&
            task.state != SprintTaskState.cancelled)
        .toList(growable: false)
      ..sort((a, b) => a.order.compareTo(b.order));
    final totalEstimated = projectTasks.fold<int>(
      0,
      (sum, task) => sum + task.estimatedMinutes,
    );
    final completedEstimated = projectTasks
        .where((task) => task.state == SprintTaskState.completed)
        .fold<int>(0, (sum, task) => sum + task.estimatedMinutes);
    final remaining = projectTasks
        .where((task) => task.state != SprintTaskState.completed)
        .fold<int>(
          0,
          (sum, task) =>
              sum +
              math.max(0, task.estimatedMinutes - task.actualMinutes).toInt(),
        );
    final todayTasks = projectTasks.where((task) {
      return _blocks.any(
        (block) =>
            block.taskId == task.id && _sameDay(block.start, DateTime.now()),
      );
    }).toList(growable: false);
    final attentionCount = _attentionItems
        .where((item) => item.projectId == projectId)
        .length;
    return SprintProjectSummary(
      project: project,
      totalTaskCount: projectTasks.length,
      completedTaskCount: projectTasks
          .where((task) => task.state == SprintTaskState.completed)
          .length,
      todayTaskCount: todayTasks.length,
      attentionCount: attentionCount,
      totalEstimatedMinutes: totalEstimated,
      completedEstimatedMinutes: completedEstimated,
      remainingMinutes: remaining,
      estimatedCompletion: _estimateCompletion(projectId, remaining),
      workload: _workloadFor(projectId),
      todayTasks: todayTasks,
      pathTasks: projectTasks,
    );
  }

  int plannedMinutesFor(DateTime date, String projectId) {
    return _blocks.where((block) {
      final task = taskById(block.taskId);
      return task?.projectId == projectId &&
          task?.state != SprintTaskState.completed &&
          block.status == SprintScheduleBlockStatus.planned &&
          _sameDay(block.start, date);
    }).fold<int>(0, (sum, block) => sum + block.durationMinutes);
  }

  int plannedMinutesForCurrentScope(DateTime date) {
    return _blocks.where((block) {
      final task = taskById(block.taskId);
      return task != null &&
          _taskMatchesScope(task) &&
          task.state != SprintTaskState.completed &&
          block.status == SprintScheduleBlockStatus.planned &&
          _sameDay(block.start, date);
    }).fold<int>(0, (sum, block) => sum + block.durationMinutes);
  }

  SprintPlacementValidation validateBlockPlacement({
    required DateTime start,
    required DateTime end,
    String? blockId,
    String? taskId,
  }) {
    final task = taskById(taskId ?? blockById(blockId)?.taskId);
    return _schedulingEngine.validatePlacement(
      start: start,
      end: end,
      blocks: _blocks,
      externalEvents: _externalEvents,
      ignoringBlockId: blockId,
      projectId: task?.projectId,
      taskId: task?.id,
    );
  }

  DateTime nextAvailableStartForBlock({
    required String blockId,
    required DateTime anchor,
    int? durationMinutes,
  }) {
    final block = blockById(blockId);
    if (block == null) return _schedulingEngine.ceilToSlot(anchor);
    return _schedulingEngine.findNextAvailableStart(
      anchor: anchor,
      durationMinutes: durationMinutes ?? block.durationMinutes,
      blocks: _blocks,
      externalEvents: _externalEvents,
      ignoredBlockIds: <String>{block.id},
    );
  }

  String? preferredTaskProjectId([String? requestedProjectId]) {
    final requested = projectById(requestedProjectId);
    if (requested != null && requested.status == SprintProjectStatus.active) {
      return requested.id;
    }
    final selected = selectedProject;
    if (selected != null && selected.status == SprintProjectStatus.active) {
      return selected.id;
    }
    final activeProjects = projects;
    if (activeProjects.length == 1) {
      return activeProjects.first.id;
    }
    return null;
  }

  DateTime suggestedTaskStart({
    required DateTime date,
    required int durationMinutes,
  }) {
    final day = _day(date);
    final now = DateTime.now();
    final anchor = _sameDay(day, now)
        ? now.add(const Duration(minutes: 10))
        : DateTime(day.year, day.month, day.day, 9);
    final suggested = _schedulingEngine.findNextAvailableStart(
      anchor: anchor,
      durationMinutes: durationMinutes,
      blocks: _blocks,
      externalEvents: _externalEvents,
    );
    if (_sameDay(suggested, day)) {
      return suggested;
    }
    if (_sameDay(day, now)) {
      final fallback = _schedulingEngine.ceilToSlot(
        now.add(const Duration(minutes: 10)),
      );
      if (_sameDay(fallback, day)) return fallback;
      return DateTime(day.year, day.month, day.day, 23, 30);
    }
    return DateTime(day.year, day.month, day.day, 9);
  }

  SprintTaskCreationPreview? previewTaskFromText(
    String rawText, {
    String? projectId,
  }) {
    final raw = rawText.trim();
    _taskInputError = null;
    if (raw.isEmpty) return null;
    final parsed = _parseTask(raw);
    if (parsed.error != null) {
      _taskInputError = parsed.error;
      notifyListeners();
      return null;
    }
    final resolvedProjectId = preferredTaskProjectId(projectId);
    if (resolvedProjectId == null) {
      _taskInputError = projects.isEmpty
          ? '업무를 추가하려면 먼저 프로젝트를 생성하세요.'
          : '업무를 추가할 프로젝트를 선택하세요.';
      notifyListeners();
      return null;
    }
    return _buildTaskCreationPreview(
      title: parsed.title,
      projectId: resolvedProjectId,
      estimatedMinutes: parsed.minutes,
      deadline: parsed.deadline,
      requestedStart: parsed.start,
      explicitStart: parsed.explicitStart,
    );
  }

  SprintTaskCreationPreview? previewTaskDetails({
    required String title,
    required String projectId,
    required int estimatedMinutes,
    required DateTime requestedStart,
    DateTime? deadline,
  }) {
    _taskInputError = null;
    final project = projectById(projectId);
    if (title.trim().isEmpty ||
        estimatedMinutes < 20 ||
        project == null ||
        project.status != SprintProjectStatus.active) {
      _taskInputError = '업무 정보를 확인하세요.';
      notifyListeners();
      return null;
    }
    return _buildTaskCreationPreview(
      title: title.trim(),
      projectId: projectId,
      estimatedMinutes: estimatedMinutes,
      deadline: deadline == null ? null : _day(deadline),
      requestedStart: normalizeScheduleStart(requestedStart),
      explicitStart: true,
    );
  }

  SprintTaskCreationPreview _buildTaskCreationPreview({
    required String title,
    required String projectId,
    required int estimatedMinutes,
    required DateTime? deadline,
    required DateTime? requestedStart,
    required bool explicitStart,
  }) {
    var conflicts = const <SprintScheduleConflict>[];
    DateTime? recommendedStart;
    if (requestedStart != null) {
      final end = requestedStart.add(Duration(minutes: estimatedMinutes));
      final validation = _schedulingEngine.validatePlacement(
        start: requestedStart,
        end: end,
        blocks: _blocks,
        externalEvents: _externalEvents,
        projectId: projectId,
      );
      conflicts = validation.conflicts;
      if (conflicts.isNotEmpty &&
          !conflicts.any(
            (conflict) => conflict.type == SprintConflictType.pastTime,
          )) {
        recommendedStart = _schedulingEngine.findNextAvailableStart(
          anchor: requestedStart,
          durationMinutes: estimatedMinutes,
          blocks: _blocks,
          externalEvents: _externalEvents,
        );
      }
    }
    return SprintTaskCreationPreview(
      title: title,
      projectId: projectId,
      estimatedMinutes: estimatedMinutes,
      deadline: deadline,
      requestedStart: requestedStart,
      explicitStart: explicitStart,
      conflicts: conflicts,
      recommendedStart: recommendedStart,
    );
  }

  Future<SprintTask?> createTaskFromPreview(
    SprintTaskCreationPreview preview, {
    bool useRecommendedStart = false,
    bool allowConflicts = false,
  }) async {
    final project = projectById(preview.projectId);
    if (preview.title.trim().isEmpty ||
        preview.estimatedMinutes < 20 ||
        project == null ||
        project.status != SprintProjectStatus.active) {
      _taskInputError = '업무 정보를 확인하세요.';
      notifyListeners();
      return null;
    }
    final selectedStart = useRecommendedStart
        ? preview.recommendedStart
        : preview.requestedStart;
    if (useRecommendedStart && selectedStart == null) {
      _taskInputError = '추천 시간을 찾지 못했습니다.';
      notifyListeners();
      return null;
    }
    if (selectedStart != null) {
      final validation = _schedulingEngine.validatePlacement(
        start: selectedStart,
        end: selectedStart.add(
          Duration(minutes: preview.estimatedMinutes),
        ),
        blocks: _blocks,
        externalEvents: _externalEvents,
        projectId: preview.projectId,
      );
      if (validation.conflicts.isNotEmpty &&
          (!allowConflicts || _hasHardPlacementConflict(validation))) {
        _taskInputError = _placementFailureMessage(validation);
        notifyListeners();
        return null;
      }
    }
    final task = SprintTask(
      id: _newId('task'),
      title: preview.title.trim(),
      projectId: preview.projectId,
      estimatedMinutes: preview.estimatedMinutes,
      order: _nextOrder(preview.projectId),
      state: selectedStart == null
          ? SprintTaskState.ready
          : SprintTaskState.scheduled,
      placementMode: SprintPlacementMode.automatic,
      deadline: preview.deadline,
    );
    _tasks.add(task);
    if (selectedStart != null) {
      _blocks.add(
        SprintScheduleBlock(
          id: _newId('block'),
          taskId: task.id,
          start: selectedStart,
          end: selectedStart.add(
            Duration(minutes: preview.estimatedMinutes),
          ),
        ),
      );
    }
    _recordActivity(
      type: SprintActivityEventType.taskCreated,
      projectId: task.projectId,
      taskId: task.id,
    );
    _refreshAttention();
    notifyListeners();
    await _persistNow();
    return task;
  }

  Future<SprintTask?> createTaskFromText(String rawText) async {
    final preview = previewTaskFromText(rawText);
    if (preview == null) return null;
    if (preview.hasConflicts) {
      _taskInputError = preview.hasHardConflict
          ? '과거 시간에는 업무를 배치할 수 없습니다.'
          : '선택한 시간에 일정 충돌이 있습니다.';
      notifyListeners();
      return null;
    }
    return createTaskFromPreview(preview);
  }

  List<SprintTask> tasksForProject(String projectId) {
    return _tasks
        .where((task) => task.projectId == projectId)
        .toList(growable: false)
      ..sort((a, b) => a.order.compareTo(b.order));
  }

  List<SprintScheduleBlock> blocksForTask(String taskId) {
    return _blocks
        .where((block) => block.taskId == taskId)
        .toList(growable: false)
      ..sort((a, b) => a.start.compareTo(b.start));
  }

  List<SprintScheduleConflict> conflictsForProject(String projectId) {
    return _schedulingEngine.detectConflicts(
      blocks: _blocks.where((block) {
        final task = taskById(block.taskId);
        return task?.projectId == projectId;
      }).toList(growable: false),
      tasks: tasksForProject(projectId),
      externalEvents: _externalEvents,
    ).where((conflict) => !_isConflictResolved(conflict.id)).toList(growable: false);
  }

  Future<bool> updateTask({
    required String taskId,
    required String title,
    required String projectId,
    required int estimatedMinutes,
    DateTime? deadline,
  }) async {
    final task = taskById(taskId);
    final normalizedTitle = title.trim();
    final targetProject = projectById(projectId);
    if (task == null ||
        task.state == SprintTaskState.completed ||
        task.state == SprintTaskState.cancelled ||
        !_taskBelongsToActiveProject(task) ||
        normalizedTitle.isEmpty ||
        estimatedMinutes < 20 ||
        targetProject == null ||
        targetProject.status != SprintProjectStatus.active) {
      return false;
    }
    final previousProjectId = task.projectId;
    task
      ..title = normalizedTitle
      ..estimatedMinutes = estimatedMinutes
      ..deadline = deadline == null ? null : _day(deadline);
    if (previousProjectId != projectId) {
      task
        ..projectId = projectId
        ..order = _nextOrder(projectId);
    }
    if (task.placementMode == SprintPlacementMode.automatic) {
      final now = DateTime.now();
      final futureBlocks = blocksForTask(taskId)
          .where((block) =>
              block.status == SprintScheduleBlockStatus.planned &&
              block.start.isAfter(now) &&
              !block.locked)
          .toList(growable: false);
      if (futureBlocks.isNotEmpty) {
        final first = futureBlocks.first;
        _blocks.removeWhere((block) => futureBlocks.contains(block));
        final minutesToSchedule = _remainingMinutesToSchedule(task);
        if (minutesToSchedule > 0) {
          final start = _schedulingEngine.findNextAvailableStart(
            anchor: first.start,
            durationMinutes: minutesToSchedule,
            blocks: _blocks,
            externalEvents: _externalEvents,
          );
          _blocks.add(
            SprintScheduleBlock(
              id: _newId('block'),
              taskId: task.id,
              start: start,
              end: start.add(Duration(minutes: minutesToSchedule)),
            ),
          );
        }
        task.state = _hasPlannedBlock(task.id)
            ? SprintTaskState.scheduled
            : SprintTaskState.ready;
      }
    }
    _recordActivity(
      type: SprintActivityEventType.taskUpdated,
      projectId: task.projectId,
      taskId: task.id,
    );
    _pruneConflictResolutions();
    _refreshAttention();
    notifyListeners();
    await _persistNow();
    return true;
  }

  Future<bool> cancelTask(String taskId) async {
    final task = taskById(taskId);
    if (task == null ||
        task.state == SprintTaskState.cancelled ||
        task.state == SprintTaskState.completed ||
        !_taskBelongsToActiveProject(task)) {
      return false;
    }
    task.state = SprintTaskState.cancelled;
    for (final block in _blocks.where((block) => block.taskId == taskId)) {
      if (block.status == SprintScheduleBlockStatus.planned) {
        block.status = SprintScheduleBlockStatus.cancelled;
      }
    }
    _recordActivity(
      type: SprintActivityEventType.taskCancelled,
      projectId: task.projectId,
      taskId: task.id,
    );
    _pruneConflictResolutions();
    _refreshAttention();
    notifyListeners();
    await _persistNow();
    return true;
  }

  Future<bool> deleteTask(String taskId) async {
    final task = taskById(taskId);
    if (task == null ||
        task.state == SprintTaskState.completed ||
        task.state == SprintTaskState.cancelled ||
        !_taskBelongsToActiveProject(task)) {
      return false;
    }
    final hasExecution = task.actualMinutes > 0;
    if (hasExecution) return false;
    final blockIds = _blocks
        .where((block) => block.taskId == taskId)
        .map((block) => block.id)
        .toSet();
    _blocks.removeWhere((block) => block.taskId == taskId);
    _attentionItems.removeWhere((item) => item.taskId == taskId);
    _conflictResolutions.removeWhere(
      (resolution) => blockIds.contains(resolution.blockId),
    );
    _tasks.removeWhere((candidate) => candidate.id == taskId);
    _recordActivity(
      type: SprintActivityEventType.taskDeleted,
      projectId: task.projectId,
      taskId: task.id,
    );
    _pruneConflictResolutions();
    _refreshAttention();
    notifyListeners();
    await _persistNow();
    return true;
  }

  Future<SprintOperationResult> createBlock({
    required String taskId,
    required DateTime start,
    required DateTime end,
    bool locked = false,
    bool allowConflicts = false,
  }) async {
    final task = taskById(taskId);
    if (task == null ||
        task.state == SprintTaskState.completed ||
        task.state == SprintTaskState.cancelled ||
        !_taskBelongsToActiveProject(task) ||
        !end.isAfter(start) ||
        end.difference(start).inMinutes < 20) {
      return const SprintOperationResult(
        success: false,
        message: '일정 정보를 확인하세요.',
      );
    }
    final duration = end.difference(start);
    final normalizedStart = _schedulingEngine.ceilToSlot(start);
    final normalizedEnd = normalizedStart.add(duration);
    final validation = _schedulingEngine.validatePlacement(
      start: normalizedStart,
      end: normalizedEnd,
      blocks: _blocks,
      externalEvents: _externalEvents,
      projectId: task.projectId,
      taskId: task.id,
    );
    if (validation.conflicts.isNotEmpty &&
        (!allowConflicts || _hasHardPlacementConflict(validation))) {
      return SprintOperationResult(
        success: false,
        message: _placementFailureMessage(validation),
        conflicts: validation.conflicts,
      );
    }
    final block = SprintScheduleBlock(
      id: _newId('block'),
      taskId: taskId,
      start: normalizedStart,
      end: normalizedEnd,
      locked: locked,
    );
    _blocks.add(block);
    task.state = SprintTaskState.scheduled;
    _syncTaskPlacementMode(task.id);
    _recordActivity(
      type: SprintActivityEventType.blockCreated,
      projectId: task.projectId,
      taskId: task.id,
      blockId: block.id,
    );
    _pruneConflictResolutions();
    _refreshAttention();
    notifyListeners();
    await _persistNow();
    return SprintOperationResult(
      success: true,
      message: '일정을 생성했습니다.',
      conflicts: validation.conflicts,
    );
  }

  Future<SprintOperationResult> updateBlock({
    required String blockId,
    required DateTime start,
    required DateTime end,
    required bool locked,
    bool allowConflicts = false,
  }) async {
    final block = blockById(blockId);
    final task = taskById(block?.taskId);
    if (block == null ||
        task == null ||
        task.state == SprintTaskState.completed ||
        task.state == SprintTaskState.cancelled ||
        block.status != SprintScheduleBlockStatus.planned ||
        !_taskBelongsToActiveProject(task) ||
        !end.isAfter(start)) {
      return const SprintOperationResult(
        success: false,
        message: '일정 정보를 확인하세요.',
      );
    }
    if (end.difference(start).inMinutes < 20) {
      return const SprintOperationResult(
        success: false,
        message: '일정은 20분 이상이어야 합니다.',
      );
    }
    final duration = end.difference(start);
    final normalizedStart = _schedulingEngine.ceilToSlot(start);
    final normalizedEnd = normalizedStart.add(duration);
    final validation = _schedulingEngine.validatePlacement(
      start: normalizedStart,
      end: normalizedEnd,
      blocks: _blocks,
      externalEvents: _externalEvents,
      ignoringBlockId: block.id,
      projectId: task.projectId,
      taskId: task.id,
    );
    if (validation.conflicts.isNotEmpty &&
        (!allowConflicts || _hasHardPlacementConflict(validation))) {
      return SprintOperationResult(
        success: false,
        message: _placementFailureMessage(validation),
        conflicts: validation.conflicts,
      );
    }
    final moved = block.start != normalizedStart;
    final resized = block.end != normalizedEnd;
    block
      ..start = normalizedStart
      ..end = normalizedEnd
      ..locked = locked;
    _syncTaskPlacementMode(task.id);
    if (moved) {
      _recordActivity(
        type: SprintActivityEventType.blockMoved,
        projectId: task.projectId,
        taskId: task.id,
        blockId: block.id,
      );
    }
    if (resized) {
      _recordActivity(
        type: SprintActivityEventType.blockResized,
        projectId: task.projectId,
        taskId: task.id,
        blockId: block.id,
      );
    }
    _pruneConflictResolutions();
    _refreshAttention();
    notifyListeners();
    await _persistNow();
    return SprintOperationResult(
      success: true,
      message: '일정을 변경했습니다.',
      conflicts: validation.conflicts,
    );
  }

  Future<SprintOperationResult> moveBlock({
    required String blockId,
    required DateTime newStart,
    bool allowConflicts = false,
  }) async {
    final block = blockById(blockId);
    final task = taskById(block?.taskId);
    if (block == null ||
        task == null ||
        task.state == SprintTaskState.completed ||
        task.state == SprintTaskState.cancelled ||
        block.status != SprintScheduleBlockStatus.planned ||
        !_taskBelongsToActiveProject(task)) {
      return const SprintOperationResult(
        success: false,
        message: '변경할 수 있는 일정을 찾지 못했습니다.',
      );
    }
    if (block.locked) {
      return const SprintOperationResult(
        success: false,
        message: '고정된 일정입니다.',
      );
    }
    final normalizedStart = _schedulingEngine.ceilToSlot(newStart);
    final newEnd = normalizedStart.add(Duration(minutes: block.durationMinutes));
    final validation = _schedulingEngine.validatePlacement(
      start: normalizedStart,
      end: newEnd,
      blocks: _blocks,
      externalEvents: _externalEvents,
      ignoringBlockId: block.id,
      projectId: task.projectId,
      taskId: task.id,
    );
    if (validation.conflicts.isNotEmpty &&
        (!allowConflicts || _hasHardPlacementConflict(validation))) {
      return SprintOperationResult(
        success: false,
        message: _placementFailureMessage(validation),
        conflicts: validation.conflicts,
      );
    }
    block
      ..start = normalizedStart
      ..end = newEnd;
    _recordActivity(
      type: SprintActivityEventType.blockMoved,
      projectId: task.projectId,
      taskId: task.id,
      blockId: block.id,
    );
    _pruneConflictResolutions();
    _refreshAttention();
    notifyListeners();
    await _persistNow();
    return SprintOperationResult(
      success: true,
      message: '일정을 이동했습니다.',
      conflicts: validation.conflicts,
    );
  }

  Future<SprintOperationResult> resizeBlock({
    required String blockId,
    required DateTime newEnd,
    bool allowConflicts = false,
  }) async {
    final block = blockById(blockId);
    final task = taskById(block?.taskId);
    if (block == null ||
        task == null ||
        task.state == SprintTaskState.completed ||
        task.state == SprintTaskState.cancelled ||
        block.status != SprintScheduleBlockStatus.planned ||
        block.locked ||
        !_taskBelongsToActiveProject(task) ||
        newEnd.difference(block.start).inMinutes < 20) {
      return const SprintOperationResult(
        success: false,
        message: '일정은 20분 이상이어야 합니다.',
      );
    }
    final validation = _schedulingEngine.validatePlacement(
      start: block.start,
      end: newEnd,
      blocks: _blocks,
      externalEvents: _externalEvents,
      ignoringBlockId: block.id,
      projectId: task.projectId,
      taskId: task.id,
    );
    if (validation.conflicts.isNotEmpty &&
        (!allowConflicts || _hasHardPlacementConflict(validation))) {
      return SprintOperationResult(
        success: false,
        message: _placementFailureMessage(validation),
        conflicts: validation.conflicts,
      );
    }
    block.end = newEnd;
    _recordActivity(
      type: SprintActivityEventType.blockResized,
      projectId: task.projectId,
      taskId: task.id,
      blockId: block.id,
    );
    _pruneConflictResolutions();
    _refreshAttention();
    notifyListeners();
    await _persistNow();
    return SprintOperationResult(
      success: true,
      message: '일정 길이를 변경했습니다.',
      conflicts: validation.conflicts,
    );
  }

  Future<bool> setBlockLocked(String blockId, bool locked) async {
    final block = blockById(blockId);
    final task = taskById(block?.taskId);
    if (block == null ||
        task == null ||
        block.status != SprintScheduleBlockStatus.planned ||
        !_taskBelongsToActiveProject(task)) {
      return false;
    }
    if (block.locked == locked) return true;
    block.locked = locked;
    _syncTaskPlacementMode(task.id);
    _pruneConflictResolutions();
    _refreshAttention();
    notifyListeners();
    await _persistNow();
    return true;
  }

  Future<bool> unscheduleBlock(String blockId) async {
    final block = blockById(blockId);
    final task = taskById(block?.taskId);
    if (block == null ||
        task == null ||
        block.status != SprintScheduleBlockStatus.planned ||
        !_taskBelongsToActiveProject(task)) {
      return false;
    }
    _blocks.removeWhere((candidate) => candidate.id == blockId);
    _syncTaskPlacementMode(task.id);
    if (!_blocks.any((candidate) =>
        candidate.taskId == task.id &&
        candidate.status == SprintScheduleBlockStatus.planned)) {
      task.state = SprintTaskState.ready;
    }
    _recordActivity(
      type: SprintActivityEventType.blockUnscheduled,
      projectId: task.projectId,
      taskId: task.id,
      blockId: block.id,
    );
    _pruneConflictResolutions();
    _refreshAttention();
    notifyListeners();
    await _persistNow();
    return true;
  }

  Future<bool> splitBlock({
    required String blockId,
    required int firstMinutes,
  }) async {
    final block = blockById(blockId);
    final task = taskById(block?.taskId);
    if (block == null ||
        task == null ||
        block.status != SprintScheduleBlockStatus.planned ||
        !_taskBelongsToActiveProject(task) ||
        firstMinutes < 20 ||
        block.durationMinutes - firstMinutes < 20) {
      return false;
    }
    final originalEnd = block.end;
    final secondStart = _schedulingEngine.findNextAvailableStart(
      anchor: block.start.add(Duration(minutes: firstMinutes)),
      durationMinutes: block.durationMinutes - firstMinutes,
      blocks: _blocks,
      externalEvents: _externalEvents,
      ignoredBlockIds: <String>{block.id},
    );
    block.end = block.start.add(Duration(minutes: firstMinutes));
    final second = SprintScheduleBlock(
      id: _newId('block'),
      taskId: block.taskId,
      start: secondStart,
      end: secondStart.add(
        Duration(minutes: originalEnd.difference(block.end).inMinutes),
      ),
      locked: block.locked,
    );
    _blocks.add(second);
    _recordActivity(
      type: SprintActivityEventType.blockSplit,
      projectId: task.projectId,
      taskId: task.id,
      blockId: block.id,
      payload: <String, String>{'secondBlockId': second.id},
    );
    _pruneConflictResolutions();
    _refreshAttention();
    notifyListeners();
    await _persistNow();
    return true;
  }

  Future<bool> resolveConflict({
    required SprintAttentionItem item,
    required SprintConflictResolutionType resolutionType,
    DateTime? adjustedStart,
  }) async {
    final block = blockById(item.blockId);
    if (block == null) return false;
    if (resolutionType == SprintConflictResolutionType.moved) {
      final target = item.suggestedStart ??
          _schedulingEngine.findNextAvailableStart(
            anchor: block.start,
            durationMinutes: block.durationMinutes,
            blocks: _blocks,
            externalEvents: _externalEvents,
            ignoredBlockIds: <String>{block.id},
          );
      final result = await updateBlock(
        blockId: block.id,
        start: target,
        end: target.add(Duration(minutes: block.durationMinutes)),
        locked: block.locked,
      );
      if (!result.success) return false;
    } else if (resolutionType == SprintConflictResolutionType.adjusted) {
      if (adjustedStart == null) return false;
      final result = await updateBlock(
        blockId: block.id,
        start: adjustedStart,
        end: adjustedStart.add(Duration(minutes: block.durationMinutes)),
        locked: block.locked,
      );
      if (!result.success) return false;
    } else {
      _conflictResolutions.removeWhere(
        (resolution) => resolution.conflictKey == item.id,
      );
      _conflictResolutions.add(
        SprintConflictResolution(
          id: _newId('resolution'),
          blockId: block.id,
          conflictKey: item.id,
          type: resolutionType,
          resolvedAt: DateTime.now(),
        ),
      );
    }
    final task = taskById(block.taskId);
    _recordActivity(
      type: SprintActivityEventType.conflictResolved,
      projectId: task?.projectId,
      taskId: task?.id,
      blockId: block.id,
      payload: <String, String>{'resolution': resolutionType.name},
    );
    _pruneConflictResolutions();
    _refreshAttention();
    notifyListeners();
    await _persistNow();
    return true;
  }

  void clearTaskInputError() {
    if (_taskInputError == null) return;
    _taskInputError = null;
    notifyListeners();
  }

  Future<void> placeUnplacedTask(SprintTask task) async {
    if (task.state == SprintTaskState.completed ||
        task.state == SprintTaskState.cancelled ||
        !_taskBelongsToActiveProject(task)) {
      return;
    }
    if (_blocks.any((block) =>
        block.taskId == task.id &&
        block.status == SprintScheduleBlockStatus.planned)) {
      return;
    }
    final anchor = _sameDay(_selectedDate, DateTime.now())
        ? DateTime.now()
        : _selectedDate;
    final start = _schedulingEngine.findNextAvailableStart(
      anchor: anchor,
      durationMinutes: task.remainingMinutes == 0
          ? task.estimatedMinutes
          : task.remainingMinutes,
      blocks: _blocks,
      externalEvents: _externalEvents,
    );
    final block = SprintScheduleBlock(
      id: _newId('block'),
      taskId: task.id,
      start: start,
      end: start.add(
        Duration(
          minutes: task.remainingMinutes == 0
              ? task.estimatedMinutes
              : task.remainingMinutes,
        ),
      ),
    );
    _blocks.add(block);
    task.state = SprintTaskState.scheduled;
    _recordActivity(
      type: SprintActivityEventType.blockCreated,
      projectId: task.projectId,
      taskId: task.id,
      blockId: block.id,
    );
    _pruneConflictResolutions();
    _refreshAttention();
    notifyListeners();
    await _persistNow();
  }

  void completeTask(String taskId) {
    final task = taskById(taskId);
    if (task == null ||
        task.state == SprintTaskState.completed ||
        task.state == SprintTaskState.cancelled ||
        !_taskBelongsToActiveProject(task)) {
      return;
    }
    task.state = SprintTaskState.completed;
    if (task.actualMinutes == 0) {
      task.actualMinutes = task.estimatedMinutes;
    }
    _blocks.removeWhere(
      (block) =>
          block.taskId == taskId &&
          block.status == SprintScheduleBlockStatus.planned &&
          block.start.isAfter(DateTime.now()),
    );
    for (final block in _blocks.where((block) => block.taskId == taskId)) {
      if (block.status != SprintScheduleBlockStatus.planned &&
          block.status != SprintScheduleBlockStatus.executed) {
        continue;
      }
      block
        ..completed = true
        ..status = SprintScheduleBlockStatus.executed
        ..executedMinutes = math.max(
          block.executedMinutes,
          block.durationMinutes,
        ).toInt();
    }
    final nextTask = _nextBlockedTask(task);
    if (nextTask != null) {
      nextTask.state = SprintTaskState.ready;
    }
    _recordActivity(
      type: SprintActivityEventType.taskCompleted,
      projectId: task.projectId,
      taskId: task.id,
    );
    _pruneConflictResolutions();
    _refreshAttention();
    notifyListeners();
    _queuePersist();
  }

  void setTaskManual(String taskId, bool manual) {
    final task = taskById(taskId);
    if (task == null ||
        task.state == SprintTaskState.completed ||
        task.state == SprintTaskState.cancelled ||
        !_taskBelongsToActiveProject(task)) {
      return;
    }
    task.placementMode = manual
        ? SprintPlacementMode.manual
        : SprintPlacementMode.automatic;
    for (final block in _blocks.where((block) =>
        block.taskId == taskId &&
        block.status == SprintScheduleBlockStatus.planned)) {
      block.locked = manual;
    }
    _pruneConflictResolutions();
    _refreshAttention();
    notifyListeners();
    _queuePersist();
  }

  void postponeTask(String taskId, SprintPostponeType type) {
    final task = taskById(taskId);
    if (task == null ||
        task.state == SprintTaskState.completed ||
        task.state == SprintTaskState.cancelled ||
        !_taskBelongsToActiveProject(task)) {
      return;
    }
    final candidates = _blocks
        .where((block) =>
            block.taskId == taskId &&
            block.status == SprintScheduleBlockStatus.planned)
        .toList(growable: false)
      ..sort((a, b) => a.start.compareTo(b.start));
    if (candidates.isEmpty) {
      unawaited(placeUnplacedTask(task));
      return;
    }
    final now = DateTime.now();
    DateTime anchor;
    switch (type) {
      case SprintPostponeType.laterToday:
        anchor = now.add(const Duration(hours: 2));
        break;
      case SprintPostponeType.tomorrow:
        anchor = DateTime(now.year, now.month, now.day + 1, 9, 30);
        break;
      case SprintPostponeType.nextWeek:
        final daysUntilMonday = 8 - now.weekday;
        anchor = DateTime(
          now.year,
          now.month,
          now.day + daysUntilMonday,
          10,
        );
        break;
      case SprintPostponeType.automatic:
        anchor = now.add(const Duration(hours: 2));
        break;
    }
    final block = candidates.first;
    if (block.locked) return;
    final target = _schedulingEngine.findNextAvailableStart(
      anchor: anchor,
      durationMinutes: block.durationMinutes,
      blocks: _blocks,
      externalEvents: _externalEvents,
      ignoredBlockIds: <String>{block.id},
    );
    final duration = block.end.difference(block.start);
    block
      ..start = target
      ..end = target.add(duration)
      ..locked = false;
    task.placementMode = SprintPlacementMode.automatic;
    _recordActivity(
      type: SprintActivityEventType.taskPostponed,
      projectId: task.projectId,
      taskId: task.id,
      blockId: block.id,
      payload: <String, String>{'type': type.name},
    );
    _pruneConflictResolutions();
    _refreshAttention();
    notifyListeners();
    _queuePersist();
  }

  Future<void> syncGoogleCalendar() async {
    if (_accountOperationInProgress) return;
    _accountOperationInProgress = true;
    notifyListeners();
    try {
      await _syncGoogleCalendarInternal();
    } finally {
      _accountOperationInProgress = false;
      notifyListeners();
    }
  }

  Future<void> _syncGoogleCalendarInternal() async {
    if (_calendarState == SprintCalendarConnectionState.syncing) return;
    _calendarState = SprintCalendarConnectionState.syncing;
    _calendarError = null;
    notifyListeners();
    try {
      final today = _day(DateTime.now());
      final events = await _calendarService.listEvents(
        calendarId: _googleCalendarId,
        timeMin: today.subtract(const Duration(days: 7)),
        timeMax: today.add(const Duration(days: 90)),
        maxResults: 500,
      );
      _externalEvents
        ..clear()
        ..addAll(events.map(_mapGoogleEvent).whereType<SprintExternalEvent>());
      _calendarState = SprintCalendarConnectionState.connected;
      _calendarError = null;
      _refreshAttention();
      await _persistNow();
      notifyListeners();
    } catch (error) {
      _calendarState = SprintCalendarConnectionState.failed;
      _calendarError = error.toString();
      notifyListeners();
    }
  }

  void disconnectGoogleCalendar() {
    if (_accountOperationInProgress) return;
    _externalEvents.clear();
    _calendarState = SprintCalendarConnectionState.notConnected;
    _calendarError = null;
    _refreshAttention();
    notifyListeners();
    _queuePersist();
  }

  String projectName(String? projectId) {
    return projectById(projectId)?.name ?? '프로젝트 없음';
  }

  SprintWorkspaceScope _validatedScope(SprintWorkspaceScope scope) {
    if (scope.type == SprintWorkspaceScopeType.project &&
        (projectById(scope.projectId) == null ||
            projectById(scope.projectId)?.status != SprintProjectStatus.active)) {
      return const SprintWorkspaceScope.all();
    }
    return scope;
  }

  bool _taskMatchesScope(SprintTask task) {
    final project = projectById(task.projectId);
    if (project == null || project.status != SprintProjectStatus.active) {
      return false;
    }
    switch (_workspaceScope.type) {
      case SprintWorkspaceScopeType.all:
        return true;
      case SprintWorkspaceScopeType.project:
        return task.projectId == _workspaceScope.projectId;
    }
  }

  bool _attentionMatchesScope(SprintAttentionItem item) {
    final project = projectById(item.projectId);
    if (project == null || project.status != SprintProjectStatus.active) {
      return false;
    }
    switch (_workspaceScope.type) {
      case SprintWorkspaceScopeType.all:
        return true;
      case SprintWorkspaceScopeType.project:
        return item.projectId == _workspaceScope.projectId;
    }
  }

  void _normalizeTaskStates() {
    for (final task in _tasks) {
      if (task.state == SprintTaskState.completed ||
          task.state == SprintTaskState.cancelled ||
          task.state == SprintTaskState.blocked) {
        continue;
      }
      task.state = _hasPlannedBlock(task.id)
          ? SprintTaskState.scheduled
          : SprintTaskState.ready;
    }
  }

  int _nextSequenceValue() {
    var value = DateTime.now().microsecondsSinceEpoch;
    for (final project in _projects) {
      value = math.max(value, _numericSuffix(project.id)).toInt();
    }
    for (final task in _tasks) {
      value = math.max(value, _numericSuffix(task.id)).toInt();
    }
    for (final block in _blocks) {
      value = math.max(value, _numericSuffix(block.id)).toInt();
    }
    for (final report in _projectReports) {
      value = math.max(value, _numericSuffix(report.id)).toInt();
    }
    for (final event in _activityEvents) {
      value = math.max(value, _numericSuffix(event.id)).toInt();
    }
    for (final resolution in _conflictResolutions) {
      value = math.max(value, _numericSuffix(resolution.id)).toInt();
    }
    return value + 1;
  }

  int _numericSuffix(String value) {
    final match = RegExp(r'(\d+)$').firstMatch(value);
    return int.tryParse(match?.group(1) ?? '') ?? 0;
  }

  String _newId(String prefix) {
    _sequence = math.max(
      _sequence + 1,
      DateTime.now().microsecondsSinceEpoch,
    ).toInt();
    return '$prefix-$_sequence';
  }

  int _nextOrder(String? projectId) {
    final projectTasks = _tasks.where((task) => task.projectId == projectId);
    if (projectTasks.isEmpty) return 0;
    return projectTasks
            .map((task) => task.order)
            .reduce((a, b) => a > b ? a : b) +
        1;
  }

  SprintTask? _nextBlockedTask(SprintTask completedTask) {
    final candidates = _tasks.where((task) {
      return task.projectId == completedTask.projectId &&
          task.order > completedTask.order &&
          task.state == SprintTaskState.blocked;
    }).toList(growable: false)
      ..sort((a, b) => a.order.compareTo(b.order));
    return candidates.isEmpty ? null : candidates.first;
  }

  DateTime _estimateCompletion(String projectId, int remainingMinutes) {
    if (remainingMinutes <= 0) return _day(DateTime.now());
    var minutes = remainingMinutes;
    var cursor = _day(DateTime.now());
    var safety = 0;
    while (minutes > 0 && safety < 365) {
      safety += 1;
      cursor = cursor.add(const Duration(days: 1));
      if (cursor.weekday == DateTime.saturday ||
          cursor.weekday == DateTime.sunday) {
        continue;
      }
      final externalBusy = _externalEvents.where((event) {
        return event.blocksTime && _sameDay(event.start, cursor);
      }).fold<int>(
        0,
        (sum, event) => sum + event.end.difference(event.start).inMinutes,
      );
      final otherWork = _blocks.where((block) {
        final task = taskById(block.taskId);
        return task?.projectId != projectId && _sameDay(block.start, cursor);
      }).fold<int>(0, (sum, block) => sum + block.durationMinutes);
      final available = math.max(60, 384 - externalBusy - otherWork).toInt();
      minutes -= available;
    }
    return cursor;
  }

  List<SprintDayLoad> _workloadFor(String projectId) {
    final today = _day(DateTime.now());
    return List<SprintDayLoad>.generate(7, (index) {
      final date = today.add(Duration(days: index));
      final planned = plannedMinutesFor(date, projectId);
      final externalBusy = _externalEvents.where((event) {
        return event.blocksTime && _sameDay(event.start, date);
      }).fold<int>(
        0,
        (sum, event) => sum + event.end.difference(event.start).inMinutes,
      );
      final available = date.weekday == DateTime.saturday ||
              date.weekday == DateTime.sunday
          ? 0
          : math.max(0, 480 - 60 - externalBusy).toInt();
      return SprintDayLoad(
        date: date,
        plannedMinutes: planned,
        availableMinutes: available,
      );
    }, growable: false);
  }

  DateTime _nextAvailableStart(DateTime anchor, int durationMinutes) {
    return _schedulingEngine.findNextAvailableStart(
      anchor: anchor,
      durationMinutes: durationMinutes,
      blocks: _blocks,
      externalEvents: _externalEvents,
    );
  }

  DateTime _ceilToThirtyMinutes(DateTime value) {
    return _schedulingEngine.ceilToSlot(value);
  }

  _ParsedTask _parseTask(String raw) {
    var title = raw;
    var minutes = 30;
    DateTime? date;
    DateTime? deadline;
    int? hour;
    var minute = 0;
    var explicitStart = false;
    final now = DateTime.now();
    final hourDuration = RegExp(r'(\d+)\s*시간').firstMatch(raw);
    final minuteDuration = RegExp(r'(\d+)\s*분').firstMatch(raw);
    if (hourDuration != null) {
      minutes = int.parse(hourDuration.group(1)!) * 60;
      title = title.replaceFirst(hourDuration.group(0)!, ' ');
    } else if (minuteDuration != null) {
      minutes = int.parse(minuteDuration.group(1)!);
      title = title.replaceFirst(minuteDuration.group(0)!, ' ');
    }
    if (raw.contains('오늘')) {
      date = _day(now);
      title = title.replaceAll('오늘', ' ');
    } else if (raw.contains('내일')) {
      date = _day(now).add(const Duration(days: 1));
      title = title.replaceAll('내일', ' ');
    } else if (raw.contains('모레')) {
      date = _day(now).add(const Duration(days: 2));
      title = title.replaceAll('모레', ' ');
    } else {
      const weekdayTokens = <String, int>{
        '월요일': DateTime.monday,
        '화요일': DateTime.tuesday,
        '수요일': DateTime.wednesday,
        '목요일': DateTime.thursday,
        '금요일': DateTime.friday,
        '토요일': DateTime.saturday,
        '일요일': DateTime.sunday,
      };
      for (final entry in weekdayTokens.entries) {
        if (!raw.contains(entry.key)) continue;
        var delta = entry.value - now.weekday;
        if (delta <= 0) delta += 7;
        date = _day(now).add(Duration(days: delta));
        title = title.replaceAll(entry.key, ' ');
        break;
      }
    }
    final timeMatch = RegExp(
      r'(오전|오후)?\s*(\d{1,2})\s*시(?:\s*(\d{1,2})\s*분)?',
    ).firstMatch(raw);
    if (timeMatch != null) {
      explicitStart = true;
      hour = int.parse(timeMatch.group(2)!);
      minute = int.tryParse(timeMatch.group(3) ?? '') ?? 0;
      if (hour > 23 || minute > 59) {
        return _ParsedTask.error('시간 형식을 확인하세요.');
      }
      if (timeMatch.group(1) == '오후' && hour < 12) hour += 12;
      if (timeMatch.group(1) == '오전' && hour == 12) hour = 0;
      title = title.replaceFirst(timeMatch.group(0)!, ' ');
    } else if (raw.contains('저녁')) {
      explicitStart = true;
      hour = 19;
      title = title.replaceAll('저녁', ' ');
    }
    if (raw.contains('까지') && date != null) {
      deadline = DateTime(date.year, date.month, date.day, 18);
      title = title.replaceAll('까지', ' ');
    }
    final normalizedTitle = title.replaceAll(RegExp(r'\s+'), ' ').trim();
    final safeTitle = normalizedTitle.isEmpty ? raw : normalizedTitle;
    DateTime? start;
    if (date != null) {
      if (hour == null) {
        final anchor = _sameDay(date, now) ? now : date;
        start = _nextAvailableStart(anchor, minutes);
      } else {
        start = _ceilToThirtyMinutes(
          DateTime(date.year, date.month, date.day, hour, minute),
        );
        if (_sameDay(start, now) && start.isBefore(now)) {
          return _ParsedTask.error(
            '오늘의 지난 시간에는 업무를 배치할 수 없습니다.',
          );
        }
      }
    }
    return _ParsedTask(
      title: safeTitle,
      minutes: math.max(20, minutes).toInt(),
      start: start,
      deadline: deadline,
      explicitStart: explicitStart,
    );
  }

  SprintExternalEvent? _mapGoogleEvent(gcal.Event event) {
    if (event.status == 'cancelled') return null;
    final startValue = event.start?.dateTime?.toLocal() ?? event.start?.date;
    if (startValue == null) return null;
    final allDay = event.start?.date != null;
    final endValue = event.end?.dateTime?.toLocal() ??
        event.end?.date ??
        startValue.add(
          allDay ? const Duration(days: 1) : const Duration(minutes: 30),
        );
    final title = event.summary?.trim();
    return SprintExternalEvent(
      id: event.id ?? 'google-${startValue.microsecondsSinceEpoch}',
      title: title == null || title.isEmpty ? '제목 없는 외부 일정' : title,
      start: startValue,
      end: endValue,
      allDay: allDay,
      blocksTime: event.transparency != 'transparent',
      sourceUrl: event.htmlLink,
    );
  }

  void _refreshAttention() {
    _pruneConflictResolutions();
    _attentionItems.clear();
    for (final project in _projects) {
      if (project.status != SprintProjectStatus.active) continue;
      final projectTasks = _tasks.where((task) {
        return task.projectId == project.id &&
            task.state != SprintTaskState.completed &&
            task.state != SprintTaskState.cancelled;
      });
      final remaining = projectTasks.fold<int>(
        0,
        (sum, task) => sum + task.remainingMinutes,
      );
      final estimate = _estimateCompletion(project.id, remaining);
      final target = project.targetDate;
      if (target != null && _day(estimate).isAfter(_day(target))) {
        _attentionItems.add(
          SprintAttentionItem(
            id: 'deadline-${project.id}',
            title: '목표일 위험',
            description: '${project.name}의 예상 완료일이 목표일보다 늦습니다.',
            projectId: project.id,
            conflictType: SprintConflictType.targetDateRisk,
          ),
        );
      }
    }
    for (final task in _tasks) {
      if (task.state == SprintTaskState.completed ||
          task.state == SprintTaskState.cancelled ||
          task.placementMode != SprintPlacementMode.manual ||
          task.actualMinutes <= 0 ||
          task.remainingMinutes <= 0) {
        continue;
      }
      final futurePlannedMinutes = _futurePlannedMinutes(task.id);
      final uncoveredMinutes = math.max(
        0,
        task.remainingMinutes - futurePlannedMinutes,
      ).toInt();
      if (uncoveredMinutes <= 0) continue;
      _attentionItems.add(
        SprintAttentionItem(
          id: 'remaining-${task.id}',
          title: '$uncoveredMinutes분이 남았습니다',
          description: '수동 고정 업무의 남은 시간을 직접 배치하세요.',
          projectId: task.projectId,
          taskId: task.id,
        ),
      );
    }
    final conflicts = _schedulingEngine.detectConflicts(
      blocks: _blocks,
      tasks: _tasks,
      externalEvents: _externalEvents,
    );
    for (final conflict in conflicts) {
      if (_isConflictResolved(conflict.id)) continue;
      _attentionItems.add(
        SprintAttentionItem(
          id: conflict.id,
          title: conflict.title,
          description: conflict.description,
          projectId: conflict.projectId,
          taskId: conflict.taskId,
          blockId: conflict.blockId,
          conflictType: conflict.type,
          suggestedStart: conflict.suggestedStart,
        ),
      );
    }
  }

  void _pruneConflictResolutions() {
    if (_conflictResolutions.isEmpty) return;
    final activeConflictKeys = _schedulingEngine
        .detectConflicts(
          blocks: _blocks,
          tasks: _tasks,
          externalEvents: _externalEvents,
        )
        .map((conflict) => conflict.id)
        .toSet();
    _conflictResolutions.removeWhere(
      (resolution) => !activeConflictKeys.contains(resolution.conflictKey),
    );
  }

  bool _isConflictResolved(String conflictKey) {
    return _conflictResolutions.any(
      (resolution) => resolution.conflictKey == conflictKey,
    );
  }

  bool _hasHardPlacementConflict(SprintPlacementValidation validation) {
    return validation.conflicts.any(
      (conflict) => conflict.type == SprintConflictType.pastTime,
    );
  }

  String _placementFailureMessage(SprintPlacementValidation validation) {
    if (_hasHardPlacementConflict(validation)) {
      return '과거 시간에는 일정을 배치할 수 없습니다.';
    }
    return '선택한 시간에 일정 충돌이 있습니다.';
  }

  bool _hasPlannedBlock(String taskId) {
    return _blocks.any(
      (block) =>
          block.taskId == taskId &&
          block.status == SprintScheduleBlockStatus.planned,
    );
  }

  int _futurePlannedMinutes(String taskId) {
    final now = DateTime.now();
    return _blocks.where((block) {
      return block.taskId == taskId &&
          block.status == SprintScheduleBlockStatus.planned &&
          block.end.isAfter(now);
    }).fold<int>(0, (sum, block) => sum + block.remainingMinutes);
  }

  int _remainingMinutesToSchedule(SprintTask task) {
    return math.max(
      0,
      task.remainingMinutes - _futurePlannedMinutes(task.id),
    ).toInt();
  }

  void _syncTaskPlacementMode(String taskId) {
    final task = taskById(taskId);
    if (task == null) return;
    final hasLockedBlock = _blocks.any(
      (block) =>
          block.taskId == taskId &&
          block.status == SprintScheduleBlockStatus.planned &&
          block.locked,
    );
    task.placementMode = hasLockedBlock
        ? SprintPlacementMode.manual
        : SprintPlacementMode.automatic;
  }

  SprintProjectReport _buildProjectReport({
    required SprintProject project,
    required DateTime completedAt,
    required String? reviewNote,
    required int conflictCount,
  }) {
    final tasks = _tasks
        .where((task) => task.projectId == project.id)
        .toList(growable: false);
    final taskIds = tasks.map((task) => task.id).toSet();
    final blocks = _blocks
        .where((block) => taskIds.contains(block.taskId))
        .toList(growable: false);
    final events = _activityEvents
        .where((event) => event.projectId == project.id)
        .toList(growable: false);
    final resolvedConflictCount = events
        .where((event) =>
            event.type == SprintActivityEventType.conflictResolved)
        .length;
    final target = project.targetDate;
    final targetDeltaDays = target == null
        ? 0
        : _day(completedAt).difference(_day(target)).inDays;
    return SprintProjectReport(
      id: _newId('report'),
      projectId: project.id,
      completedAt: completedAt,
      plannedMinutes: tasks.fold<int>(
        0,
        (sum, task) => sum + task.estimatedMinutes,
      ),
      actualMinutes: tasks.fold<int>(
        0,
        (sum, task) => sum + task.actualMinutes,
      ),
      scheduledMinutes: blocks.fold<int>(
        0,
        (sum, block) => sum + block.durationMinutes,
      ),
      completedTaskCount: tasks
          .where((task) => task.state == SprintTaskState.completed)
          .length,
      cancelledTaskCount: tasks
          .where((task) => task.state == SprintTaskState.cancelled)
          .length,
      postponeCount: events
          .where((event) => event.type == SprintActivityEventType.taskPostponed)
          .length,
      conflictCount: conflictCount + resolvedConflictCount,
      resolvedConflictCount: resolvedConflictCount,
      targetDeltaDays: targetDeltaDays,
      reviewNote: reviewNote,
    );
  }

  void _recordActivity({
    required SprintActivityEventType type,
    String? projectId,
    String? taskId,
    String? blockId,
    Map<String, String> payload = const <String, String>{},
  }) {
    _activityEvents.add(
      SprintActivityEvent(
        id: _newId('event'),
        type: type,
        occurredAt: DateTime.now(),
        projectId: projectId,
        taskId: taskId,
        blockId: blockId,
        payload: payload,
      ),
    );
  }

  SprintDatabaseSnapshot _snapshot() {
    return SprintDatabaseSnapshot(
      projects: List<SprintProject>.from(_projects),
      tasks: List<SprintTask>.from(_tasks),
      blocks: List<SprintScheduleBlock>.from(_blocks),
      externalEvents: List<SprintExternalEvent>.from(_externalEvents),
      attentionItems: List<SprintAttentionItem>.from(_attentionItems),
      projectReports: List<SprintProjectReport>.from(_projectReports),
      activityEvents: List<SprintActivityEvent>.from(_activityEvents),
      conflictResolutions:
          List<SprintConflictResolution>.from(_conflictResolutions),
      workspaceScope: _workspaceScope,
      selectedDate: _selectedDate,
      weekMode: _weekMode,
      googleCalendarId: _googleCalendarId,
      googleCalendarIdLocked: _googleCalendarIdLocked,
    );
  }

  Future<void> _persistNow() async {
    final snapshot = _snapshot();
    _writeQueue = _writeQueue
        .catchError((_) {})
        .then((_) => _database.replaceSnapshot(snapshot));
    await _writeQueue;
  }

  void _queuePersist() {
    final snapshot = _snapshot();
    _writeQueue = _writeQueue
        .catchError((_) {})
        .then((_) => _database.replaceSnapshot(snapshot));
  }

  static DateTime _day(DateTime value) {
    return DateTime(value.year, value.month, value.day);
  }

  static bool _sameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  static bool _intersectsDay(DateTime start, DateTime end, DateTime day) {
    final dayStart = _day(day);
    final dayEnd = dayStart.add(const Duration(days: 1));
    return start.isBefore(dayEnd) && end.isAfter(dayStart);
  }
}

class _ParsedTask {
  _ParsedTask({
    required this.title,
    required this.minutes,
    required this.start,
    required this.deadline,
    required this.explicitStart,
  }) : error = null;

  _ParsedTask.error(this.error)
      : title = '',
        minutes = 30,
        start = null,
        deadline = null,
        explicitStart = false;

  final String title;
  final int minutes;
  final DateTime? start;
  final DateTime? deadline;
  final bool explicitStart;
  final String? error;
}
