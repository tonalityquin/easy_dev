import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:googleapis/calendar/v3.dart' as gcal;

import '../../../app/auth/google_auth_session.dart';

import '../../../shared/google_calendar/google_event_colors.dart';
import '../../headquarter/widgets/calendar/google_calendar_service.dart';
import 'sprint_calendar_sync_coordinator.dart';
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
        _schedulingEngine = schedulingEngine ?? const SprintSchedulingEngine() {
    _calendarSyncCoordinator = SprintCalendarSyncCoordinator(
      calendarService: _calendarService,
    );
    _identitySubscription =
        GoogleAuthSession.instance.identityChanges.listen(_handleIdentityChange);
  }

  static const int maxActiveProjectCount = 11;

  final GoogleCalendarService _calendarService;
  late final SprintCalendarSyncCoordinator _calendarSyncCoordinator;
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
  final List<SprintGoogleAccount> _googleAccounts = <SprintGoogleAccount>[];
  final List<SprintCalendarProfile> _calendarProfiles =
      <SprintCalendarProfile>[];

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
  String? _activeCalendarProfileId;
  DateTime _lastObservedToday = _day(DateTime.now());
  DateTime? _calendarLoadedStart;
  DateTime? _calendarLoadedEnd;
  Timer? _calendarRangeDebounce;
  int _calendarSyncGeneration = 0;
  Future<void> _writeQueue = Future<void>.value();
  Future<void> _calendarWriteQueue = Future<void>.value();
  StreamSubscription<GoogleAuthIdentity?>? _identitySubscription;
  String? _projectInputError;

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
  List<SprintTask> get tasks => List<SprintTask>.unmodifiable(
        _tasks.where((task) => !task.deleteAfterSync),
      );
  List<SprintScheduleBlock> get blocks =>
      List<SprintScheduleBlock>.unmodifiable(_blocks);
  List<SprintExternalEvent> get externalEvents {
    final profileId = _activeCalendarProfileId;
    if (profileId == null) return const <SprintExternalEvent>[];
    return List<SprintExternalEvent>.unmodifiable(
      _externalEvents.where(
        (event) => event.calendarProfileId == profileId,
      ),
    );
  }
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
  String? get projectInputError => _projectInputError;
  bool get initialized => _initialized;
  bool get initializing => _initializing;
  bool get accountSaving => _accountOperationInProgress;
  bool get accountBusy => _accountOperationInProgress;
  List<SprintGoogleAccount> get googleAccounts =>
      List<SprintGoogleAccount>.unmodifiable(_googleAccounts);
  List<SprintCalendarProfile> get calendarProfiles =>
      List<SprintCalendarProfile>.unmodifiable(
        _calendarProfiles.where((profile) => profile.enabled),
      );
  String? get activeCalendarProfileId => _activeCalendarProfileId;
  SprintCalendarProfile? get activeCalendarProfile =>
      calendarProfileById(_activeCalendarProfileId);
  SprintGoogleAccount? get activeGoogleAccount =>
      googleAccountById(activeCalendarProfile?.accountId);
  String get googleCalendarId => activeCalendarProfile?.calendarId ?? 'primary';
  bool get googleCalendarIdLocked => activeCalendarProfile?.locked ?? false;
  String get activeCalendarLabel =>
      activeCalendarProfile?.label.trim().isNotEmpty == true
          ? activeCalendarProfile!.label.trim()
          : 'Google 캘린더';
  String get activeGoogleEmail => activeGoogleAccount?.email.trim() ?? '';
  bool get isTodaySelected =>
      _selectedDate.isAtSameMomentAs(_day(DateTime.now()));
  bool get isCurrentWeekSelected =>
      weekStart(_selectedDate).isAtSameMomentAs(weekStart(DateTime.now()));

  int get activeProjectCount => projects.length;
  bool get canCreateProject =>
      activeProjectCount < maxActiveProjectCount &&
      availableProjectColorIds().isNotEmpty;
  bool get hasLinkedGoogleEvents => _tasks.any(
        (task) => task.hasGoogleEvent,
      );

  List<String> availableProjectColorIds({String? excludingProjectId}) {
    final used = _projects
        .where(
          (project) =>
              project.status == SprintProjectStatus.active &&
              project.id != excludingProjectId &&
              googleEventColorIds.contains(project.googleColorId),
        )
        .map((project) => project.googleColorId)
        .toSet();
    return googleEventColorIds
        .where((colorId) => !used.contains(colorId))
        .toList(growable: false);
  }

  Map<String, String> projectColorOwners({String? excludingProjectId}) {
    return <String, String>{
      for (final project in _projects)
        if (project.status == SprintProjectStatus.active &&
            project.id != excludingProjectId &&
            googleEventColorIds.contains(project.googleColorId))
          project.googleColorId: project.name,
    };
  }

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

  void _ensureCalendarProfileMigration(SprintDatabaseSnapshot snapshot) {
    final hasUnassignedLegacyTasks = _tasks.any(
      (task) =>
          task.googleCalendarProfileId?.trim().isNotEmpty != true &&
          (task.hasGoogleEvent ||
              task.googleCalendarId?.trim().isNotEmpty == true),
    );
    final hasUnassignedLegacyEvents = _externalEvents.any(
      (event) => event.calendarProfileId.trim().isEmpty,
    );
    final hasLegacyData = snapshot.legacyCalendarConfigured ||
        hasUnassignedLegacyTasks ||
        hasUnassignedLegacyEvents;
    if (_calendarProfiles.isEmpty && hasLegacyData) {
      final now = DateTime.now();
      final account = SprintGoogleAccount(
        id: 'legacy-google-account',
        email: '',
        displayName: '',
        requiresReauthentication: true,
        createdAt: now,
        updatedAt: now,
      );
      final profile = SprintCalendarProfile(
        id: 'legacy-calendar-profile',
        accountId: account.id,
        calendarId: snapshot.googleCalendarId.trim().isEmpty
            ? 'primary'
            : snapshot.googleCalendarId.trim(),
        label: '기존 Google 캘린더',
        locked: snapshot.googleCalendarIdLocked,
        sortOrder: 0,
        createdAt: now,
        updatedAt: now,
      );
      _googleAccounts.add(account);
      _calendarProfiles.add(profile);
      _activeCalendarProfileId = profile.id;
    }
    if (_activeCalendarProfileId == null ||
        calendarProfileById(_activeCalendarProfileId)?.enabled != true) {
      final enabled = _calendarProfiles.where((profile) => profile.enabled);
      _activeCalendarProfileId = enabled.isEmpty ? null : enabled.first.id;
    }
    final activeProfile = activeCalendarProfile;
    if (activeProfile == null) return;
    for (final task in _tasks) {
      if (task.googleCalendarProfileId?.trim().isNotEmpty == true) continue;
      if (task.hasGoogleEvent ||
          task.googleCalendarId?.trim().isNotEmpty == true) {
        task.googleCalendarProfileId = activeProfile.id;
      }
    }
    for (var index = 0; index < _externalEvents.length; index += 1) {
      final event = _externalEvents[index];
      if (event.calendarProfileId.trim().isNotEmpty) continue;
      _externalEvents[index] = SprintExternalEvent(
        id: '${activeProfile.id}:${event.googleEventId}',
        googleEventId: event.googleEventId,
        calendarProfileId: activeProfile.id,
        title: event.title,
        start: event.start,
        end: event.end,
        allDay: event.allDay,
        blocksTime: event.blocksTime,
        sourceUrl: event.sourceUrl,
        colorId: event.colorId,
        managedBySprint: event.managedBySprint,
        linkedTaskId: event.linkedTaskId,
        linkedProjectId: event.linkedProjectId,
      );
    }
  }

  void _handleIdentityChange(GoogleAuthIdentity? identity) {
    if (_accountOperationInProgress) return;
    final profile = activeCalendarProfile;
    final account = activeGoogleAccount;
    if (profile == null || account == null) return;
    if (account.normalizedEmail.isEmpty) {
      account
        ..requiresReauthentication = true
        ..updatedAt = DateTime.now();
      _calendarService.resetAuthenticatedClient();
      _calendarState = SprintCalendarConnectionState.reauthenticationRequired;
      _calendarError = null;
      notifyListeners();
      _queuePersist();
      return;
    }
    final matches = identity != null &&
        account.normalizedEmail.isNotEmpty &&
        identity.normalizedEmail == account.normalizedEmail;
    if (!matches) {
      account
        ..requiresReauthentication = true
        ..updatedAt = DateTime.now();
      _calendarService.resetAuthenticatedClient();
      _calendarState = SprintCalendarConnectionState.reauthenticationRequired;
      _calendarError = null;
      notifyListeners();
      _queuePersist();
      return;
    }
    account
      ..googleUserId = identity.id
      ..email = identity.email.trim()
      ..displayName = identity.displayName.trim()
      ..requiresReauthentication = false
      ..updatedAt = DateTime.now();
    if (_calendarState ==
        SprintCalendarConnectionState.reauthenticationRequired) {
      _calendarState = SprintCalendarConnectionState.cached;
      _calendarError = null;
    }
    notifyListeners();
    _queuePersist();
  }

  bool _activeIdentityMatches() {
    final account = activeGoogleAccount;
    final identity = GoogleAuthSession.instance.currentIdentity;
    return account != null &&
        identity != null &&
        account.normalizedEmail.isNotEmpty &&
        account.normalizedEmail == identity.normalizedEmail;
  }

  void _protectActiveProfileAfterAuthenticationChange() {
    final account = activeGoogleAccount;
    if (account == null || _activeIdentityMatches()) return;
    account
      ..requiresReauthentication = true
      ..updatedAt = DateTime.now();
    _calendarService.resetAuthenticatedClient();
    _calendarState = SprintCalendarConnectionState.reauthenticationRequired;
  }

  SprintCalendarConnectionState _initialCalendarState() {
    final profile = activeCalendarProfile;
    final account = activeGoogleAccount;
    if (profile == null || account == null || !profile.enabled) {
      return SprintCalendarConnectionState.notConnected;
    }
    final identity = GoogleAuthSession.instance.currentIdentity;
    final matches = identity != null &&
        account.email.trim().isNotEmpty &&
        identity.normalizedEmail == account.normalizedEmail;
    if (!matches) {
      account.requiresReauthentication = true;
      return SprintCalendarConnectionState.reauthenticationRequired;
    }
    account.requiresReauthentication = false;
    return SprintCalendarConnectionState.cached;
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
      _googleAccounts
        ..clear()
        ..addAll(snapshot.googleAccounts);
      _calendarProfiles
        ..clear()
        ..addAll(snapshot.calendarProfiles);
      _activeCalendarProfileId = snapshot.activeCalendarProfileId;
      _ensureCalendarProfileMigration(snapshot);
      final currentToday = _day(DateTime.now());
      final restoredSelectedDate = _day(snapshot.selectedDate);
      final restoredObservedToday = _day(snapshot.lastObservedToday);
      _selectedDate = restoredSelectedDate.isAtSameMomentAs(restoredObservedToday)
          ? currentToday
          : restoredSelectedDate;
      _lastObservedToday = currentToday;
      _workspaceScope = _validatedScope(snapshot.workspaceScope);
      _weekMode = snapshot.weekMode;
      _calendarState = _initialCalendarState();
      _sequence = _nextSequenceValue();
      _ensureProjectColors();
      _normalizeAllDayData();
      _normalizeGoogleSyncState();
      _refreshAttention();
      _initialized = true;
      await _persistNow();
      if (_calendarState == SprintCalendarConnectionState.cached) {
        ensureCalendarRangeFor(_selectedDate, immediate: true);
      }
      _retryPendingTaskSyncs();
    } finally {
      _initializing = false;
      notifyListeners();
    }
  }

  Future<void> flush() async {
    await _writeQueue;
    await _calendarWriteQueue;
    if (_initialized) await _persistNow();
  }

  Future<SprintProject?> createProject({
    required String name,
    required String iconKey,
    required String googleColorId,
    DateTime? targetStartDate,
    DateTime? targetDate,
  }) async {
    _projectInputError = null;
    final normalizedName = name.trim();
    final start = targetStartDate == null ? null : _day(targetStartDate);
    final target = targetDate == null ? null : _day(targetDate);
    if (projects.length >= maxActiveProjectCount) {
      _projectInputError = '활성 프로젝트는 최대 11개까지 만들 수 있습니다.';
      return null;
    }
    if (!availableProjectColorIds().contains(googleColorId)) {
      _projectInputError = '다른 활성 프로젝트에서 사용하지 않는 색상을 선택하세요.';
      return null;
    }
    if (normalizedName.isEmpty || !_validProjectDateRange(start, target)) {
      _projectInputError = '프로젝트 정보를 확인하세요.';
      return null;
    }
    final project = SprintProject(
      id: _newId('project'),
      name: normalizedName,
      iconKey: sprintProjectIcons.containsKey(iconKey) ? iconKey : 'folder',
      targetStartDate: start,
      targetDate: target,
      googleColorId: googleColorId,
      calendarSyncEnabled: true,
    );
    _projects.add(project);
    _workspaceScope = SprintWorkspaceScope.project(project.id);
    _recordActivity(
      type: SprintActivityEventType.projectCreated,
      projectId: project.id,
      payload: <String, String>{'google_color_id': googleColorId},
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
    required String googleColorId,
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
    if (!availableProjectColorIds(excludingProjectId: projectId)
        .contains(googleColorId)) {
      return const SprintOperationResult(
        success: false,
        message: '다른 활성 프로젝트에서 사용하지 않는 색상을 선택하세요.',
      );
    }
    final colorChanged = project.googleColorId != googleColorId;
    project
      ..name = normalizedName
      ..iconKey = sprintProjectIcons.containsKey(iconKey) ? iconKey : 'folder'
      ..targetStartDate = start
      ..targetDate = target
      ..googleColorId = googleColorId;
    _recordActivity(
      type: SprintActivityEventType.projectUpdated,
      projectId: project.id,
      payload: <String, String>{
        'google_color_id': googleColorId,
      },
    );
    _refreshAttention();
    notifyListeners();
    await _persistNow();
    final syncTargets = <SprintTask>{
      if (colorChanged)
        ..._tasks.where(
          (task) =>
              task.projectId == projectId &&
              task.state != SprintTaskState.cancelled &&
              _blockForTask(task.id) != null,
        ),
    };
    for (final task in syncTargets) {
      _scheduleTaskCalendarUpsert(task.id);
    }
    return const SprintOperationResult(
      success: true,
      message: '프로젝트를 수정했습니다.',
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
    final deleteTargets = <String>[];
    if (cancelRemaining) {
      for (final task in remaining) {
        task
          ..state = SprintTaskState.cancelled
          ..deleteAfterSync = false;
        final block = _blockForTask(task.id);
        if (block != null) block.status = SprintScheduleBlockStatus.cancelled;
        deleteTargets.add(task.id);
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
    for (final taskId in deleteTargets) {
      _scheduleTaskCalendarDelete(taskId, deleteAfterSync: false);
    }
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
    if (projects.length >= maxActiveProjectCount) return false;
    final available = availableProjectColorIds(excludingProjectId: projectId);
    if (available.isEmpty) return false;
    final colorId = available.contains(project.googleColorId)
        ? project.googleColorId
        : available.first;
    project
      ..status = SprintProjectStatus.active
      ..googleColorId = colorId
      ..calendarSyncEnabled = true
      ..completedAt = null
      ..archivedAt = null
      ..reopenedAt = DateTime.now();
    _workspaceScope = SprintWorkspaceScope.project(projectId);
    _recordActivity(
      type: SprintActivityEventType.projectReopened,
      projectId: projectId,
      payload: <String, String>{'google_color_id': colorId},
    );
    _refreshAttention();
    notifyListeners();
    await _persistNow();
    for (final task in _tasks.where(
      (task) =>
          task.projectId == projectId &&
          task.state != SprintTaskState.completed &&
          task.state != SprintTaskState.cancelled &&
          _blockForTask(task.id) != null,
    )) {
      _scheduleTaskCalendarUpsert(task.id);
    }
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
    await _calendarWriteQueue;
    final project = projectById(projectId);
    if (project == null) return false;
    final projectTasks = _tasks
        .where((task) => task.projectId == projectId)
        .toList(growable: false);
    final pendingDeleteIds = <String>[];
    for (final task in projectTasks) {
      final remoteLinked = task.hasGoogleEvent || task.hasPendingGoogleSync;
      if (!remoteLinked) {
        _removeTaskLocally(task);
        continue;
      }
      _blocks.removeWhere((block) => block.taskId == task.id);
      _attentionItems.removeWhere((item) => item.taskId == task.id);
      _recordActivity(
        type: SprintActivityEventType.taskDeleted,
        projectId: projectId,
        taskId: task.id,
      );
      task
        ..projectId = null
        ..state = SprintTaskState.cancelled
        ..googleSyncState = SprintGoogleSyncState.pendingDelete
        ..googleSyncError = null
        ..deleteAfterSync = true;
      pendingDeleteIds.add(task.id);
    }
    _pruneConflictResolutions();
    _attentionItems.removeWhere((item) => item.projectId == projectId);
    _projectReports.removeWhere((report) => report.projectId == projectId);
    _activityEvents.removeWhere(
      (event) => event.projectId == projectId &&
          event.type != SprintActivityEventType.taskDeleted,
    );
    _projects.remove(project);
    if (_workspaceScope.projectId == projectId) {
      _workspaceScope = const SprintWorkspaceScope.all();
    }
    _refreshAttention();
    notifyListeners();
    await _persistNow();
    for (final taskId in pendingDeleteIds) {
      final task = taskById(taskId);
      if (task?.googleCalendarProfileId == _activeCalendarProfileId) {
        _scheduleTaskCalendarDelete(taskId, deleteAfterSync: true);
      }
    }
    return true;
  }

  Future<SprintCalendarProfile> addGoogleCalendarProfile({
    required String label,
    required String calendarId,
    required bool locked,
    bool forceAccountSelection = true,
    bool makeActive = true,
  }) async {
    if (_accountOperationInProgress) {
      throw StateError('account_operation_in_progress');
    }
    final normalizedCalendarId = normalizeGoogleCalendarId(calendarId);
    final normalizedLabel = label.trim();
    if (normalizedCalendarId.isEmpty) {
      throw ArgumentError.value(calendarId, 'calendarId');
    }
    _accountOperationInProgress = true;
    _calendarRangeDebounce?.cancel();
    _calendarSyncGeneration += 1;
    _calendarError = null;
    notifyListeners();
    try {
      await _writeQueue;
      await _calendarWriteQueue;
      final identity = await GoogleAuthSession.instance.authenticateAccount(
        forceAccountSelection: forceAccountSelection,
      );
      _calendarService.resetAuthenticatedClient();
      await _calendarService.verifyCalendarAccess(
        accountEmail: identity.email,
        calendarId: normalizedCalendarId,
      );
      final now = DateTime.now();
      SprintGoogleAccount? account;
      for (final candidate in _googleAccounts) {
        final sameGoogleUser = candidate.googleUserId?.trim().isNotEmpty == true &&
            candidate.googleUserId == identity.id;
        if (sameGoogleUser ||
            candidate.normalizedEmail == identity.normalizedEmail) {
          account = candidate;
          break;
        }
      }
      if (account == null) {
        account = SprintGoogleAccount(
          id: _newId('google-account'),
          googleUserId: identity.id,
          email: identity.email.trim(),
          displayName: identity.displayName.trim(),
          createdAt: now,
          updatedAt: now,
        );
        _googleAccounts.add(account);
      } else {
        account
          ..googleUserId = identity.id
          ..email = identity.email.trim()
          ..displayName = identity.displayName.trim()
          ..requiresReauthentication = false
          ..updatedAt = now;
      }
      SprintCalendarProfile? profile;
      for (final candidate in _calendarProfiles) {
        if (candidate.accountId == account.id &&
            candidate.calendarId == normalizedCalendarId) {
          profile = candidate;
          break;
        }
      }
      if (profile == null) {
        profile = SprintCalendarProfile(
          id: _newId('calendar-profile'),
          accountId: account.id,
          calendarId: normalizedCalendarId,
          label: normalizedLabel.isEmpty
              ? identity.displayName.trim().isNotEmpty
                  ? identity.displayName.trim()
                  : identity.email.trim()
              : normalizedLabel,
          locked: locked,
          sortOrder: _calendarProfiles.length,
          createdAt: now,
          updatedAt: now,
        );
        _calendarProfiles.add(profile);
      } else {
        profile
          ..label = normalizedLabel.isEmpty ? profile.label : normalizedLabel
          ..locked = locked
          ..enabled = true
          ..lastSyncError = null
          ..updatedAt = now;
      }
      if (makeActive || _activeCalendarProfileId == null) {
        _activateProfileLocally(profile.id);
      }
      await _persistNow();
      if (_activeCalendarProfileId == profile.id) {
        await _syncGoogleCalendarInternal();
      }
      return profile;
    } catch (error) {
      _protectActiveProfileAfterAuthenticationChange();
      _calendarError = _activeIdentityMatches() ? _calendarError : error.toString();
      await _persistNow();
      rethrow;
    } finally {
      _accountOperationInProgress = false;
      notifyListeners();
    }
  }

  Future<void> switchActiveCalendarProfile(String profileId) async {
    if (_accountOperationInProgress) {
      throw StateError('account_operation_in_progress');
    }
    final profile = calendarProfileById(profileId);
    final account = accountForProfile(profileId);
    if (profile == null || account == null || !profile.enabled) {
      throw StateError('calendar_profile_not_found');
    }
    final previousProfileId = _activeCalendarProfileId;
    final previousState = _calendarState;
    final previousError = _calendarError;
    final previousGoogleUserId = account.googleUserId;
    final previousEmail = account.email;
    final previousDisplayName = account.displayName;
    final previousRequiresReauthentication =
        account.requiresReauthentication;
    final previousAccountUpdatedAt = account.updatedAt;
    var bindingCommitted = false;
    _accountOperationInProgress = true;
    _calendarRangeDebounce?.cancel();
    _calendarSyncGeneration += 1;
    _calendarState = SprintCalendarConnectionState.switching;
    _calendarError = null;
    notifyListeners();
    try {
      await _writeQueue;
      await _calendarWriteQueue;
      final expectedEmail =
          account.normalizedEmail.isEmpty ? null : account.email;
      final identity = await GoogleAuthSession.instance.authenticateAccount(
        expectedEmail: expectedEmail,
        forceAccountSelection: expectedEmail == null ||
            !isProfileAuthenticated(profileId),
      );
      _calendarService.resetAuthenticatedClient();
      await _calendarService.verifyCalendarAccess(
        accountEmail: identity.email,
        calendarId: profile.calendarId,
      );
      final verifiedAt = DateTime.now();
      account
        ..googleUserId = identity.id
        ..email = identity.email.trim()
        ..displayName = identity.displayName.trim()
        ..requiresReauthentication = false
        ..updatedAt = verifiedAt;
      profile
        ..lastSyncError = null
        ..updatedAt = verifiedAt;
      _activateProfileLocally(profile.id);
      await _persistNow();
      bindingCommitted = true;
      await _syncGoogleCalendarInternal();
    } catch (error) {
      if (!bindingCommitted) {
        account
          ..googleUserId = previousGoogleUserId
          ..email = previousEmail
          ..displayName = previousDisplayName
          ..requiresReauthentication = previousRequiresReauthentication
          ..updatedAt = previousAccountUpdatedAt;
        if (_activeCalendarProfileId != previousProfileId) {
          _activeCalendarProfileId = previousProfileId;
          _calendarLoadedStart = null;
          _calendarLoadedEnd = null;
          _calendarSyncGeneration += 1;
        }
      }
      profile
        ..lastSyncError = error.toString()
        ..updatedAt = DateTime.now();
      _calendarService.resetAuthenticatedClient();
      _protectActiveProfileAfterAuthenticationChange();
      if (bindingCommitted) {
        _calendarState = _activeIdentityMatches()
            ? SprintCalendarConnectionState.failed
            : SprintCalendarConnectionState.reauthenticationRequired;
        _calendarError = error.toString();
      } else if (_activeIdentityMatches()) {
        if (previousProfileId == profileId) {
          _calendarState = SprintCalendarConnectionState.failed;
          _calendarError = error.toString();
        } else {
          _calendarState = previousState;
          _calendarError = previousError;
        }
      } else {
        _calendarState =
            SprintCalendarConnectionState.reauthenticationRequired;
        _calendarError = error.toString();
      }
      await _persistNow();
      rethrow;
    } finally {
      _accountOperationInProgress = false;
      notifyListeners();
    }
  }

  Future<void> reconnectActiveCalendarProfile() async {
    final profileId = _activeCalendarProfileId;
    if (profileId == null) throw StateError('calendar_profile_not_found');
    await switchActiveCalendarProfile(profileId);
  }

  Future<void> updateCalendarProfile({
    required String profileId,
    required String label,
    required bool locked,
  }) async {
    final profile = calendarProfileById(profileId);
    if (profile == null) throw StateError('calendar_profile_not_found');
    profile
      ..label = label.trim().isEmpty ? profile.label : label.trim()
      ..locked = locked
      ..updatedAt = DateTime.now();
    notifyListeners();
    await _persistNow();
  }

  Future<void> removeCalendarProfile(String profileId) async {
    if (_accountOperationInProgress) {
      throw StateError('account_operation_in_progress');
    }
    final profile = calendarProfileById(profileId);
    if (profile == null) return;
    final inUse = _tasks.any(
      (task) => task.googleCalendarProfileId == profileId,
    );
    if (inUse) throw StateError('calendar_profile_in_use');
    _calendarProfiles.remove(profile);
    _externalEvents.removeWhere(
      (event) => event.calendarProfileId == profileId,
    );
    final accountStillUsed = _calendarProfiles.any(
      (candidate) => candidate.accountId == profile.accountId,
    );
    if (!accountStillUsed) {
      _googleAccounts.removeWhere((account) => account.id == profile.accountId);
    }
    var refreshSelectedProfile = false;
    if (_activeCalendarProfileId == profileId) {
      final enabled = _calendarProfiles.where((candidate) => candidate.enabled);
      _activeCalendarProfileId = enabled.isEmpty ? null : enabled.first.id;
      _calendarLoadedStart = null;
      _calendarLoadedEnd = null;
      _calendarState = _initialCalendarState();
      _calendarError = null;
      _calendarSyncGeneration += 1;
      refreshSelectedProfile =
          _calendarState == SprintCalendarConnectionState.cached;
    }
    notifyListeners();
    await _persistNow();
    if (refreshSelectedProfile) {
      ensureCalendarRangeFor(_selectedDate, immediate: true);
    }
  }

  void _activateProfileLocally(String profileId) {
    _calendarRangeDebounce?.cancel();
    _calendarSyncGeneration += 1;
    _activeCalendarProfileId = profileId;
    _calendarLoadedStart = null;
    _calendarLoadedEnd = null;
    _calendarState = SprintCalendarConnectionState.cached;
    _calendarError = null;
  }

  Future<void> saveGoogleCalendarAccount({
    required String calendarId,
    required bool locked,
  }) async {
    final profile = activeCalendarProfile;
    if (profile == null) {
      await addGoogleCalendarProfile(
        label: 'Google 캘린더',
        calendarId: calendarId,
        locked: locked,
        forceAccountSelection: false,
        makeActive: true,
      );
      return;
    }
    final normalized = normalizeGoogleCalendarId(calendarId);
    final changed = normalized != profile.calendarId;
    if (changed &&
        _tasks.any(
          (task) => task.googleCalendarProfileId == profile.id &&
              task.hasGoogleEvent,
        )) {
      throw StateError('linked_calendar_change_not_allowed');
    }
    profile
      ..calendarId = normalized
      ..locked = locked
      ..updatedAt = DateTime.now();
    if (changed) _activateProfileLocally(profile.id);
    notifyListeners();
    await _persistNow();
  }

  Future<void> saveGoogleCalendarAccountAndSync({
    required String calendarId,
    required bool locked,
  }) async {
    await saveGoogleCalendarAccount(calendarId: calendarId, locked: locked);
    await reconnectActiveCalendarProfile();
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

  SprintGoogleAccount? googleAccountById(String? id) {
    if (id == null) return null;
    for (final account in _googleAccounts) {
      if (account.id == id) return account;
    }
    return null;
  }

  SprintCalendarProfile? calendarProfileById(String? id) {
    if (id == null) return null;
    for (final profile in _calendarProfiles) {
      if (profile.id == id) return profile;
    }
    return null;
  }

  SprintGoogleAccount? accountForProfile(String? profileId) {
    return googleAccountById(calendarProfileById(profileId)?.accountId);
  }

  bool isProfileAuthenticated(String profileId) {
    final account = accountForProfile(profileId);
    final identity = GoogleAuthSession.instance.currentIdentity;
    if (account == null || identity == null || account.email.trim().isEmpty) {
      return false;
    }
    return identity.normalizedEmail == account.normalizedEmail;
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
    final externalEntries = externalEvents.where((event) {
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
    for (final event in externalEvents) {
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
    for (final event in externalEvents) {
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
    return _day(date);
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
      description: '',
      projectId: resolvedProjectId,
      priority: parsed.priority,
      startDate: adjustedStart,
      endDate: adjustedStart.add(Duration(days: days)),
    );
  }

  SprintTaskCreationPreview? previewTaskDetails({
    required String title,
    required String description,
    required String projectId,
    required SprintTaskPriority priority,
    required DateTime startDate,
    required DateTime endDate,
  }) {
    _taskInputError = null;
    final normalizedTitle = title.trim();
    final normalizedDescription = description.trim();
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
      description: normalizedDescription,
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
      description: preview.description,
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
    _scheduleTaskCalendarUpsert(task.id);
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
        ).conflicts,
      );
    }
    return conflicts.where((value) => !_isConflictResolved(value.id)).toList();
  }

  Future<bool> updateTask({
    required String taskId,
    required String title,
    required String description,
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
    );
    if (validation.conflicts.any(_isHardDateConflict)) return false;
    task
      ..title = normalizedTitle
      ..description = description.trim()
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
    _scheduleTaskCalendarUpsert(task.id);
    return true;
  }

  Future<bool> cancelTask(String taskId) async {
    final task = taskById(taskId);
    if (task == null) return false;
    task
      ..state = SprintTaskState.cancelled
      ..deleteAfterSync = false;
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
    _scheduleTaskCalendarDelete(task.id, deleteAfterSync: false);
    return true;
  }


  Future<bool> deleteTask(String taskId) async {
    await _calendarWriteQueue;
    final task = taskById(taskId);
    if (task == null) return false;
    if (!task.hasGoogleEvent) {
      _removeTaskLocally(task);
      notifyListeners();
      await _persistNow();
      return true;
    }
    task
      ..state = SprintTaskState.cancelled
      ..googleSyncState = SprintGoogleSyncState.pendingDelete
      ..googleSyncError = null
      ..deleteAfterSync = true;
    final block = _blockForTask(task.id);
    if (block != null) block.status = SprintScheduleBlockStatus.cancelled;
    _refreshAttention();
    notifyListeners();
    await _persistNow();
    _scheduleTaskCalendarDelete(task.id, deleteAfterSync: true);
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
    _scheduleTaskCalendarUpsert(task.id);
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
    _scheduleTaskCalendarUpsert(task.id);
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
    _scheduleTaskCalendarDelete(task.id, deleteAfterSync: false);
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
    _scheduleTaskCalendarUpsert(task.id);
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
    _scheduleTaskCalendarUpsert(task.id);
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
    _scheduleTaskCalendarUpsert(task.id);
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
    _scheduleTaskCalendarUpsert(task.id);
  }

  Future<void> syncGoogleCalendar() async {
    final profileId = _activeCalendarProfileId;
    if (profileId == null) {
      _calendarState = SprintCalendarConnectionState.notConnected;
      notifyListeners();
      return;
    }
    if (!isProfileAuthenticated(profileId)) {
      await switchActiveCalendarProfile(profileId);
      return;
    }
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
    final profileId = _activeCalendarProfileId;
    if (profileId == null || !isProfileAuthenticated(profileId)) return;
    if (_calendarState == SprintCalendarConnectionState.notConnected ||
        _calendarState ==
            SprintCalendarConnectionState.reauthenticationRequired ||
        _calendarState == SprintCalendarConnectionState.switching) {
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
    final profile = activeCalendarProfile;
    final account = activeGoogleAccount;
    if (profile == null || account == null) {
      _calendarState = SprintCalendarConnectionState.notConnected;
      _calendarError = null;
      notifyListeners();
      return;
    }
    if (!isProfileAuthenticated(profile.id)) {
      account.requiresReauthentication = true;
      _calendarState = SprintCalendarConnectionState.reauthenticationRequired;
      _calendarError = 'Google 계정 재인증이 필요합니다.';
      notifyListeners();
      await _persistNow();
      return;
    }
    final generation = ++_calendarSyncGeneration;
    final profileId = profile.id;
    final center = weekStart(anchor ?? _selectedDate);
    final rangeStart = center.subtract(const Duration(days: 28));
    final rangeEnd = center.add(const Duration(days: 42));
    _calendarState = SprintCalendarConnectionState.syncing;
    _calendarError = null;
    notifyListeners();
    try {
      final events = await _calendarService.listEvents(
        accountEmail: account.email,
        calendarId: profile.calendarId,
        timeMin: rangeStart,
        timeMax: rangeEnd.add(const Duration(days: 1)),
        maxResults: 500,
      );
      if (generation != _calendarSyncGeneration ||
          profileId != _activeCalendarProfileId) {
        return;
      }
      final mapped = _reconcileGoogleEvents(
        events,
        profile: profile,
        rangeStart: rangeStart,
        rangeEnd: rangeEnd,
      );
      if (replace) {
        _externalEvents.removeWhere(
          (event) => event.calendarProfileId == profileId,
        );
        _externalEvents.addAll(mapped);
        _calendarLoadedStart = rangeStart;
        _calendarLoadedEnd = rangeEnd;
      } else {
        _externalEvents.removeWhere((event) {
          if (event.calendarProfileId != profileId) return false;
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
      profile
        ..lastSyncedAt = DateTime.now()
        ..lastSyncError = null
        ..updatedAt = DateTime.now();
      account
        ..requiresReauthentication = false
        ..updatedAt = DateTime.now();
      _calendarState = SprintCalendarConnectionState.connected;
      _calendarError = null;
      _refreshAttention();
      notifyListeners();
      await _persistNow();
      _retryPendingTaskSyncs();
    } catch (error) {
      if (generation != _calendarSyncGeneration ||
          profileId != _activeCalendarProfileId) {
        return;
      }
      final mismatch = error is GoogleAccountMismatchException;
      account
        ..requiresReauthentication = mismatch
        ..updatedAt = DateTime.now();
      profile
        ..lastSyncError = error.toString()
        ..updatedAt = DateTime.now();
      _calendarState = mismatch
          ? SprintCalendarConnectionState.reauthenticationRequired
          : SprintCalendarConnectionState.failed;
      _calendarError = error.toString();
      notifyListeners();
      await _persistNow();
    }
  }

  Future<bool> retryTaskGoogleSync(String taskId) async {
    final task = taskById(taskId);
    if (task == null) return false;
    if (task.googleCalendarProfileId != _activeCalendarProfileId) {
      return false;
    }
    final requiresDelete =
        task.googleSyncState == SprintGoogleSyncState.pendingDelete ||
            task.deleteAfterSync ||
            task.state == SprintTaskState.cancelled ||
            _blockForTask(task.id) == null;
    if (requiresDelete) {
      task.googleSyncState = SprintGoogleSyncState.pendingDelete;
      task.googleSyncError = null;
      notifyListeners();
      await _persistNow();
      return _performTaskCalendarDelete(task.id);
    }
    task.googleSyncState = task.hasGoogleEvent
        ? SprintGoogleSyncState.pendingUpdate
        : SprintGoogleSyncState.pendingCreate;
    task.googleSyncError = null;
    notifyListeners();
    await _persistNow();
    return _performTaskCalendarUpsert(task.id);
  }

  void _scheduleTaskCalendarUpsert(String taskId) {
    final task = taskById(taskId);
    final project = projectById(task?.projectId);
    final block = _blockForTask(taskId);
    if (task == null ||
        project == null ||
        !project.calendarSyncEnabled ||
        block == null ||
        task.state == SprintTaskState.cancelled) {
      return;
    }
    task.googleCalendarProfileId ??= _activeCalendarProfileId;
    task
      ..googleSyncState = task.hasGoogleEvent
          ? SprintGoogleSyncState.pendingUpdate
          : SprintGoogleSyncState.pendingCreate
      ..googleSyncError = null
      ..deleteAfterSync = false;
    notifyListeners();
    _queuePersist();
    if (!_canRunCalendarWrites ||
        task.googleCalendarProfileId != _activeCalendarProfileId) {
      return;
    }
    _enqueueCalendarWrite(() async {
      await _performTaskCalendarUpsert(taskId);
    });
  }

  void _scheduleTaskCalendarDelete(
    String taskId, {
    required bool deleteAfterSync,
  }) {
    final task = taskById(taskId);
    if (task == null) return;
    task.googleCalendarProfileId ??= _activeCalendarProfileId;
    final couldHaveRemoteEvent = task.hasGoogleEvent ||
        task.googleSyncState != SprintGoogleSyncState.none;
    if (!couldHaveRemoteEvent) {
      if (deleteAfterSync) {
        _removeTaskLocally(task);
      } else {
        task
          ..googleSyncState = SprintGoogleSyncState.none
          ..googleSyncError = null
          ..deleteAfterSync = false;
      }
      notifyListeners();
      _queuePersist();
      return;
    }
    task
      ..googleSyncState = SprintGoogleSyncState.pendingDelete
      ..googleSyncError = null
      ..deleteAfterSync = deleteAfterSync;
    notifyListeners();
    _queuePersist();
    if (!_canRunCalendarWrites ||
        task.googleCalendarProfileId != _activeCalendarProfileId) {
      return;
    }
    _enqueueCalendarWrite(() async {
      await _performTaskCalendarDelete(taskId);
    });
  }

  bool get _canRunCalendarWrites {
    final profileId = _activeCalendarProfileId;
    return profileId != null &&
        isProfileAuthenticated(profileId) &&
        (_calendarState == SprintCalendarConnectionState.connected ||
            _calendarState == SprintCalendarConnectionState.syncing);
  }

  void _enqueueCalendarWrite(Future<void> Function() operation) {
    _calendarWriteQueue = _calendarWriteQueue.then((_) async {
      try {
        await operation();
      } catch (_) {}
    });
  }

  Future<bool> _performTaskCalendarUpsert(String taskId) async {
    final task = taskById(taskId);
    final project = projectById(task?.projectId);
    final block = _blockForTask(taskId);
    if (task == null || project == null || block == null) return false;
    if (!project.calendarSyncEnabled ||
        task.state == SprintTaskState.cancelled) {
      return false;
    }
    final profile = calendarProfileById(
      task.googleCalendarProfileId ?? _activeCalendarProfileId,
    );
    final account = accountForProfile(profile?.id);
    if (profile == null || account == null) return false;
    task.googleCalendarProfileId ??= profile.id;
    if (!_canRunCalendarWrites || profile.id != _activeCalendarProfileId) {
      return false;
    }
    final creatingRemoteEvent = !task.hasGoogleEvent;
    final result = await _calendarSyncCoordinator.upsertTask(
      task: task,
      block: block,
      project: project,
      profile: profile,
      account: account,
    );
    final current = taskById(taskId);
    if (current == null) return result.success;
    if (result.success) {
      final deletionPending =
          current.googleSyncState == SprintGoogleSyncState.pendingDelete ||
              current.deleteAfterSync ||
              current.state == SprintTaskState.cancelled ||
              _blockForTask(current.id) == null;
      current
        ..googleEventId = result.eventId
        ..googleCalendarId = result.calendarId ?? profile.calendarId
        ..googleCalendarProfileId =
            result.calendarProfileId ?? profile.id
        ..googleSyncState = deletionPending
            ? SprintGoogleSyncState.pendingDelete
            : SprintGoogleSyncState.synced
        ..googleSyncError = null;
      if (!deletionPending) current.deleteAfterSync = false;
    } else {
      if (!creatingRemoteEvent) {
        current
          ..googleEventId = result.eventId ?? current.googleEventId
          ..googleCalendarId = result.calendarId ?? current.googleCalendarId
          ..googleCalendarProfileId =
              result.calendarProfileId ?? current.googleCalendarProfileId;
      }
      current
        ..googleSyncState = SprintGoogleSyncState.failed
        ..googleSyncError = result.error;
    }
    notifyListeners();
    await _persistNow();
    return result.success;
  }

  Future<bool> _performTaskCalendarDelete(String taskId) async {
    final task = taskById(taskId);
    if (task == null) return false;
    final profile = calendarProfileById(
      task.googleCalendarProfileId ?? _activeCalendarProfileId,
    );
    final account = accountForProfile(profile?.id);
    if (profile == null || account == null) return false;
    if (profile.id != _activeCalendarProfileId ||
        (!_canRunCalendarWrites && task.hasGoogleEvent)) {
      return false;
    }
    final result = await _calendarSyncCoordinator.deleteTaskEvent(
      task: task,
      profile: profile,
      account: account,
    );
    final current = taskById(taskId);
    if (current == null) return result.success;
    if (!result.success) {
      current
        ..googleSyncState = SprintGoogleSyncState.failed
        ..googleSyncError = result.error;
      notifyListeners();
      await _persistNow();
      return false;
    }
    final removeAfterSync = current.deleteAfterSync;
    current
      ..googleEventId = null
      ..googleCalendarId = null
      ..googleCalendarProfileId = null
      ..googleSyncState = SprintGoogleSyncState.none
      ..googleSyncError = null
      ..deleteAfterSync = false;
    if (removeAfterSync) {
      _removeTaskLocally(current);
    }
    notifyListeners();
    await _persistNow();
    return true;
  }

  void _retryPendingTaskSyncs() {
    if (!_canRunCalendarWrites) return;
    final profileId = _activeCalendarProfileId;
    if (profileId == null) return;
    var localStateChanged = false;
    for (final task in List<SprintTask>.from(_tasks)) {
      if (!task.hasPendingGoogleSync) continue;
      final requiresDelete =
          task.googleSyncState == SprintGoogleSyncState.pendingDelete ||
              task.deleteAfterSync ||
              task.state == SprintTaskState.cancelled ||
              _blockForTask(task.id) == null;
      if (task.googleCalendarProfileId == null && !task.hasGoogleEvent) {
        if (requiresDelete) {
          if (task.deleteAfterSync) {
            _removeTaskLocally(task);
            localStateChanged = true;
          } else {
            task
              ..googleSyncState = SprintGoogleSyncState.none
              ..googleSyncError = null;
            localStateChanged = true;
          }
          continue;
        }
        task.googleCalendarProfileId = profileId;
      }
      if (task.googleCalendarProfileId != profileId) continue;
      if (requiresDelete) {
        _scheduleTaskCalendarDelete(
          task.id,
          deleteAfterSync: task.deleteAfterSync,
        );
      } else {
        _scheduleTaskCalendarUpsert(task.id);
      }
    }
    if (localStateChanged) {
      notifyListeners();
      _queuePersist();
    }
  }

  List<SprintExternalEvent> _reconcileGoogleEvents(
    List<gcal.Event> events, {
    required SprintCalendarProfile profile,
    required DateTime rangeStart,
    required DateTime rangeEnd,
  }) {
    final external = <SprintExternalEvent>[];
    final remoteManagedIds = <String>{};
    for (final event in events) {
      final mapped = _mapGoogleEvent(event, profile.id);
      if (mapped == null) continue;
      final linkedTaskId = mapped.linkedTaskId;
      final task = taskById(linkedTaskId);
      if (mapped.managedBySprint && task != null) {
        remoteManagedIds.add(mapped.googleEventId);
        final taskProfileId = task.googleCalendarProfileId;
        if (taskProfileId == null || taskProfileId == profile.id) {
          task
            ..googleEventId = mapped.googleEventId
            ..googleCalendarId = profile.calendarId
            ..googleCalendarProfileId = profile.id;
          if (task.googleSyncState == SprintGoogleSyncState.none ||
              task.googleSyncState == SprintGoogleSyncState.synced) {
            task
              ..googleSyncState = SprintGoogleSyncState.synced
              ..googleSyncError = null
              ..deleteAfterSync = false;
          } else if (task.googleSyncState ==
              SprintGoogleSyncState.pendingCreate) {
            task.googleSyncState = SprintGoogleSyncState.pendingUpdate;
          }
        }
        continue;
      }
      external.add(mapped);
    }
    for (final task in _tasks) {
      if (task.googleCalendarProfileId != profile.id ||
          !task.hasGoogleEvent ||
          task.googleSyncState == SprintGoogleSyncState.pendingDelete) {
        continue;
      }
      final block = _blockForTask(task.id);
      if (block == null) continue;
      final blockStart = _day(block.start);
      final blockEnd = _inclusiveEnd(block.end);
      final inLoadedRange = !blockEnd.isBefore(rangeStart) &&
          !blockStart.isAfter(rangeEnd);
      if (!inLoadedRange || remoteManagedIds.contains(task.googleEventId)) {
        continue;
      }
      task
        ..googleEventId = null
        ..googleCalendarId = null
        ..googleSyncState = SprintGoogleSyncState.pendingCreate
        ..googleSyncError = null;
    }
    return external;
  }

  void _removeTaskLocally(SprintTask task) {
    _blocks.removeWhere((block) => block.taskId == task.id);
    _attentionItems.removeWhere((item) => item.taskId == task.id);
    _tasks.remove(task);
    _recordActivity(
      type: SprintActivityEventType.taskDeleted,
      projectId: task.projectId,
      taskId: task.id,
    );
    _refreshAttention();
  }

  Future<void> disconnectGoogleCalendar() async {
    if (_accountOperationInProgress) return;
    final account = activeGoogleAccount;
    _calendarRangeDebounce?.cancel();
    _calendarSyncGeneration += 1;
    _calendarLoadedStart = null;
    _calendarLoadedEnd = null;
    _calendarService.resetAuthenticatedClient();
    if (account != null) {
      account
        ..requiresReauthentication = true
        ..updatedAt = DateTime.now();
    }
    await GoogleAuthSession.instance.signOut();
    _calendarState = activeCalendarProfile == null
        ? SprintCalendarConnectionState.notConnected
        : SprintCalendarConnectionState.reauthenticationRequired;
    _calendarError = null;
    notifyListeners();
    await _persistNow();
  }

  String projectName(String? projectId) {
    return projectById(projectId)?.name ?? '프로젝트 없음';
  }

  void _ensureProjectColors() {
    final used = <String>{};
    var overflowIndex = 0;
    for (final project in _projects.where((value) => value.isActive)) {
      final current = project.googleColorId;
      if (googleEventColorIds.contains(current) && !used.contains(current)) {
        used.add(current);
        project.calendarSyncEnabled = true;
        continue;
      }
      final available = googleEventColorIds
          .where((colorId) => !used.contains(colorId))
          .toList(growable: false);
      if (available.isNotEmpty) {
        project
          ..googleColorId = available.first
          ..calendarSyncEnabled = true;
        used.add(available.first);
      } else {
        project
          ..googleColorId =
              googleEventColorIds[overflowIndex % googleEventColorIds.length]
          ..calendarSyncEnabled = false;
        overflowIndex += 1;
      }
    }
    var inactiveIndex = 0;
    for (final project in _projects.where((value) => !value.isActive)) {
      if (googleEventColorIds.contains(project.googleColorId)) continue;
      project.googleColorId =
          googleEventColorIds[inactiveIndex % googleEventColorIds.length];
      inactiveIndex += 1;
    }
  }

  void _normalizeGoogleSyncState() {
    for (final task in _tasks) {
      if (task.hasGoogleEvent &&
          task.googleSyncState == SprintGoogleSyncState.none) {
        task.googleSyncState = SprintGoogleSyncState.synced;
      }
      if (!task.hasGoogleEvent &&
          task.googleSyncState == SprintGoogleSyncState.synced) {
        task.googleSyncState = SprintGoogleSyncState.none;
      }
      if (task.googleCalendarId?.trim().isEmpty == true) {
        task.googleCalendarId = null;
      }
      if (task.googleEventId?.trim().isEmpty == true) {
        task.googleEventId = null;
      }
      if (task.googleCalendarProfileId?.trim().isEmpty == true) {
        task.googleCalendarProfileId = null;
      }
      if ((task.hasGoogleEvent || task.hasPendingGoogleSync) &&
          task.googleCalendarProfileId == null) {
        task.googleCalendarProfileId = _activeCalendarProfileId;
      }
    }
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
  }) {
    final validation = _schedulingEngine.validatePlacement(
      start: _day(startDate),
      end: _exclusiveEnd(_day(endDate)),
      ignoringBlockId: blockId,
      projectId: projectId,
      taskId: taskId,
      notBefore: projectScheduleLowerBound(projectId),
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
    return conflict.type == SprintConflictType.invalidDateRange;
  }

  String _dateConflictMessage(List<SprintScheduleConflict> conflicts) {
    if (conflicts.any((value) => value.type == SprintConflictType.invalidDateRange)) {
      return '종료일은 시작일보다 빠를 수 없습니다.';
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

  SprintExternalEvent? _mapGoogleEvent(
    gcal.Event event,
    String calendarProfileId,
  ) {
    if (event.status == 'cancelled') return null;
    final start = event.start?.dateTime?.toLocal() ?? event.start?.date;
    if (start == null) return null;
    final allDay = event.start?.date != null;
    final end = event.end?.dateTime?.toLocal() ??
        event.end?.date ??
        start.add(allDay ? const Duration(days: 1) : const Duration(minutes: 30));
    final title = event.summary?.trim();
    final privateProperties = event.extendedProperties?.private;
    final managedBySprint =
        privateProperties?['source'] == 'parkinworkin_sprint';
    final googleEventId =
        event.id?.trim().isNotEmpty == true
            ? event.id!.trim()
            : 'google-${start.microsecondsSinceEpoch}';
    return SprintExternalEvent(
      id: '$calendarProfileId:$googleEventId',
      googleEventId: googleEventId,
      calendarProfileId: calendarProfileId,
      title: title == null || title.isEmpty ? '제목 없는 외부 일정' : title,
      start: start,
      end: end,
      allDay: allDay,
      blocksTime: event.transparency != 'transparent',
      sourceUrl: event.htmlLink,
      colorId: event.colorId,
      managedBySprint: managedBySprint,
      linkedTaskId: privateProperties?['sprintTaskId'],
      linkedProjectId: privateProperties?['sprintProjectId'],
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
        googleAccounts: List<SprintGoogleAccount>.from(_googleAccounts),
        calendarProfiles:
            List<SprintCalendarProfile>.from(_calendarProfiles),
        activeCalendarProfileId: _activeCalendarProfileId,
        workspaceScope: _workspaceScope,
        selectedDate: _selectedDate,
        lastObservedToday: _lastObservedToday,
        weekMode: _weekMode,
        googleCalendarId: googleCalendarId,
        googleCalendarIdLocked: googleCalendarIdLocked,
        legacyCalendarConfigured: activeCalendarProfile != null,
      ),
    );
  }

  void _queuePersist() {
    _writeQueue = _writeQueue.then((_) => _persistNow());
  }

  @override
  void dispose() {
    _calendarRangeDebounce?.cancel();
    _identitySubscription?.cancel();
    _identitySubscription = null;
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
