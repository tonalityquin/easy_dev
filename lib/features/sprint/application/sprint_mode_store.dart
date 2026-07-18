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
  DateTime _lastObservedToday = _day(DateTime.now());
  DateTime? _calendarLoadedStart;
  DateTime? _calendarLoadedEnd;
  Timer? _calendarRangeDebounce;
  int _calendarSyncGeneration = 0;
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
  SprintProject? get selectedProject => projectById(selectedProjectId);
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
  bool get isTodaySelected =>
      _selectedDate.isAtSameMomentAs(_day(DateTime.now()));
  bool get isCurrentWeekSelected =>
      weekStart(_selectedDate).isAtSameMomentAs(weekStart(DateTime.now()));

  String get scopeLabel {
    switch (_workspaceScope.type) {
      case SprintWorkspaceScopeType.all:
        return '전체 일정';
      case SprintWorkspaceScopeType.project:
        return projectName(_workspaceScope.projectId);
    }
  }

  IconData get scopeIcon {
    switch (_workspaceScope.type) {
      case SprintWorkspaceScopeType.all:
        return Icons.calendar_view_month_rounded;
      case SprintWorkspaceScopeType.project:
        return projectById(_workspaceScope.projectId)?.icon ??
            Icons.folder_rounded;
    }
  }

  List<SprintAttentionItem> get currentScopeAttentionItems =>
      _attentionItems.where(_attentionMatchesScope).toList(growable: false);

  DateTime? projectScheduleLowerBound(String? projectId) {
    final value = projectById(projectId)?.targetStartDate;
    return value == null ? null : _day(value);
  }

  bool canScheduleProjectOn(String? projectId, DateTime date) {
    final lower = projectScheduleLowerBound(projectId);
    return lower == null || !_day(date).isBefore(lower);
  }

  Future<void> initialize() async {
    if (_initialized) return;
    if (_initializing) {
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
      final currentToday = _day(DateTime.now());
      final restoredSelectedDate = _day(snapshot.selectedDate);
      final restoredObservedToday = _day(snapshot.lastObservedToday);
      _selectedDate = restoredSelectedDate.isAtSameMomentAs(restoredObservedToday)
          ? currentToday
          : restoredSelectedDate;
      _lastObservedToday = currentToday;
      _workspaceScope = _validatedScope(snapshot.workspaceScope);
      _weekMode = snapshot.weekMode;
      _googleCalendarId = snapshot.googleCalendarId;
      _googleCalendarIdLocked = snapshot.googleCalendarIdLocked;
      _calendarState = _externalEvents.isEmpty
          ? SprintCalendarConnectionState.notConnected
          : SprintCalendarConnectionState.connected;
      _sequence = _nextSequenceValue();
      _normalizeAllDayData();
      _refreshAttention();
      _initialized = true;
      await _persistNow();
      ensureCalendarRangeFor(_selectedDate);
    } finally {
      _initializing = false;
      notifyListeners();
    }
  }

  Future<void> flush() async {
    await _writeQueue;
    if (_initialized) await _persistNow();
  }

  Future<SprintProject?> createProject({
    required String name,
    required String iconKey,
    DateTime? targetStartDate,
    DateTime? targetDate,
  }) async {
    final normalizedName = name.trim();
    final start = targetStartDate == null ? null : _day(targetStartDate);
    final target = targetDate == null ? null : _day(targetDate);
    if (normalizedName.isEmpty || !_validProjectDateRange(start, target)) {
      return null;
    }
    final project = SprintProject(
      id: _newId('project'),
      name: normalizedName,
      iconKey: sprintProjectIcons.containsKey(iconKey) ? iconKey : 'folder',
      targetStartDate: start,
      targetDate: target,
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

  Future<SprintOperationResult> updateProject({
    required String projectId,
    required String name,
    required String iconKey,
    DateTime? targetStartDate,
    DateTime? targetDate,
  }) async {
    final project = projectById(projectId);
    final normalizedName = name.trim();
    final start = targetStartDate == null ? null : _day(targetStartDate);
    final target = targetDate == null ? null : _day(targetDate);
    if (project == null ||
        normalizedName.isEmpty ||
        !_validProjectDateRange(start, target)) {
      return const SprintOperationResult(
        success: false,
        message: '프로젝트 날짜 범위를 확인하세요.',
      );
    }
    final affected = _tasks.where((task) {
      return task.projectId == projectId &&
          task.state != SprintTaskState.completed &&
          task.state != SprintTaskState.cancelled &&
          start != null &&
          task.startDate.isBefore(start);
    }).toList(growable: false);
    final hasLocked = affected.any(
      (task) => blocksForTask(task.id).any((block) => block.locked),
    );
    if (hasLocked) {
      return const SprintOperationResult(
        success: false,
        message: '새 목표 시작일 이전에 고정된 일정이 있습니다.',
      );
    }
    var moved = 0;
    if (start != null) {
      for (final task in affected) {
        final days = math.max(0, task.endDate.difference(task.startDate).inDays);
        task
          ..startDate = start
          ..endDate = start.add(Duration(days: days));
        _syncBlockFromTask(task);
        moved += 1;
      }
    }
    project
      ..name = normalizedName
      ..iconKey = sprintProjectIcons.containsKey(iconKey) ? iconKey : 'folder'
      ..targetStartDate = start
      ..targetDate = target;
    _recordActivity(
      type: SprintActivityEventType.projectUpdated,
      projectId: project.id,
      payload: <String, String>{'moved_tasks': '$moved'},
    );
    _refreshAttention();
    notifyListeners();
    await _persistNow();
    return SprintOperationResult(
      success: true,
      message: moved == 0
          ? '프로젝트를 수정했습니다.'
          : '프로젝트를 수정하고 업무 $moved개를 시작일 이후로 이동했습니다.',
    );
  }

  Future<SprintProjectReport?> completeProject({
    required String projectId,
    required String reviewNote,
    required bool cancelRemaining,
    required bool acceptConflicts,
  }) async {
    final project = projectById(projectId);
    if (project == null || project.status != SprintProjectStatus.active) {
      return null;
    }
    final remaining = tasksForProject(projectId).where((task) {
      return task.state != SprintTaskState.completed &&
          task.state != SprintTaskState.cancelled;
    }).toList(growable: false);
    final conflicts = conflictsForProject(projectId);
    if (remaining.isNotEmpty && !cancelRemaining) return null;
    if (conflicts.isNotEmpty && !acceptConflicts) return null;
    if (cancelRemaining) {
      for (final task in remaining) {
        task.state = SprintTaskState.cancelled;
        final block = _blockForTask(task.id);
        if (block != null) block.status = SprintScheduleBlockStatus.cancelled;
      }
    }
    final completedAt = DateTime.now();
    project
      ..status = SprintProjectStatus.completed
      ..completedAt = completedAt;
    final report = _buildProjectReport(
      project: project,
      completedAt: completedAt,
      reviewNote: reviewNote.trim().isEmpty ? null : reviewNote.trim(),
      conflictCount: conflicts.length,
    );
    _projectReports.add(report);
    _recordActivity(
      type: SprintActivityEventType.projectCompleted,
      projectId: projectId,
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
      ..completedAt = null
      ..archivedAt = null
      ..reopenedAt = DateTime.now();
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
    if (project == null) return false;
    final taskIds = _tasks
        .where((task) => task.projectId == projectId)
        .map((task) => task.id)
        .toSet();
    _blocks.removeWhere((block) => taskIds.contains(block.taskId));
    _pruneConflictResolutions();
    _tasks.removeWhere((task) => taskIds.contains(task.id));
    _attentionItems.removeWhere((item) => item.projectId == projectId);
    _projectReports.removeWhere((report) => report.projectId == projectId);
    _activityEvents.removeWhere((event) => event.projectId == projectId);
    _projects.remove(project);
    if (_workspaceScope.projectId == projectId) {
      _workspaceScope = const SprintWorkspaceScope.all();
    }
    notifyListeners();
    await _persistNow();
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
      _calendarRangeDebounce?.cancel();
      _calendarSyncGeneration += 1;
      _externalEvents.clear();
      _calendarLoadedStart = null;
      _calendarLoadedEnd = null;
      _calendarState = SprintCalendarConnectionState.notConnected;
      _calendarError = null;
    }
    await _persistNow();
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

  void selectScope(SprintWorkspaceScope scope) {
    final validated = _validatedScope(scope);
    if (_workspaceScope == validated) return;
    _workspaceScope = validated;
    notifyListeners();
    _queuePersist();
  }

  void selectAll() => selectScope(const SprintWorkspaceScope.all());

  void selectProject(String projectId) {
    selectScope(SprintWorkspaceScope.project(projectId));
  }

  void selectPreviousScope() {
    _selectAdjacentScope(-1);
  }

  void selectNextScope() {
    _selectAdjacentScope(1);
  }

  void _selectAdjacentScope(int delta) {
    final scopes = <SprintWorkspaceScope>[
      const SprintWorkspaceScope.all(),
      ...projects.map((project) => SprintWorkspaceScope.project(project.id)),
    ];
    if (scopes.length < 2) return;
    var currentIndex = scopes.indexWhere((scope) => scope == _workspaceScope);
    if (currentIndex < 0) currentIndex = 0;
    final rawIndex = (currentIndex + delta) % scopes.length;
    final nextIndex = rawIndex < 0 ? rawIndex + scopes.length : rawIndex;
    selectScope(scopes[nextIndex]);
  }

  void selectDate(DateTime date) {
    final normalized = _day(date);
    if (_selectedDate.isAtSameMomentAs(normalized)) {
      ensureCalendarRangeFor(normalized);
      return;
    }
    _selectedDate = normalized;
    notifyListeners();
    _queuePersist();
    ensureCalendarRangeFor(normalized);
  }

  void selectPreviousDay() {
    selectDate(_selectedDate.subtract(const Duration(days: 1)));
  }

  void selectNextDay() {
    selectDate(_selectedDate.add(const Duration(days: 1)));
  }

  void selectPreviousWeek() {
    selectDate(_selectedDate.subtract(const Duration(days: 7)));
  }

  void selectNextWeek() {
    selectDate(_selectedDate.add(const Duration(days: 7)));
  }

  void selectToday() {
    _lastObservedToday = _day(DateTime.now());
    selectDate(_lastObservedToday);
  }

  void handleAppResumed() {
    final currentToday = _day(DateTime.now());
    final selectedWasObservedToday =
        _selectedDate.isAtSameMomentAs(_lastObservedToday);
    final dayChanged = !currentToday.isAtSameMomentAs(_lastObservedToday);
    _lastObservedToday = currentToday;
    if (dayChanged && selectedWasObservedToday) {
      _selectedDate = currentToday;
      notifyListeners();
      _queuePersist();
    } else if (dayChanged) {
      _queuePersist();
    }
    ensureCalendarRangeFor(_selectedDate);
  }

  DateTime weekStart(DateTime anchor) {
    final day = _day(anchor);
    return day.subtract(Duration(days: day.weekday - 1));
  }

  DateTime weekEnd(DateTime anchor) {
    return weekStart(anchor).add(const Duration(days: 6));
  }

  void setWeekMode(bool value) {
    if (_weekMode == value) return;
    _weekMode = value;
    notifyListeners();
    _queuePersist();
  }

  List<DateTime> weekDates(DateTime anchor) {
    final monday = weekStart(anchor);
    return List<DateTime>.generate(
      7,
      (index) => monday.add(Duration(days: index)),
      growable: false,
    );
  }

  List<SprintTimelineEntry> timelineFor(DateTime date) {
    final day = _day(date);
    final taskEntries = <SprintTimelineEntry>[];
    for (final task in _tasks) {
      if (!_taskMatchesScope(task) || !task.spans(day)) continue;
      if (task.state == SprintTaskState.cancelled) continue;
      final block = _blockForTask(task.id);
      final project = projectById(task.projectId);
      if (block == null || project == null) continue;
      taskEntries.add(
        SprintTimelineEntry.task(
          block: block,
          task: task,
          project: project,
        ),
      );
    }
    taskEntries.sort((a, b) => _compareTasks(a.task!, b.task!));
    final externalEntries = _externalEvents.where((event) {
      final start = _day(event.start);
      final last = event.allDay
          ? _day(event.end.subtract(const Duration(days: 1)))
          : _day(event.end);
      return !day.isBefore(start) && !day.isAfter(last);
    }).map(
      (event) => SprintTimelineEntry.external(externalEvent: event),
    ).toList(growable: false)
      ..sort((a, b) => a.start.compareTo(b.start));
    return <SprintTimelineEntry>[...taskEntries, ...externalEntries];
  }

  DateTime? previousScheduledDate(DateTime from) {
    final day = _day(from);
    DateTime? result;
    for (final task in _tasks) {
      if (!_taskMatchesScope(task) ||
          task.state == SprintTaskState.cancelled) {
        continue;
      }
      final candidate = task.endDate.isBefore(day) ? task.endDate : null;
      if (candidate != null && (result == null || candidate.isAfter(result))) {
        result = candidate;
      }
    }
    for (final event in _externalEvents) {
      final end = event.allDay
          ? _day(event.end.subtract(const Duration(days: 1)))
          : _day(event.end);
      if (end.isBefore(day) && (result == null || end.isAfter(result))) {
        result = end;
      }
    }
    return result;
  }

  DateTime? nextScheduledDate(DateTime from) {
    final day = _day(from);
    DateTime? result;
    for (final task in _tasks) {
      if (!_taskMatchesScope(task) ||
          task.state == SprintTaskState.cancelled) {
        continue;
      }
      final candidate = task.startDate.isAfter(day) ? task.startDate : null;
      if (candidate != null && (result == null || candidate.isBefore(result))) {
        result = candidate;
      }
    }
    for (final event in _externalEvents) {
      final start = _day(event.start);
      if (start.isAfter(day) && (result == null || start.isBefore(result))) {
        result = start;
      }
    }
    return result;
  }

  List<SprintTask> unplacedTasks() {
    return _tasks.where((task) {
      return _taskBelongsToActiveProject(task) &&
          task.state != SprintTaskState.completed &&
          task.state != SprintTaskState.cancelled &&
          _blockForTask(task.id) == null;
    }).toList(growable: false)
      ..sort(_compareTasks);
  }

  SprintProjectSummary summaryFor(String projectId) {
    final project = projectById(projectId);
    if (project == null) throw StateError('project_not_found');
    final projectTasks = tasksForProject(projectId)
        .where((task) => task.state != SprintTaskState.cancelled)
        .toList(growable: false);
    final completed = projectTasks
        .where((task) => task.state == SprintTaskState.completed)
        .length;
    final today = _day(DateTime.now());
    final todayTasks = projectTasks.where((task) {
      return task.spans(today) && task.state != SprintTaskState.completed;
    }).toList(growable: false)
      ..sort(_compareTasks);
    final incomplete = projectTasks.where((task) {
      return task.state != SprintTaskState.completed &&
          task.state != SprintTaskState.cancelled;
    }).toList(growable: false);
    final plannedCompletion = incomplete.isEmpty
        ? today
        : incomplete
            .map((task) => task.endDate)
            .reduce((a, b) => a.isAfter(b) ? a : b);
    return SprintProjectSummary(
      project: project,
      totalTaskCount: projectTasks.length,
      completedTaskCount: completed,
      todayTaskCount: todayTasks.length,
      attentionCount:
          _attentionItems.where((item) => item.projectId == projectId).length,
      highPriorityRemainingCount: incomplete
          .where((task) => task.priority == SprintTaskPriority.high)
          .length,
      plannedCompletion: plannedCompletion,
      workload: _workloadFor(projectId),
      todayTasks: todayTasks,
      pathTasks: List<SprintTask>.from(projectTasks)..sort(_compareTasks),
    );
  }

  SprintDayLoad dayLoadFor(DateTime date, [String? projectId]) {
    final day = _day(date);
    final relevant = _tasks.where((task) {
      if (task.state == SprintTaskState.cancelled ||
          task.state == SprintTaskState.completed ||
          !task.spans(day)) {
        return false;
      }
      if (projectId != null) return task.projectId == projectId;
      return _taskMatchesScope(task);
    }).toList(growable: false);
    return SprintDayLoad(
      date: day,
      taskCount: relevant.length,
      highPriorityCount:
          relevant.where((task) => task.priority == SprintTaskPriority.high).length,
      priorityScore: relevant.fold<int>(
        0,
        (sum, task) => sum + _priorityWeight(task.priority),
      ),
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
    return projects.length == 1 ? projects.first.id : null;
  }

  DateTime suggestedTaskStart({
    required String projectId,
    required DateTime date,
  }) {
    var result = _day(date);
    final today = _day(DateTime.now());
    if (result.isBefore(today)) result = today;
    final lower = projectScheduleLowerBound(projectId);
    if (lower != null && result.isBefore(lower)) result = lower;
    return result;
  }

  SprintTaskCreationPreview? previewTaskFromText(
    String rawText, {
    String? projectId,
  }) {
    _taskInputError = null;
    final resolvedProjectId = preferredTaskProjectId(projectId);
    if (resolvedProjectId == null) {
      _taskInputError = projects.isEmpty
          ? '업무를 추가하려면 먼저 프로젝트를 생성하세요.'
          : '업무를 추가할 프로젝트를 선택하세요.';
      return null;
    }
    final parsed = _parseTask(rawText);
    if (parsed.error != null) {
      _taskInputError = parsed.error;
      return null;
    }
    final adjustedStart = suggestedTaskStart(
      projectId: resolvedProjectId,
      date: parsed.startDate,
    );
    final days = math.max(0, parsed.endDate.difference(parsed.startDate).inDays);
    return previewTaskDetails(
      title: parsed.title,
      projectId: resolvedProjectId,
      priority: parsed.priority,
      startDate: adjustedStart,
      endDate: adjustedStart.add(Duration(days: days)),
    );
  }

  SprintTaskCreationPreview? previewTaskDetails({
    required String title,
    required String projectId,
    required SprintTaskPriority priority,
    required DateTime startDate,
    required DateTime endDate,
  }) {
    _taskInputError = null;
    final normalizedTitle = title.trim();
    final project = projectById(projectId);
    final start = _day(startDate);
    final end = _day(endDate);
    if (normalizedTitle.isEmpty) {
      _taskInputError = '업무명을 입력하세요.';
      return null;
    }
    if (project == null || project.status != SprintProjectStatus.active) {
      _taskInputError = '업무를 추가할 프로젝트를 선택하세요.';
      return null;
    }
    final validation = _validateTaskDates(
      projectId: projectId,
      startDate: start,
      endDate: end,
    );
    return SprintTaskCreationPreview(
      title: normalizedTitle,
      projectId: projectId,
      priority: priority,
      startDate: start,
      endDate: end,
      conflicts: validation.conflicts,
    );
  }

  Future<SprintTask?> createTaskFromPreview(
    SprintTaskCreationPreview preview,
  ) async {
    _taskInputError = null;
    if (preview.hasHardConflict) {
      _taskInputError = _dateConflictMessage(preview.conflicts);
      return null;
    }
    final project = projectById(preview.projectId);
    if (project == null || project.status != SprintProjectStatus.active) {
      _taskInputError = '업무를 추가할 프로젝트를 선택하세요.';
      return null;
    }
    final task = SprintTask(
      id: _newId('task'),
      title: preview.title,
      projectId: preview.projectId,
      priority: preview.priority,
      startDate: preview.startDate,
      endDate: preview.endDate,
      order: _nextOrder(preview.projectId),
      state: SprintTaskState.scheduled,
      placementMode: SprintPlacementMode.automatic,
    );
    final block = SprintScheduleBlock(
      id: _newId('block'),
      taskId: task.id,
      start: task.startDate,
      end: _exclusiveEnd(task.endDate),
      allDay: true,
    );
    _tasks.add(task);
    _blocks.add(block);
    _recordActivity(
      type: SprintActivityEventType.taskCreated,
      projectId: task.projectId,
      taskId: task.id,
      blockId: block.id,
      payload: <String, String>{'priority': task.priority.name},
    );
    _refreshAttention();
    notifyListeners();
    await _persistNow();
    return task;
  }

  Future<SprintTask?> createTaskFromText(String rawText) async {
    final preview = previewTaskFromText(rawText);
    if (preview == null) return null;
    return createTaskFromPreview(preview);
  }

  List<SprintTask> tasksForProject(String projectId) {
    return _tasks.where((task) => task.projectId == projectId).toList(growable: false)
      ..sort(_compareTasks);
  }

  List<SprintScheduleBlock> blocksForTask(String taskId) {
    return _blocks.where((block) => block.taskId == taskId).toList(growable: false)
      ..sort((a, b) => a.start.compareTo(b.start));
  }

  List<SprintScheduleConflict> conflictsForProject(String projectId) {
    final conflicts = <SprintScheduleConflict>[];
    for (final task in tasksForProject(projectId)) {
      if (task.state == SprintTaskState.completed ||
          task.state == SprintTaskState.cancelled) {
        continue;
      }
      conflicts.addAll(
        _validateTaskDates(
          projectId: projectId,
          startDate: task.startDate,
          endDate: task.endDate,
          taskId: task.id,
          blockId: _blockForTask(task.id)?.id,
          allowPastDate: true,
        ).conflicts,
      );
    }
    return conflicts.where((value) => !_isConflictResolved(value.id)).toList();
  }

  Future<bool> updateTask({
    required String taskId,
    required String title,
    required String projectId,
    required SprintTaskPriority priority,
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    final task = taskById(taskId);
    final project = projectById(projectId);
    final normalizedTitle = title.trim();
    if (task == null ||
        project == null ||
        project.status != SprintProjectStatus.active ||
        normalizedTitle.isEmpty) {
      return false;
    }
    final start = _day(startDate);
    final end = _day(endDate);
    final validation = _validateTaskDates(
      projectId: projectId,
      startDate: start,
      endDate: end,
      taskId: task.id,
      blockId: _blockForTask(task.id)?.id,
      allowPastDate: _day(start).isAtSameMomentAs(_day(task.startDate)),
    );
    if (validation.conflicts.any(_isHardDateConflict)) return false;
    task
      ..title = normalizedTitle
      ..projectId = projectId
      ..priority = priority
      ..startDate = start
      ..endDate = end
      ..state = task.state == SprintTaskState.completed
          ? SprintTaskState.completed
          : SprintTaskState.scheduled;
    _syncBlockFromTask(task);
    _recordActivity(
      type: SprintActivityEventType.taskUpdated,
      projectId: task.projectId,
      taskId: task.id,
    );
    _refreshAttention();
    notifyListeners();
    await _persistNow();
    return true;
  }

  Future<bool> cancelTask(String taskId) async {
    final task = taskById(taskId);
    if (task == null) return false;
    task.state = SprintTaskState.cancelled;
    final block = _blockForTask(taskId);
    if (block != null) block.status = SprintScheduleBlockStatus.cancelled;
    _recordActivity(
      type: SprintActivityEventType.taskCancelled,
      projectId: task.projectId,
      taskId: task.id,
      blockId: block?.id,
    );
    _refreshAttention();
    notifyListeners();
    await _persistNow();
    return true;
  }

  Future<bool> deleteTask(String taskId) async {
    final task = taskById(taskId);
    if (task == null) return false;
    _blocks.removeWhere((block) => block.taskId == taskId);
    _attentionItems.removeWhere((item) => item.taskId == taskId);
    _tasks.remove(task);
    _recordActivity(
      type: SprintActivityEventType.taskDeleted,
      projectId: task.projectId,
      taskId: task.id,
    );
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
  }) async {
    final task = taskById(taskId);
    if (task == null) {
      return const SprintOperationResult(
        success: false,
        message: '업무를 찾을 수 없습니다.',
      );
    }
    final startDay = _day(start);
    final endDay = _inclusiveEnd(end);
    final validation = _validateTaskDates(
      projectId: task.projectId,
      startDate: startDay,
      endDate: endDay,
      taskId: task.id,
    );
    if (validation.conflicts.any(_isHardDateConflict)) {
      return SprintOperationResult(
        success: false,
        message: _dateConflictMessage(validation.conflicts),
        conflicts: validation.conflicts,
      );
    }
    task
      ..startDate = startDay
      ..endDate = endDay
      ..state = SprintTaskState.scheduled;
    _syncBlockFromTask(task, locked: locked);
    _recordActivity(
      type: SprintActivityEventType.blockCreated,
      projectId: task.projectId,
      taskId: task.id,
      blockId: _blockForTask(task.id)?.id,
    );
    _refreshAttention();
    notifyListeners();
    await _persistNow();
    return const SprintOperationResult(
      success: true,
      message: '종일 일정을 저장했습니다.',
    );
  }

  Future<SprintOperationResult> updateBlock({
    required String blockId,
    required DateTime start,
    required DateTime end,
    required bool locked,
  }) async {
    final block = blockById(blockId);
    final task = taskById(block?.taskId);
    if (block == null || task == null) {
      return const SprintOperationResult(
        success: false,
        message: '일정을 찾을 수 없습니다.',
      );
    }
    final startDay = _day(start);
    final endDay = _inclusiveEnd(end);
    final validation = _validateTaskDates(
      projectId: task.projectId,
      startDate: startDay,
      endDate: endDay,
      taskId: task.id,
      blockId: block.id,
      allowPastDate: _day(startDay).isAtSameMomentAs(_day(task.startDate)),
    );
    if (validation.conflicts.any(_isHardDateConflict)) {
      return SprintOperationResult(
        success: false,
        message: _dateConflictMessage(validation.conflicts),
        conflicts: validation.conflicts,
      );
    }
    final moved = block.start != startDay;
    final resized = block.end != _exclusiveEnd(endDay);
    task
      ..startDate = startDay
      ..endDate = endDay
      ..state = SprintTaskState.scheduled;
    block
      ..start = startDay
      ..end = _exclusiveEnd(endDay)
      ..allDay = true
      ..locked = locked
      ..status = SprintScheduleBlockStatus.planned;
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
    _refreshAttention();
    notifyListeners();
    await _persistNow();
    return const SprintOperationResult(
      success: true,
      message: '종일 일정 기간을 수정했습니다.',
    );
  }


  Future<bool> setBlockLocked(String blockId, bool locked) async {
    final block = blockById(blockId);
    if (block == null) return false;
    block.locked = locked;
    final task = taskById(block.taskId);
    if (task != null) {
      task.placementMode =
          locked ? SprintPlacementMode.manual : SprintPlacementMode.automatic;
    }
    notifyListeners();
    await _persistNow();
    return true;
  }

  Future<bool> unscheduleBlock(String blockId) async {
    final block = blockById(blockId);
    final task = taskById(block?.taskId);
    if (block == null || task == null) return false;
    _blocks.remove(block);
    task.state = SprintTaskState.ready;
    _recordActivity(
      type: SprintActivityEventType.blockUnscheduled,
      projectId: task.projectId,
      taskId: task.id,
      blockId: block.id,
    );
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
    final task = taskById(item.taskId);
    if (task == null) return false;
    if (resolutionType == SprintConflictResolutionType.kept &&
        item.conflictType == SprintConflictType.afterProjectTargetDate) {
      _conflictResolutions.removeWhere(
        (resolution) => resolution.conflictKey == item.id,
      );
      _conflictResolutions.add(
        SprintConflictResolution(
          id: _newId('resolution'),
          conflictKey: item.id,
          type: resolutionType,
          resolvedAt: DateTime.now(),
          blockId: item.blockId,
        ),
      );
      _refreshAttention();
      notifyListeners();
      await _persistNow();
      return true;
    }
    final target = adjustedStart ?? item.suggestedStart;
    if (target == null) return false;
    final days = math.max(0, task.endDate.difference(task.startDate).inDays);
    final start = suggestedTaskStart(
      projectId: task.projectId ?? '',
      date: target,
    );
    task
      ..startDate = start
      ..endDate = start.add(Duration(days: days));
    _syncBlockFromTask(task);
    _conflictResolutions.add(
      SprintConflictResolution(
        id: _newId('resolution'),
        conflictKey: item.id,
        type: resolutionType,
        resolvedAt: DateTime.now(),
        blockId: item.blockId,
      ),
    );
    _recordActivity(
      type: SprintActivityEventType.conflictResolved,
      projectId: task.projectId,
      taskId: task.id,
      blockId: item.blockId,
    );
    _refreshAttention();
    notifyListeners();
    await _persistNow();
    return true;
  }

  void clearTaskInputError() {
    _taskInputError = null;
  }

  Future<void> placeUnplacedTask(SprintTask task) async {
    final start = suggestedTaskStart(
      projectId: task.projectId ?? '',
      date: _selectedDate,
    );
    final days = math.max(0, task.endDate.difference(task.startDate).inDays);
    task
      ..startDate = start
      ..endDate = start.add(Duration(days: days))
      ..state = SprintTaskState.scheduled;
    _syncBlockFromTask(task);
    _refreshAttention();
    notifyListeners();
    await _persistNow();
  }

  void completeTask(String taskId) {
    final task = taskById(taskId);
    if (task == null || task.state == SprintTaskState.completed) return;
    task.state = SprintTaskState.completed;
    final block = _blockForTask(taskId);
    if (block != null) {
      block
        ..completed = true
        ..status = SprintScheduleBlockStatus.executed;
    }
    _recordActivity(
      type: SprintActivityEventType.taskCompleted,
      projectId: task.projectId,
      taskId: task.id,
      blockId: block?.id,
    );
    final next = _nextBlockedTask(task);
    if (next != null) next.state = SprintTaskState.scheduled;
    _refreshAttention();
    notifyListeners();
    _queuePersist();
  }


  void postponeTask(String taskId, SprintPostponeType type) {
    final task = taskById(taskId);
    if (task == null ||
        task.state == SprintTaskState.completed ||
        task.state == SprintTaskState.cancelled) {
      return;
    }
    final delta = type == SprintPostponeType.nextWeek ? 7 : 1;
    var start = task.startDate.add(Duration(days: delta));
    final lower = projectScheduleLowerBound(task.projectId);
    if (lower != null && start.isBefore(lower)) start = lower;
    final days = math.max(0, task.endDate.difference(task.startDate).inDays);
    task
      ..startDate = start
      ..endDate = start.add(Duration(days: days));
    _syncBlockFromTask(task);
    _recordActivity(
      type: SprintActivityEventType.taskPostponed,
      projectId: task.projectId,
      taskId: task.id,
      blockId: _blockForTask(task.id)?.id,
      payload: <String, String>{'type': type.name},
    );
    _refreshAttention();
    notifyListeners();
    _queuePersist();
  }

  Future<void> syncGoogleCalendar() async {
    if (_accountOperationInProgress) return;
    _accountOperationInProgress = true;
    notifyListeners();
    try {
      await _syncGoogleCalendarInternal(
        anchor: _selectedDate,
        replace: true,
      );
    } finally {
      _accountOperationInProgress = false;
      notifyListeners();
    }
  }

  void ensureCalendarRangeFor(
    DateTime anchor, {
    bool immediate = false,
  }) {
    if (_calendarState == SprintCalendarConnectionState.notConnected &&
        _externalEvents.isEmpty) {
      return;
    }
    final day = _day(anchor);
    final loadedStart = _calendarLoadedStart;
    final loadedEnd = _calendarLoadedEnd;
    if (loadedStart != null &&
        loadedEnd != null &&
        !day.isBefore(loadedStart) &&
        !day.isAfter(loadedEnd)) {
      return;
    }
    _calendarRangeDebounce?.cancel();
    if (immediate) {
      unawaited(
        _syncGoogleCalendarInternal(
          anchor: day,
          replace: false,
        ),
      );
      return;
    }
    _calendarRangeDebounce = Timer(
      const Duration(milliseconds: 280),
      () {
        unawaited(
          _syncGoogleCalendarInternal(
            anchor: day,
            replace: false,
          ),
        );
      },
    );
  }

  Future<void> _syncGoogleCalendarInternal({
    DateTime? anchor,
    bool replace = true,
  }) async {
    final generation = ++_calendarSyncGeneration;
    final center = weekStart(anchor ?? _selectedDate);
    final rangeStart = center.subtract(const Duration(days: 28));
    final rangeEnd = center.add(const Duration(days: 42));
    _calendarState = SprintCalendarConnectionState.syncing;
    _calendarError = null;
    notifyListeners();
    try {
      final events = await _calendarService.listEvents(
        calendarId: _googleCalendarId,
        timeMin: rangeStart,
        timeMax: rangeEnd.add(const Duration(days: 1)),
        maxResults: 500,
      );
      if (generation != _calendarSyncGeneration) return;
      final mapped = events
          .map(_mapGoogleEvent)
          .whereType<SprintExternalEvent>()
          .toList(growable: false);
      if (replace) {
        _externalEvents
          ..clear()
          ..addAll(mapped);
        _calendarLoadedStart = rangeStart;
        _calendarLoadedEnd = rangeEnd;
      } else {
        _externalEvents.removeWhere((event) {
          final eventStart = _day(event.start);
          final eventEnd = event.allDay
              ? _day(event.end.subtract(const Duration(days: 1)))
              : _day(event.end);
          return !eventEnd.isBefore(rangeStart) &&
              !eventStart.isAfter(rangeEnd);
        });
        final byId = <String, SprintExternalEvent>{
          for (final event in _externalEvents) event.id: event,
          for (final event in mapped) event.id: event,
        };
        _externalEvents
          ..clear()
          ..addAll(byId.values);
        final loadedStart = _calendarLoadedStart;
        final loadedEnd = _calendarLoadedEnd;
        final overlapsLoadedRange = loadedStart != null &&
            loadedEnd != null &&
            !rangeEnd.isBefore(
              loadedStart.subtract(const Duration(days: 1)),
            ) &&
            !rangeStart.isAfter(
              loadedEnd.add(const Duration(days: 1)),
            );
        if (overlapsLoadedRange) {
          _calendarLoadedStart =
              rangeStart.isBefore(loadedStart) ? rangeStart : loadedStart;
          _calendarLoadedEnd =
              rangeEnd.isAfter(loadedEnd) ? rangeEnd : loadedEnd;
        } else {
          _calendarLoadedStart = rangeStart;
          _calendarLoadedEnd = rangeEnd;
        }
      }
      _externalEvents.sort((a, b) => a.start.compareTo(b.start));
      _calendarState = SprintCalendarConnectionState.connected;
      _calendarError = null;
      _refreshAttention();
      notifyListeners();
      await _persistNow();
    } catch (error) {
      if (generation != _calendarSyncGeneration) return;
      _calendarState = SprintCalendarConnectionState.failed;
      _calendarError = error.toString();
      notifyListeners();
    }
  }

  void disconnectGoogleCalendar() {
    if (_accountOperationInProgress) return;
    _calendarRangeDebounce?.cancel();
    _calendarSyncGeneration += 1;
    _externalEvents.clear();
    _calendarLoadedStart = null;
    _calendarLoadedEnd = null;
    _calendarState = SprintCalendarConnectionState.notConnected;
    _calendarError = null;
    notifyListeners();
    _queuePersist();
  }

  String projectName(String? projectId) {
    return projectById(projectId)?.name ?? '프로젝트 없음';
  }

  void _normalizeAllDayData() {
    final normalizedBlocks = <SprintScheduleBlock>[];
    for (final task in _tasks) {
      final taskBlocks = _blocks.where((block) => block.taskId == task.id).toList();
      if (taskBlocks.isNotEmpty) {
        final earliest = taskBlocks
            .map((block) => _day(block.start))
            .reduce((a, b) => a.isBefore(b) ? a : b);
        final latest = taskBlocks
            .map((block) => _inclusiveEnd(block.end))
            .reduce((a, b) => a.isAfter(b) ? a : b);
        task
          ..startDate = earliest
          ..endDate = latest.isBefore(earliest) ? earliest : latest;
        final source = taskBlocks.firstWhere(
          (block) => block.status == SprintScheduleBlockStatus.planned,
          orElse: () => taskBlocks.first,
        );
        normalizedBlocks.add(
          SprintScheduleBlock(
            id: source.id,
            taskId: task.id,
            start: task.startDate,
            end: _exclusiveEnd(task.endDate),
            allDay: true,
            completed: task.state == SprintTaskState.completed,
            status: task.state == SprintTaskState.completed
                ? SprintScheduleBlockStatus.executed
                : source.status == SprintScheduleBlockStatus.cancelled
                    ? SprintScheduleBlockStatus.cancelled
                    : SprintScheduleBlockStatus.planned,
            locked: source.locked,
          ),
        );
        if (task.state != SprintTaskState.completed &&
            task.state != SprintTaskState.cancelled &&
            task.state != SprintTaskState.blocked) {
          task.state = SprintTaskState.scheduled;
        }
      } else {
        task.startDate = _day(task.startDate);
        task.endDate = _day(task.endDate);
        if (task.endDate.isBefore(task.startDate)) task.endDate = task.startDate;
        if (task.state != SprintTaskState.completed &&
            task.state != SprintTaskState.cancelled &&
            task.state != SprintTaskState.blocked) {
          task.state = SprintTaskState.ready;
        }
      }
      task.startDate = _day(task.startDate);
      task.endDate = _day(task.endDate);
    }
    _blocks
      ..clear()
      ..addAll(normalizedBlocks);
  }

  SprintWorkspaceScope _validatedScope(SprintWorkspaceScope scope) {
    if (scope.type == SprintWorkspaceScopeType.project &&
        projectById(scope.projectId)?.status != SprintProjectStatus.active) {
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
    switch (_workspaceScope.type) {
      case SprintWorkspaceScopeType.all:
        return projectById(item.projectId)?.status == SprintProjectStatus.active;
      case SprintWorkspaceScopeType.project:
        return item.projectId == _workspaceScope.projectId;
    }
  }

  bool _taskBelongsToActiveProject(SprintTask task) {
    return projectById(task.projectId)?.status == SprintProjectStatus.active;
  }

  bool _validProjectDateRange(DateTime? start, DateTime? target) {
    return start == null || target == null || !start.isAfter(target);
  }

  SprintPlacementValidation _validateTaskDates({
    required String? projectId,
    required DateTime startDate,
    required DateTime endDate,
    String? taskId,
    String? blockId,
    bool allowPastDate = false,
  }) {
    final validation = _schedulingEngine.validatePlacement(
      start: _day(startDate),
      end: _exclusiveEnd(_day(endDate)),
      ignoringBlockId: blockId,
      projectId: projectId,
      taskId: taskId,
      notBefore: projectScheduleLowerBound(projectId),
      allowPastDate: allowPastDate,
    );
    final conflicts = <SprintScheduleConflict>[...validation.conflicts];
    final target = projectById(projectId)?.targetDate;
    if (target != null && _day(endDate).isAfter(_day(target))) {
      conflicts.add(
        SprintScheduleConflict(
          id: 'after-target-${taskId ?? 'new'}-${endDate.millisecondsSinceEpoch}',
          type: SprintConflictType.afterProjectTargetDate,
          title: '목표 완료일 이후 업무',
          description: '업무 종료일이 프로젝트 목표 완료일보다 늦습니다.',
          projectId: projectId,
          taskId: taskId,
          blockId: blockId,
        ),
      );
    }
    return SprintPlacementValidation(
      valid: conflicts.isEmpty,
      conflicts: conflicts,
    );
  }

  bool _isHardDateConflict(SprintScheduleConflict conflict) {
    return conflict.type == SprintConflictType.invalidDateRange ||
        conflict.type == SprintConflictType.pastDate ||
        conflict.type == SprintConflictType.beforeProjectStart;
  }

  String _dateConflictMessage(List<SprintScheduleConflict> conflicts) {
    if (conflicts.any((value) => value.type == SprintConflictType.invalidDateRange)) {
      return '종료일은 시작일보다 빠를 수 없습니다.';
    }
    if (conflicts.any((value) => value.type == SprintConflictType.beforeProjectStart)) {
      return '프로젝트 목표 시작일 이전에는 업무를 배치할 수 없습니다.';
    }
    if (conflicts.any((value) => value.type == SprintConflictType.pastDate)) {
      return '과거 날짜에는 새 업무를 배치할 수 없습니다.';
    }
    return '업무 날짜를 확인하세요.';
  }

  SprintScheduleBlock? _blockForTask(String taskId) {
    for (final block in _blocks) {
      if (block.taskId == taskId &&
          block.status != SprintScheduleBlockStatus.cancelled) {
        return block;
      }
    }
    return null;
  }

  void _syncBlockFromTask(SprintTask task, {bool? locked}) {
    var block = _blockForTask(task.id);
    if (block == null) {
      block = SprintScheduleBlock(
        id: _newId('block'),
        taskId: task.id,
        start: task.startDate,
        end: _exclusiveEnd(task.endDate),
        allDay: true,
        locked: locked ?? false,
      );
      _blocks.add(block);
    } else {
      block
        ..start = _day(task.startDate)
        ..end = _exclusiveEnd(task.endDate)
        ..allDay = true
        ..locked = locked ?? block.locked
        ..status = task.state == SprintTaskState.completed
            ? SprintScheduleBlockStatus.executed
            : SprintScheduleBlockStatus.planned
        ..completed = task.state == SprintTaskState.completed;
    }
  }

  void _refreshAttention() {
    _pruneConflictResolutions();
    _attentionItems.clear();
    final today = _day(DateTime.now());
    for (final project in _projects) {
      if (project.status != SprintProjectStatus.active) continue;
      final incomplete = _tasks.where((task) {
        return task.projectId == project.id &&
            task.state != SprintTaskState.completed &&
            task.state != SprintTaskState.cancelled;
      }).toList(growable: false);
      if (project.targetDate != null && incomplete.isNotEmpty) {
        final latest = incomplete
            .map((task) => task.endDate)
            .reduce((a, b) => a.isAfter(b) ? a : b);
        if (latest.isAfter(_day(project.targetDate!))) {
          _attentionItems.add(
            SprintAttentionItem(
              id: 'target-risk-${project.id}',
              title: '목표 완료일 위험',
              description: '${project.name}의 계획 완료일이 목표 완료일보다 늦습니다.',
              projectId: project.id,
              conflictType: SprintConflictType.targetDateRisk,
            ),
          );
        }
      }
    }
    for (final task in _tasks) {
      if (task.state == SprintTaskState.completed ||
          task.state == SprintTaskState.cancelled ||
          !_taskBelongsToActiveProject(task)) {
        continue;
      }
      final validation = _validateTaskDates(
        projectId: task.projectId,
        startDate: task.startDate,
        endDate: task.endDate,
        taskId: task.id,
        blockId: _blockForTask(task.id)?.id,
        allowPastDate: true,
      );
      for (final conflict in validation.conflicts) {
        if (_isConflictResolved(conflict.id)) continue;
        _attentionItems.add(
          SprintAttentionItem(
            id: conflict.id,
            title: conflict.title,
            description: conflict.description,
            projectId: task.projectId,
            taskId: task.id,
            blockId: conflict.blockId,
            conflictType: conflict.type,
            suggestedStart: conflict.suggestedStart,
          ),
        );
      }
      if (task.endDate.isBefore(today)) {
        _attentionItems.add(
          SprintAttentionItem(
            id: 'overdue-${task.id}',
            title: task.priority == SprintTaskPriority.high
                ? '높은 우선순위 업무 기한 초과'
                : '업무 기한 초과',
            description: '${task.title}의 종료일이 지났습니다.',
            projectId: task.projectId,
            taskId: task.id,
            blockId: _blockForTask(task.id)?.id,
          ),
        );
      }
    }
  }

  bool _isConflictResolved(String key) {
    return _conflictResolutions.any((resolution) => resolution.conflictKey == key);
  }

  void _pruneConflictResolutions() {
    final blockIds = _blocks.map((block) => block.id).toSet();
    _conflictResolutions.removeWhere((resolution) {
      final blockId = resolution.blockId;
      return blockId != null && !blockIds.contains(blockId);
    });
  }

  List<SprintDayLoad> _workloadFor(String projectId) {
    final today = _day(DateTime.now());
    final start = projectScheduleLowerBound(projectId);
    final first = start != null && start.isAfter(today) ? start : today;
    return List<SprintDayLoad>.generate(
      7,
      (index) => dayLoadFor(first.add(Duration(days: index)), projectId),
      growable: false,
    );
  }

  int _priorityWeight(SprintTaskPriority priority) {
    switch (priority) {
      case SprintTaskPriority.high:
        return 3;
      case SprintTaskPriority.normal:
        return 2;
      case SprintTaskPriority.low:
        return 1;
    }
  }

  int _priorityRank(SprintTaskPriority priority) {
    switch (priority) {
      case SprintTaskPriority.high:
        return 0;
      case SprintTaskPriority.normal:
        return 1;
      case SprintTaskPriority.low:
        return 2;
    }
  }

  int _taskStateRank(SprintTask task) {
    final today = _day(DateTime.now());
    if (task.state != SprintTaskState.completed && task.endDate.isBefore(today)) {
      return 0;
    }
    if (task.state == SprintTaskState.completed) return 3;
    return 1;
  }

  int _compareTasks(SprintTask a, SprintTask b) {
    final state = _taskStateRank(a).compareTo(_taskStateRank(b));
    if (state != 0) return state;
    final priority = _priorityRank(a.priority).compareTo(_priorityRank(b.priority));
    if (priority != 0) return priority;
    final end = a.endDate.compareTo(b.endDate);
    if (end != 0) return end;
    return a.order.compareTo(b.order);
  }

  _ParsedTask _parseTask(String raw) {
    var title = raw.trim();
    if (title.isEmpty) return _ParsedTask.error('업무명을 입력하세요.');
    var priority = SprintTaskPriority.normal;
    if (RegExp(r'(^|\s)(높음|긴급|중요)(\s|$)').hasMatch(title)) {
      priority = SprintTaskPriority.high;
      title = title.replaceAll(RegExp(r'(^|\s)(높음|긴급|중요)(?=\s|$)'), ' ');
    } else if (RegExp(r'(^|\s)낮음(\s|$)').hasMatch(title)) {
      priority = SprintTaskPriority.low;
      title = title.replaceAll(RegExp(r'(^|\s)낮음(?=\s|$)'), ' ');
    } else {
      title = title.replaceAll(RegExp(r'(^|\s)보통(?=\s|$)'), ' ');
    }
    final now = _day(DateTime.now());
    final datePattern = RegExp(
      r'오늘|내일|모레|월요일|화요일|수요일|목요일|금요일|토요일|일요일',
    );
    final matches = datePattern.allMatches(title).toList(growable: false);
    DateTime resolve(String token) {
      if (token == '오늘') return now;
      if (token == '내일') return now.add(const Duration(days: 1));
      if (token == '모레') return now.add(const Duration(days: 2));
      const weekdays = <String, int>{
        '월요일': DateTime.monday,
        '화요일': DateTime.tuesday,
        '수요일': DateTime.wednesday,
        '목요일': DateTime.thursday,
        '금요일': DateTime.friday,
        '토요일': DateTime.saturday,
        '일요일': DateTime.sunday,
      };
      var delta = weekdays[token]! - now.weekday;
      if (delta <= 0) delta += 7;
      return now.add(Duration(days: delta));
    }
    var start = matches.isEmpty ? _selectedDate : resolve(matches.first.group(0)!);
    var end = matches.length < 2 ? start : resolve(matches[1].group(0)!);
    if (end.isBefore(start)) end = start;
    title = title.replaceAll(datePattern, ' ');
    title = title.replaceAll(RegExp(r'(오전|오후)?\s*\d{1,2}\s*시(?:\s*\d{1,2}\s*분)?'), ' ');
    title = title.replaceAll(RegExp(r'\d+\s*(시간|분)'), ' ');
    title = title.replaceAll('저녁', ' ');
    title = title.replaceAll('부터', ' ');
    title = title.replaceAll('까지', ' ');
    title = title.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (title.isEmpty) return _ParsedTask.error('업무명을 입력하세요.');
    return _ParsedTask(
      title: title,
      priority: priority,
      startDate: _day(start),
      endDate: _day(end),
    );
  }

  SprintExternalEvent? _mapGoogleEvent(gcal.Event event) {
    if (event.status == 'cancelled') return null;
    final start = event.start?.dateTime?.toLocal() ?? event.start?.date;
    if (start == null) return null;
    final allDay = event.start?.date != null;
    final end = event.end?.dateTime?.toLocal() ??
        event.end?.date ??
        start.add(allDay ? const Duration(days: 1) : const Duration(minutes: 30));
    final title = event.summary?.trim();
    return SprintExternalEvent(
      id: event.id ?? 'google-${start.microsecondsSinceEpoch}',
      title: title == null || title.isEmpty ? '제목 없는 외부 일정' : title,
      start: start,
      end: end,
      allDay: allDay,
      blocksTime: event.transparency != 'transparent',
      sourceUrl: event.htmlLink,
    );
  }

  SprintProjectReport _buildProjectReport({
    required SprintProject project,
    required DateTime completedAt,
    required String? reviewNote,
    required int conflictCount,
  }) {
    final tasks = tasksForProject(project.id);
    final completed = tasks
        .where((task) => task.state == SprintTaskState.completed)
        .toList(growable: false);
    var onTime = 0;
    var overdue = 0;
    for (final task in completed) {
      final events = _activityEvents.where((event) {
        return event.taskId == task.id &&
            event.type == SprintActivityEventType.taskCompleted;
      }).toList(growable: false)
        ..sort((a, b) => b.occurredAt.compareTo(a.occurredAt));
      final actual = events.isEmpty ? completedAt : events.first.occurredAt;
      final dueBoundary = DateTime(
        task.endDate.year,
        task.endDate.month,
        task.endDate.day,
        23,
        59,
        59,
      );
      if (actual.isAfter(dueBoundary)) {
        overdue += 1;
      } else {
        onTime += 1;
      }
    }
    final targetDelta = project.targetDate == null
        ? 0
        : _day(completedAt).difference(_day(project.targetDate!)).inDays;
    return SprintProjectReport(
      id: _newId('report'),
      projectId: project.id,
      completedAt: completedAt,
      totalTaskCount: tasks.length,
      completedTaskCount: completed.length,
      cancelledTaskCount:
          tasks.where((task) => task.state == SprintTaskState.cancelled).length,
      highPriorityCompletedCount: completed
          .where((task) => task.priority == SprintTaskPriority.high)
          .length,
      onTimeCompletedCount: onTime,
      overdueCompletedCount: overdue,
      postponeCount: _activityEvents.where((event) {
        return event.projectId == project.id &&
            event.type == SprintActivityEventType.taskPostponed;
      }).length,
      conflictCount: conflictCount,
      resolvedConflictCount: _conflictResolutions.where((resolution) {
        final block = blockById(resolution.blockId);
        return taskById(block?.taskId)?.projectId == project.id;
      }).length,
      targetDeltaDays: targetDelta,
      reviewNote: reviewNote,
    );
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

  int _nextOrder(String? projectId) {
    final values = _tasks
        .where((task) => task.projectId == projectId)
        .map((task) => task.order)
        .toList(growable: false);
    if (values.isEmpty) return 0;
    return values.reduce((a, b) => a > b ? a : b) + 1;
  }

  int _nextSequenceValue() {
    var value = DateTime.now().microsecondsSinceEpoch;
    final ids = <String>[
      ..._projects.map((item) => item.id),
      ..._tasks.map((item) => item.id),
      ..._blocks.map((item) => item.id),
      ..._projectReports.map((item) => item.id),
      ..._activityEvents.map((item) => item.id),
    ];
    for (final id in ids) {
      final match = RegExp(r'(\d+)$').firstMatch(id);
      final parsed = int.tryParse(match?.group(1) ?? '');
      if (parsed != null && parsed >= value) value = parsed + 1;
    }
    return value;
  }

  String _newId(String prefix) {
    _sequence = math.max(
      _sequence + 1,
      DateTime.now().microsecondsSinceEpoch,
    ).toInt();
    return '$prefix-$_sequence';
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
        id: _newId('activity'),
        type: type,
        occurredAt: DateTime.now(),
        projectId: projectId,
        taskId: taskId,
        blockId: blockId,
        payload: payload,
      ),
    );
  }

  DateTime _exclusiveEnd(DateTime inclusiveEnd) {
    final day = _day(inclusiveEnd);
    return day.add(const Duration(days: 1));
  }

  DateTime _inclusiveEnd(DateTime exclusiveEnd) {
    final normalized = _day(exclusiveEnd);
    return normalized.subtract(const Duration(days: 1));
  }

  static DateTime _day(DateTime value) {
    return DateTime(value.year, value.month, value.day);
  }

  Future<void> _persistNow() async {
    if (!_initialized && !_initializing) return;
    await _database.replaceSnapshot(
      SprintDatabaseSnapshot(
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
        lastObservedToday: _lastObservedToday,
        weekMode: _weekMode,
        googleCalendarId: _googleCalendarId,
        googleCalendarIdLocked: _googleCalendarIdLocked,
      ),
    );
  }

  void _queuePersist() {
    _writeQueue = _writeQueue.then((_) => _persistNow());
  }

  @override
  void dispose() {
    _calendarRangeDebounce?.cancel();
    super.dispose();
  }
}

class _ParsedTask {
  const _ParsedTask({
    required this.title,
    required this.priority,
    required this.startDate,
    required this.endDate,
    this.error,
  });

  factory _ParsedTask.error(String message) {
    final epoch = DateTime(1970);
    return _ParsedTask(
      title: '',
      priority: SprintTaskPriority.normal,
      startDate: epoch,
      endDate: epoch,
      error: message,
    );
  }

  final String title;
  final SprintTaskPriority priority;
  final DateTime startDate;
  final DateTime endDate;
  final String? error;
}
