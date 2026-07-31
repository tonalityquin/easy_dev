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
  static const Duration _calendarFullVerificationInterval = Duration(days: 7);

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
  final List<SprintCalendarSyncReport> _lastCalendarSyncReports =
      <SprintCalendarSyncReport>[];

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
  String? _defaultCalendarProfileId;
  DateTime _lastObservedToday = _day(DateTime.now());
  final Map<String, DateTime> _calendarLoadedStartByProfile =
      <String, DateTime>{};
  final Map<String, DateTime> _calendarLoadedEndByProfile =
      <String, DateTime>{};
  Timer? _calendarRangeDebounce;
  final Map<String, SprintCalendarConnectionState> _calendarStatesByProfile =
      <String, SprintCalendarConnectionState>{};
  final Map<String, String?> _calendarErrorsByProfile = <String, String?>{};
  final Map<String, int> _calendarSyncGenerationByProfile = <String, int>{};
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
    final visibleIds = visibleCalendarProfileIds;
    if (visibleIds.isEmpty) return const <SprintExternalEvent>[];
    return List<SprintExternalEvent>.unmodifiable(
      _externalEvents.where(
        (event) => visibleIds.contains(event.calendarProfileId),
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
  SprintCalendarConnectionState calendarStateForProfile(String profileId) {
    return _calendarStatesByProfile[profileId] ??
        _initialCalendarStateForProfile(calendarProfileById(profileId));
  }
  String? calendarErrorForProfile(String profileId) {
    return _calendarErrorsByProfile[profileId] ??
        calendarProfileById(profileId)?.lastSyncError;
  }
  String? get taskInputError => _taskInputError;
  String? get projectInputError => _projectInputError;
  bool get initialized => _initialized;
  bool get initializing => _initializing;
  bool get accountSaving => _accountOperationInProgress;
  bool get accountBusy => _accountOperationInProgress;
  List<SprintGoogleAccount> get googleAccounts =>
      List<SprintGoogleAccount>.unmodifiable(_googleAccounts);
  List<SprintCalendarProfile> _activeCalendarSlots() {
    final enabled = _calendarProfiles.where((profile) => profile.enabled).toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    SprintCalendarProfile? personal;
    SprintCalendarProfile? company;
    for (final profile in enabled) {
      if (profile.googlePrimary) {
        personal ??= profile;
      } else {
        company ??= profile;
      }
    }
    return <SprintCalendarProfile>[
      if (personal != null) personal,
      if (company != null) company,
    ];
  }

  List<SprintCalendarProfile> get calendarProfiles =>
      List<SprintCalendarProfile>.unmodifiable(_activeCalendarSlots());
  List<SprintCalendarSyncReport> get lastCalendarSyncReports =>
      List<SprintCalendarSyncReport>.unmodifiable(_lastCalendarSyncReports);
  Duration get calendarFullVerificationInterval =>
      _calendarFullVerificationInterval;

  bool isPeriodicFullVerificationDue(SprintCalendarProfile profile) {
    return _periodicFullVerificationDue(profile, DateTime.now());
  }

  DateTime? nextFullVerificationAt(SprintCalendarProfile profile) {
    final last = profile.lastFullSyncAt;
    if (last == null) return null;
    return last.add(_calendarFullVerificationInterval);
  }
  SprintCalendarProfile? get personalCalendarProfile {
    for (final profile in _activeCalendarSlots()) {
      if (profile.googlePrimary) return profile;
    }
    return null;
  }
  SprintCalendarProfile? get companyCalendarProfile {
    for (final profile in _activeCalendarSlots()) {
      if (!profile.googlePrimary) return profile;
    }
    return null;
  }
  bool get hasCompanyCalendarProfile => companyCalendarProfile != null;
  List<SprintCalendarProfile> get editableCalendarProfiles =>
      List<SprintCalendarProfile>.unmodifiable(
        _activeCalendarSlots().where((profile) => profile.canEditEvents),
      );
  bool get hasEditableCalendarProfile => editableCalendarProfiles.isNotEmpty;
  Set<String> get visibleCalendarProfileIds =>
      _activeCalendarSlots().map((profile) => profile.id).toSet();
  String? get defaultCalendarProfileId => _defaultCalendarProfileId;
  SprintCalendarProfile? get defaultCalendarProfile {
    final slots = _activeCalendarSlots();
    final profile = calendarProfileById(_defaultCalendarProfileId);
    if (profile?.enabled == true &&
        slots.any((candidate) => candidate.id == profile!.id)) {
      return profile;
    }
    return personalCalendarProfile ?? companyCalendarProfile;
  }
  SprintGoogleAccount? get defaultGoogleAccount =>
      googleAccountById(defaultCalendarProfile?.accountId);
  String get googleCalendarId => defaultCalendarProfile?.calendarId ?? 'primary';
  bool get googleCalendarIdLocked => defaultCalendarProfile?.locked ?? false;
  String get defaultCalendarLabel =>
      defaultCalendarProfile?.label.trim().isNotEmpty == true
          ? defaultCalendarProfile!.label.trim()
          : 'Google 캘린더';
  String get defaultGoogleEmail => defaultGoogleAccount?.email.trim() ?? '';
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
        role: SprintCalendarProfileRole.primary,
        locked: snapshot.googleCalendarIdLocked,
        sortOrder: 0,
        createdAt: now,
        updatedAt: now,
      );
      _googleAccounts.add(account);
      _calendarProfiles.add(profile);
      _defaultCalendarProfileId = profile.id;
    }
    final restoredActive = calendarProfileById(_defaultCalendarProfileId);
    if (restoredActive == null || !restoredActive.enabled) {
      final enabledProfiles = _calendarProfiles.where(
        (profile) => profile.enabled,
      );
      _defaultCalendarProfileId =
          enabledProfiles.isEmpty ? null : enabledProfiles.first.id;
    }
    _applyDefaultCalendarProfileRole();
    final defaultProfile = defaultCalendarProfile;
    if (defaultProfile == null) return;
    for (final task in _tasks) {
      if (task.googleCalendarProfileId?.trim().isNotEmpty == true) continue;
      if (task.hasGoogleEvent ||
          task.googleCalendarId?.trim().isNotEmpty == true) {
        task.googleCalendarProfileId = defaultProfile.id;
      }
    }
    for (var index = 0; index < _externalEvents.length; index += 1) {
      final event = _externalEvents[index];
      if (event.calendarProfileId.trim().isNotEmpty) continue;
      _externalEvents[index] = SprintExternalEvent(
        id: '${defaultProfile.id}:${event.googleEventId}',
        googleEventId: event.googleEventId,
        calendarProfileId: defaultProfile.id,
        title: event.title,
        description: event.description,
        start: event.start,
        end: event.end,
        allDay: event.allDay,
        blocksTime: event.blocksTime,
        sourceUrl: event.sourceUrl,
        colorId: event.colorId,
        etag: event.etag,
        remoteUpdatedAt: event.remoteUpdatedAt,
        managedBySprint: event.managedBySprint,
        linkedTaskId: event.linkedTaskId,
        linkedProjectId: event.linkedProjectId,
      );
    }
  }

  void _handleIdentityChange(GoogleAuthIdentity? identity) {
    if (_accountOperationInProgress) return;
    if (identity != null) {
      for (final account in _googleAccounts) {
        if (account.normalizedEmail == identity.normalizedEmail) {
          account
            ..googleUserId = identity.id
            ..email = identity.email.trim()
            ..displayName = identity.displayName.trim()
            ..requiresReauthentication = false
            ..updatedAt = DateTime.now();
        }
      }
    }
    for (final account in _googleAccounts) {
      final authenticated = GoogleAuthSession.instance.hasCachedClientFor(
        account.email,
      );
      account.requiresReauthentication = !authenticated;
    }
    _recomputeCalendarState();
    notifyListeners();
    _queuePersist();
  }

  void _protectActiveProfileAfterAuthenticationChange() {
    final profile = defaultCalendarProfile;
    final account = defaultGoogleAccount;
    if (profile == null || account == null || isProfileAuthenticated(profile.id)) {
      return;
    }
    account
      ..requiresReauthentication = true
      ..updatedAt = DateTime.now();
    _calendarStatesByProfile[profile.id] =
        SprintCalendarConnectionState.reauthenticationRequired;
    _calendarErrorsByProfile[profile.id] = null;
    _recomputeCalendarState();
  }

  SprintCalendarConnectionState _initialCalendarState() {
    if (_activeCalendarSlots().isEmpty) {
      return SprintCalendarConnectionState.notConnected;
    }
    for (final profile in _activeCalendarSlots()) {
      _calendarStatesByProfile.putIfAbsent(
        profile.id,
        () => _initialCalendarStateForProfile(profile),
      );
    }
    _recomputeCalendarState();
    return _calendarState;
  }

  SprintCalendarConnectionState _initialCalendarStateForProfile(
    SprintCalendarProfile? profile,
  ) {
    if (profile == null || !profile.enabled) {
      return SprintCalendarConnectionState.notConnected;
    }
    final account = accountForProfile(profile.id);
    if (account == null || account.email.trim().isEmpty) {
      if (account != null) account.requiresReauthentication = true;
      return SprintCalendarConnectionState.reauthenticationRequired;
    }
    final authenticated = GoogleAuthSession.instance.hasCachedClientFor(
          account.email,
        ) ||
        GoogleAuthSession.instance.currentIdentity?.normalizedEmail ==
            account.normalizedEmail;
    account.requiresReauthentication = !authenticated;
    return authenticated
        ? SprintCalendarConnectionState.cached
        : SprintCalendarConnectionState.reauthenticationRequired;
  }

  void _recomputeCalendarState() {
    final enabled = _activeCalendarSlots();
    if (enabled.isEmpty) {
      _calendarState = SprintCalendarConnectionState.notConnected;
      _calendarError = null;
      return;
    }
    final states = enabled
        .map((profile) => _calendarStatesByProfile[profile.id] ??
            _initialCalendarStateForProfile(profile))
        .toList(growable: false);
    if (states.any((state) => state == SprintCalendarConnectionState.syncing)) {
      _calendarState = SprintCalendarConnectionState.syncing;
    } else if (states.any((state) => state == SprintCalendarConnectionState.switching)) {
      _calendarState = SprintCalendarConnectionState.switching;
    } else if (states.any((state) => state == SprintCalendarConnectionState.failed)) {
      _calendarState = SprintCalendarConnectionState.failed;
    } else if (states.any((state) =>
        state == SprintCalendarConnectionState.reauthenticationRequired)) {
      _calendarState = SprintCalendarConnectionState.reauthenticationRequired;
    } else if (states.every((state) =>
        state == SprintCalendarConnectionState.connected)) {
      _calendarState = SprintCalendarConnectionState.connected;
    } else {
      _calendarState = SprintCalendarConnectionState.cached;
    }
    _calendarError = null;
    for (final profile in enabled) {
      final error = _calendarErrorsByProfile[profile.id];
      if (error?.trim().isNotEmpty == true) {
        _calendarError = error;
        break;
      }
    }
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
      _defaultCalendarProfileId = snapshot.defaultCalendarProfileId;
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
      final currentIdentity = GoogleAuthSession.instance.currentIdentity;
      if (currentIdentity != null) {
        unawaited(_bootstrapGoogleCalendarSlots(currentIdentity));
      } else if (_calendarState == SprintCalendarConnectionState.cached) {
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
      _scheduleTaskCalendarDelete(taskId, deleteAfterSync: true);
    }
    return true;
  }

  Future<GoogleAuthIdentity> _authenticateActiveGoogleAccount() async {
    final current = GoogleAuthSession.instance.currentIdentity;
    return GoogleAuthSession.instance.authenticateAccount(
      expectedEmail: current?.email,
      bridgeFirebase: false,
    );
  }

  SprintGoogleAccount _upsertGoogleAccountForIdentity(
    GoogleAuthIdentity identity,
  ) {
    SprintGoogleAccount? account;
    for (final candidate in _googleAccounts) {
      final sameGoogleUser = candidate.googleUserId?.trim().isNotEmpty == true &&
          candidate.googleUserId == identity.id;
      if (sameGoogleUser || candidate.normalizedEmail == identity.normalizedEmail) {
        account = candidate;
        break;
      }
    }
    final now = DateTime.now();
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
    return account;
  }

  Future<void> _reconcileGoogleCalendarSlots({
    required GoogleAuthIdentity identity,
    required List<GoogleCalendarAccessEntry> calendars,
  }) async {
    GoogleCalendarAccessEntry? primaryEntry;
    for (final entry in calendars) {
      if (entry.primary) {
        primaryEntry = entry;
        break;
      }
    }
    if (primaryEntry == null) {
      throw StateError('google_primary_calendar_not_found');
    }
    final account = _upsertGoogleAccountForIdentity(identity);
    final now = DateTime.now();
    final primaryId = primaryEntry.id.trim().toLowerCase();
    SprintCalendarProfile? personal;
    for (final candidate in _calendarProfiles) {
      if (candidate.accountId != account.id) continue;
      final calendarId = candidate.calendarId.trim().toLowerCase();
      if (candidate.googlePrimary ||
          calendarId == primaryId ||
          calendarId == 'primary') {
        personal = candidate;
        break;
      }
    }
    if (personal == null) {
      personal = SprintCalendarProfile(
        id: _newId('calendar-profile'),
        accountId: account.id,
        calendarId: primaryEntry.id,
        label: primaryEntry.displayName,
        role: _defaultCalendarProfileId == null
            ? SprintCalendarProfileRole.primary
            : SprintCalendarProfileRole.secondary,
        accessRole: primaryEntry.accessRole,
        googlePrimary: true,
        locked: true,
        sortOrder: 0,
        createdAt: now,
        updatedAt: now,
      );
      _calendarProfiles.add(personal);
    } else {
      final calendarChanged =
          personal.calendarId.trim().toLowerCase() != primaryId;
      if (calendarChanged) _clearProfileSyncToken(personal);
      personal
        ..calendarId = primaryEntry.id
        ..label = primaryEntry.displayName
        ..accessRole = primaryEntry.accessRole
        ..googlePrimary = true
        ..locked = true
        ..enabled = true
        ..sortOrder = 0
        ..lastSyncError = null
        ..updatedAt = now;
    }

    final companyCandidates = <SprintCalendarProfile>[];
    final disabledIds = <String>{};
    for (final candidate in _calendarProfiles) {
      if (candidate.id == personal.id) continue;
      if (candidate.googlePrimary) {
        candidate.googlePrimary = false;
      }
      final sameAccount = candidate.accountId == account.id;
      final sameCalendar = candidate.calendarId.trim().toLowerCase() == primaryId ||
          candidate.calendarId.trim().toLowerCase() == 'primary';
      if (!sameAccount || sameCalendar) {
        if (candidate.enabled) disabledIds.add(candidate.id);
        candidate
          ..enabled = false
          ..updatedAt = now;
        continue;
      }
      if (candidate.enabled) companyCandidates.add(candidate);
    }
    companyCandidates.sort((a, b) {
      if (a.id == _defaultCalendarProfileId) return -1;
      if (b.id == _defaultCalendarProfileId) return 1;
      return a.sortOrder.compareTo(b.sortOrder);
    });
    SprintCalendarProfile? company;
    if (companyCandidates.isNotEmpty) {
      company = companyCandidates.first;
      company
        ..googlePrimary = false
        ..sortOrder = 1
        ..updatedAt = now;
      for (final extra in companyCandidates.skip(1)) {
        disabledIds.add(extra.id);
        extra
          ..enabled = false
          ..updatedAt = now;
      }
    }
    if (disabledIds.isNotEmpty) {
      _externalEvents.removeWhere(
        (event) => disabledIds.contains(event.calendarProfileId),
      );
      for (final id in disabledIds) {
        _calendarLoadedStartByProfile.remove(id);
        _calendarLoadedEndByProfile.remove(id);
        _calendarStatesByProfile.remove(id);
        _calendarErrorsByProfile.remove(id);
        _calendarSyncGenerationByProfile.remove(id);
      }
    }
    final activeIds = <String>{personal.id, if (company != null) company.id};
    if (_defaultCalendarProfileId == null ||
        !activeIds.contains(_defaultCalendarProfileId)) {
      _defaultCalendarProfileId = personal.id;
    }
    _applyDefaultCalendarProfileRole(updateTimestamps: true);
    _calendarStatesByProfile.putIfAbsent(
      personal.id,
      () => _initialCalendarStateForProfile(personal),
    );
    if (company != null) {
      _calendarStatesByProfile.putIfAbsent(
        company.id,
        () => _initialCalendarStateForProfile(company),
      );
    }
    _recomputeCalendarState();
    await _persistNow();
    debugPrint(
      '[SPRINT-CALENDAR][SLOTS] account=${identity.email} '
      'personal=${personal.calendarId} company=${company?.calendarId ?? '-'} '
      'active=${activeIds.length} disabled=${disabledIds.length}',
    );
  }

  Future<void> _bootstrapGoogleCalendarSlots(
    GoogleAuthIdentity identity,
  ) async {
    if (_accountOperationInProgress) return;
    _accountOperationInProgress = true;
    notifyListeners();
    try {
      final calendars = await _calendarService.listAccessibleCalendars(
        accountEmail: identity.email,
      );
      await _reconcileGoogleCalendarSlots(
        identity: identity,
        calendars: calendars,
      );
      ensureCalendarRangeFor(_selectedDate, immediate: true);
    } catch (error, stackTrace) {
      debugPrint(
        '[SPRINT-CALENDAR][SLOTS][BOOTSTRAP][ERROR] $error\n$stackTrace',
      );
      if (_calendarState == SprintCalendarConnectionState.cached) {
        ensureCalendarRangeFor(_selectedDate, immediate: true);
      }
    } finally {
      _accountOperationInProgress = false;
      notifyListeners();
    }
  }

  Future<List<GoogleCalendarAccessEntry>> discoverAccessibleGoogleCalendars()
      async {
    if (_accountOperationInProgress) {
      throw StateError('account_operation_in_progress');
    }
    _accountOperationInProgress = true;
    notifyListeners();
    try {
      final identity = await _authenticateActiveGoogleAccount();
      final calendars = await _calendarService.listAccessibleCalendars(
        accountEmail: identity.email,
      );
      await _reconcileGoogleCalendarSlots(
        identity: identity,
        calendars: calendars,
      );
      final companyCalendars = calendars
          .where((value) => !value.primary)
          .toList(growable: false);
      debugPrint(
        '[SPRINT-CALENDAR][DISCOVERY] account=${identity.email} '
        'count=${calendars.length} companyCandidates=${companyCalendars.length} '
        'editable=${companyCalendars.where((value) => value.canEditEvents).length} '
        'owners=${companyCalendars.where((value) => value.canManageSharing).length}',
      );
      return companyCalendars;
    } catch (error, stackTrace) {
      debugPrint(
        '[SPRINT-CALENDAR][DISCOVERY][ERROR] $error\n$stackTrace',
      );
      rethrow;
    } finally {
      _accountOperationInProgress = false;
      notifyListeners();
    }
  }

  Future<SprintCalendarProfile> addGoogleCalendarProfile({
    required String label,
    required String calendarId,
    required bool locked,
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
    _invalidateAllCalendarProfileSyncs();
    notifyListeners();
    try {
      await _writeQueue;
      await _calendarWriteQueue;
      final identity = await _authenticateActiveGoogleAccount();
      final account = _upsertGoogleAccountForIdentity(identity);
      final now = DateTime.now();
      final personal = personalCalendarProfile;
      if (personal != null &&
          (personal.calendarId.trim().toLowerCase() ==
                  normalizedCalendarId.toLowerCase() ||
              normalizedCalendarId.toLowerCase() == 'primary')) {
        throw StateError('calendar_profile_duplicate');
      }
      final existingCompany = companyCalendarProfile;
      if (existingCompany != null &&
          existingCompany.calendarId.trim().toLowerCase() !=
              normalizedCalendarId.toLowerCase()) {
        throw StateError('company_calendar_slot_occupied');
      }
      SprintCalendarProfile? profile;
      for (final candidate in _calendarProfiles) {
        if (candidate.accountId == account.id &&
            candidate.calendarId.toLowerCase() ==
                normalizedCalendarId.toLowerCase()) {
          profile = candidate;
          break;
        }
      }
      final duplicateAcrossAccounts = normalizedCalendarId.toLowerCase() !=
              'primary' &&
          _calendarProfiles.any(
            (candidate) =>
                candidate.enabled &&
                candidate.accountId != account.id &&
                candidate.calendarId.toLowerCase() ==
                    normalizedCalendarId.toLowerCase(),
          );
      if (duplicateAcrossAccounts) {
        throw StateError('calendar_profile_duplicate');
      }
      await _calendarService.verifyCalendarAccess(
        accountEmail: identity.email,
        calendarId: normalizedCalendarId,
      );
      final accessRole = await _calendarService.verifyCalendarWriteAccess(
        accountEmail: identity.email,
        calendarId: normalizedCalendarId,
      );
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
          role: makeActive || _defaultCalendarProfileId == null
              ? SprintCalendarProfileRole.primary
              : SprintCalendarProfileRole.secondary,
          accessRole: accessRole,
          googlePrimary: false,
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
          ..accessRole = accessRole
          ..googlePrimary = false
          ..lastSyncError = null
          ..updatedAt = now;
      }
      _calendarStatesByProfile[profile.id] =
          SprintCalendarConnectionState.cached;
      _calendarErrorsByProfile[profile.id] = null;
      if (makeActive || _defaultCalendarProfileId == null) {
        _activateProfileLocally(profile.id);
      }
      await _persistNow();
      await _syncCalendarProfileInternal(
        profile: profile,
        anchor: _selectedDate,
        replace: true,
      );
      return profile;
    } catch (error) {
      _protectActiveProfileAfterAuthenticationChange();
      _recomputeCalendarState();
      await _persistNow();
      rethrow;
    } finally {
      _accountOperationInProgress = false;
      notifyListeners();
    }
  }

  Future<GoogleAuthIdentity> authenticateCalendarProfile(
    String profileId,
  ) async {
    final profile = calendarProfileById(profileId);
    final account = accountForProfile(profileId);
    if (profile == null || account == null || !profile.enabled) {
      throw StateError('calendar_profile_not_found');
    }
    if (account.normalizedEmail.isEmpty) {
      throw StateError('calendar_profile_account_missing');
    }
    if (_accountOperationInProgress) {
      throw StateError('account_operation_in_progress');
    }
    _accountOperationInProgress = true;
    _calendarStatesByProfile[profileId] =
        SprintCalendarConnectionState.switching;
    _calendarErrorsByProfile[profileId] = null;
    _recomputeCalendarState();
    notifyListeners();
    try {
      final identity = await _authenticateActiveGoogleAccount();
      if (identity.normalizedEmail != account.normalizedEmail) {
        throw StateError('calendar_profile_account_mismatch');
      }
      await _calendarService.verifyCalendarAccess(
        accountEmail: identity.email,
        calendarId: profile.calendarId,
      );
      final accessRole = await _calendarService.verifyCalendarWriteAccess(
        accountEmail: identity.email,
        calendarId: profile.calendarId,
      );
      final now = DateTime.now();
      account
        ..googleUserId = identity.id
        ..email = identity.email.trim()
        ..displayName = identity.displayName.trim()
        ..requiresReauthentication = false
        ..updatedAt = now;
      profile
        ..accessRole = accessRole
        ..lastSyncError = null
        ..updatedAt = now;
      _calendarStatesByProfile[profileId] =
          SprintCalendarConnectionState.cached;
      _calendarErrorsByProfile[profileId] = null;
      _recomputeCalendarState();
      await _persistNow();
      return identity;
    } catch (error) {
      account
        ..requiresReauthentication = true
        ..updatedAt = DateTime.now();
      profile
        ..lastSyncError = error.toString()
        ..updatedAt = DateTime.now();
      _calendarStatesByProfile[profileId] =
          SprintCalendarConnectionState.reauthenticationRequired;
      _calendarErrorsByProfile[profileId] = error.toString();
      _recomputeCalendarState();
      await _persistNow();
      rethrow;
    } finally {
      _accountOperationInProgress = false;
      notifyListeners();
    }
  }

  Future<void> setDefaultCalendarProfile(String profileId) async {
    final profile = calendarProfileById(profileId);
    if (profile == null || !profile.enabled) {
      throw StateError('calendar_profile_not_found');
    }
    _activateProfileLocally(profileId);
    notifyListeners();
    await _persistNow();
  }

  Future<void> switchDefaultCalendarProfile(String profileId) async {
    final profile = calendarProfileById(profileId);
    if (profile == null || !profile.enabled) {
      throw StateError('calendar_profile_not_found');
    }
    if (!isProfileAuthenticated(profileId)) {
      await authenticateCalendarProfile(profileId);
    }
    await setDefaultCalendarProfile(profileId);
    await _syncCalendarProfileInternal(
      profile: profile,
      anchor: _selectedDate,
      replace: true,
    );
  }

  Future<void> reconnectDefaultCalendarProfile() async {
    final profileId = _defaultCalendarProfileId;
    if (profileId == null) throw StateError('calendar_profile_not_found');
    await authenticateCalendarProfile(profileId);
    final profile = calendarProfileById(profileId);
    if (profile != null) {
      await _syncCalendarProfileInternal(
        profile: profile,
        anchor: _selectedDate,
        replace: true,
      );
    }
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
    if (profile.googlePrimary) {
      throw StateError('personal_calendar_slot_fixed');
    }
    var detachedTaskCount = 0;
    for (final task in _tasks) {
      if (task.googleCalendarProfileId != profile.id) continue;
      task
        ..googleEventId = null
        ..googleCalendarId = null
        ..googleCalendarProfileId = profile.id
        ..googleSyncState = SprintGoogleSyncState.none
        ..googleSyncError = null
        ..deleteAfterSync = false;
      detachedTaskCount += 1;
    }
    _calendarProfiles.remove(profile);
    _externalEvents.removeWhere(
      (event) => event.calendarProfileId == profile.id,
    );
    _calendarLoadedStartByProfile.remove(profile.id);
    _calendarLoadedEndByProfile.remove(profile.id);
    _calendarStatesByProfile.remove(profile.id);
    _calendarErrorsByProfile.remove(profile.id);
    _calendarSyncGenerationByProfile.remove(profile.id);
    final accountStillUsed = _calendarProfiles.any(
      (candidate) => candidate.accountId == profile.accountId,
    );
    if (!accountStillUsed) {
      final account = googleAccountById(profile.accountId);
      if (account != null) {
        GoogleAuthSession.instance.forgetAccount(account.email);
      }
      _googleAccounts.removeWhere(
        (account) => account.id == profile.accountId,
      );
    }
    if (_defaultCalendarProfileId == profile.id) {
      final fallback = personalCalendarProfile ?? companyCalendarProfile;
      _defaultCalendarProfileId = fallback?.id;
      _applyDefaultCalendarProfileRole(updateTimestamps: true);
      _clearCalendarRangeCache();
      _invalidateAllCalendarProfileSyncs();
    }
    debugPrint(
      '[SPRINT-CALENDAR][SLOTS][REMOVE] profile=${profile.id} '
      'calendar=${profile.calendarId} detachedTasks=$detachedTaskCount',
    );
    _recomputeCalendarState();
    notifyListeners();
    await _persistNow();
    ensureCalendarRangeFor(_selectedDate, immediate: true);
  }

  void _activateProfileLocally(String profileId) {
    final profile = calendarProfileById(profileId);
    if (profile == null || !profile.enabled) {
      throw StateError('calendar_profile_not_found');
    }
    _calendarRangeDebounce?.cancel();
    _defaultCalendarProfileId = profileId;
    _applyDefaultCalendarProfileRole(updateTimestamps: true);
    _calendarError = null;
    _recomputeCalendarState();
  }

  void _applyDefaultCalendarProfileRole({bool updateTimestamps = false}) {
    final now = updateTimestamps ? DateTime.now() : null;
    for (final profile in _calendarProfiles) {
      final role = profile.enabled && profile.id == _defaultCalendarProfileId
          ? SprintCalendarProfileRole.primary
          : SprintCalendarProfileRole.secondary;
      if (profile.role == role) continue;
      profile.role = role;
      if (now != null) profile.updatedAt = now;
    }
  }

  String normalizeGoogleCalendarId(String value) {
    var normalized = value.trim();
    if (normalized.isEmpty) return '';
    try {
      if (normalized.startsWith('http')) {
        final uri = Uri.tryParse(normalized);
        final source = uri?.queryParameters['src'];
        if (source != null && source.trim().isNotEmpty) {
          return Uri.decodeComponent(source).trim();
        }
        final sourceIndex = normalized.indexOf('src=');
        if (sourceIndex != -1) {
          var tail = normalized.substring(sourceIndex + 4);
          final separatorIndex = tail.indexOf('&');
          if (separatorIndex != -1) {
            tail = tail.substring(0, separatorIndex);
          }
          return Uri.decodeComponent(tail).trim();
        }
      }
      if (normalized.contains('&')) {
        normalized = normalized.split('&').first;
      }
      return Uri.decodeComponent(normalized).trim();
    } catch (_) {
      return '';
    }
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

  String calendarProfileLabel(String? profileId) {
    final profile = calendarProfileById(profileId);
    if (profile == null || profile.label.trim().isEmpty) {
      return 'Google 캘린더';
    }
    return profile.label.trim();
  }

  bool isProfileAuthenticated(String profileId) {
    final account = accountForProfile(profileId);
    if (account == null || account.email.trim().isEmpty) return false;
    if (GoogleAuthSession.instance.hasCachedClientFor(account.email)) {
      return true;
    }
    final identity = GoogleAuthSession.instance.currentIdentity;
    return identity != null &&
        identity.normalizedEmail == account.normalizedEmail;
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
    return _tasks.where(_isUnplacedTask).toList(growable: false)
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
    String? calendarProfileId,
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
      calendarProfileId: calendarProfileId ?? _defaultCalendarProfileId,
      priority: parsed.priority,
      startDate: adjustedStart,
      endDate: adjustedStart.add(Duration(days: days)),
    );
  }

  SprintTaskCreationPreview? previewTaskDetails({
    required String title,
    required String description,
    required String projectId,
    String? calendarProfileId,
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
    final resolvedCalendarProfileId =
        calendarProfileId ?? _defaultCalendarProfileId;
    if (resolvedCalendarProfileId != null &&
        calendarProfileById(resolvedCalendarProfileId)?.enabled != true) {
      _taskInputError = '업무를 저장할 캘린더를 선택하세요.';
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
      calendarProfileId: resolvedCalendarProfileId,
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
      googleCalendarProfileId: preview.calendarProfileId,
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
    return _tasks.where((task) {
      return task.projectId == projectId && !task.deleteAfterSync;
    }).toList(growable: false)
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
    String? calendarProfileId,
    required SprintTaskPriority priority,
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    _taskInputError = null;
    final task = taskById(taskId);
    final project = projectById(projectId);
    final normalizedTitle = title.trim();
    final targetProfileId = calendarProfileId ??
        task?.googleCalendarProfileId ??
        _defaultCalendarProfileId;
    final targetProfile = calendarProfileById(targetProfileId);
    if (task == null) {
      _taskInputError = '업무 정보를 찾지 못했습니다.';
      return false;
    }
    if (project == null || project.status != SprintProjectStatus.active) {
      _taskInputError = '업무를 저장할 프로젝트를 선택하세요.';
      return false;
    }
    if (normalizedTitle.isEmpty) {
      _taskInputError = '업무명을 입력하세요.';
      return false;
    }
    if (targetProfileId != null && targetProfile?.enabled != true) {
      _taskInputError = '업무를 저장할 캘린더를 선택하세요.';
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
    if (validation.conflicts.any(_isHardDateConflict)) {
      _taskInputError = _dateConflictMessage(validation.conflicts);
      return false;
    }
    final previousProfileId = task.googleCalendarProfileId;
    if (previousProfileId != null &&
        previousProfileId != targetProfileId &&
        task.hasGoogleEvent) {
      final previousProfile = calendarProfileById(previousProfileId);
      final previousAccount = accountForProfile(previousProfileId);
      if (previousProfile == null || previousAccount == null) {
        _taskInputError = '기존 Google 캘린더 연결 정보를 찾지 못했습니다.';
        return false;
      }
      if (!isProfileAuthenticated(previousProfileId)) {
        try {
          await authenticateCalendarProfile(
            previousProfileId,
          );
        } catch (_) {
          _taskInputError = '현재 앱 사용자 계정으로 기존 캘린더 권한을 확인하지 못했습니다.';
          return false;
        }
      }
      final deleteResult = await _calendarSyncCoordinator.deleteTaskEvent(
        task: task,
        profile: previousProfile,
        account: previousAccount,
      );
      if (!deleteResult.success) {
        task
          ..googleSyncState = SprintGoogleSyncState.failed
          ..googleSyncError = deleteResult.error;
        _taskInputError =
            '기존 캘린더 일정 삭제를 완료하지 못했습니다. 현재 앱 사용자 계정의 Calendar 권한을 갱신한 뒤 다시 시도하세요.';
        notifyListeners();
        await _persistNow();
        return false;
      }
      task
        ..googleEventId = null
        ..googleCalendarId = null
        ..googleSyncState = SprintGoogleSyncState.none
        ..googleSyncError = null;
    }
    task
      ..googleCalendarProfileId = targetProfileId
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
    if (!_couldHaveRemoteCalendarEvent(task)) {
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
    _enqueuePendingTaskCalendarDelete(task.id);
    return true;
  }

  Future<SprintBulkDeleteResult> deleteUnplacedTasks(
    Iterable<String> taskIds,
  ) async {
    final requestedIds = taskIds
        .map((taskId) => taskId.trim())
        .where((taskId) => taskId.isNotEmpty)
        .toSet();
    if (requestedIds.isEmpty) {
      return const SprintBulkDeleteResult(
        requestedCount: 0,
        deletedCount: 0,
        pendingRemoteDeleteCount: 0,
        skippedCount: 0,
      );
    }
    await _calendarWriteQueue;
    var deletedCount = 0;
    var pendingRemoteDeleteCount = 0;
    final pendingRemoteTaskIds = <String>[];
    for (final taskId in requestedIds) {
      final task = taskById(taskId);
      if (task == null || !_isUnplacedTask(task)) continue;
      if (!_couldHaveRemoteCalendarEvent(task)) {
        _removeTaskLocally(
          task,
          refreshAttention: false,
        );
        deletedCount += 1;
        continue;
      }
      task
        ..state = SprintTaskState.cancelled
        ..googleSyncState = SprintGoogleSyncState.pendingDelete
        ..googleSyncError = null
        ..deleteAfterSync = true;
      for (final block in _blocks.where((block) => block.taskId == task.id)) {
        block.status = SprintScheduleBlockStatus.cancelled;
      }
      pendingRemoteTaskIds.add(task.id);
      pendingRemoteDeleteCount += 1;
    }
    final processedCount = deletedCount + pendingRemoteDeleteCount;
    if (processedCount > 0) {
      _refreshAttention();
      notifyListeners();
      await _persistNow();
      for (final taskId in pendingRemoteTaskIds) {
        _enqueuePendingTaskCalendarDelete(taskId);
      }
    }
    return SprintBulkDeleteResult(
      requestedCount: requestedIds.length,
      deletedCount: deletedCount,
      pendingRemoteDeleteCount: pendingRemoteDeleteCount,
      skippedCount: requestedIds.length - processedCount,
    );
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

  Future<List<SprintCalendarSyncReport>> syncGoogleCalendar() async {
    return syncGoogleCalendarFor(_selectedDate);
  }

  Future<List<SprintCalendarSyncReport>> syncGoogleCalendarFor(
    DateTime anchor,
  ) async {
    final profiles = calendarProfiles;
    _lastCalendarSyncReports.clear();
    if (profiles.isEmpty) {
      _calendarState = SprintCalendarConnectionState.notConnected;
      _calendarError = null;
      notifyListeners();
      return lastCalendarSyncReports;
    }
    if (_accountOperationInProgress) return lastCalendarSyncReports;
    _accountOperationInProgress = true;
    notifyListeners();
    try {
      for (final profile in profiles) {
        if (!isProfileAuthenticated(profile.id)) {
          final account = accountForProfile(profile.id);
          if (account != null) {
            account
              ..requiresReauthentication = true
              ..updatedAt = DateTime.now();
          }
          _calendarStatesByProfile[profile.id] =
              SprintCalendarConnectionState.reauthenticationRequired;
          _calendarErrorsByProfile[profile.id] = '현재 앱 사용자 계정의 Calendar 권한 갱신이 필요합니다.';
          _lastCalendarSyncReports.add(
            SprintCalendarSyncReport(
              profileId: profile.id,
              calendarId: profile.calendarId,
              mode: SprintCalendarSyncMode.full,
              pageCount: 0,
              receivedCount: 0,
              insertedCount: 0,
              updatedCount: 0,
              deletedCount: 0,
              unlinkedTaskCount: 0,
              tokenReset: false,
              periodicVerification: false,
              success: false,
              error: _calendarErrorsByProfile[profile.id],
            ),
          );
          continue;
        }
        final report = await _syncCalendarProfileInternal(
          profile: profile,
          anchor: _day(anchor),
          replace: true,
        );
        _lastCalendarSyncReports.add(report);
      }
      _recomputeCalendarState();
      await _persistNow();
      return lastCalendarSyncReports;
    } finally {
      _accountOperationInProgress = false;
      notifyListeners();
    }
  }

  Future<SprintCalendarSyncReport> syncCalendarProfile(
    String profileId, {
    bool interactive = true,
  }) async {
    final profile = calendarProfileById(profileId);
    if (profile == null || !profile.enabled) {
      throw StateError('calendar_profile_not_found');
    }
    if (!isProfileAuthenticated(profileId)) {
      if (!interactive) {
        _calendarStatesByProfile[profileId] =
            SprintCalendarConnectionState.reauthenticationRequired;
        _calendarErrorsByProfile[profileId] = '현재 앱 사용자 계정의 Calendar 권한 갱신이 필요합니다.';
        _recomputeCalendarState();
        notifyListeners();
        return SprintCalendarSyncReport(
          profileId: profile.id,
          calendarId: profile.calendarId,
          mode: SprintCalendarSyncMode.full,
          pageCount: 0,
          receivedCount: 0,
          insertedCount: 0,
          updatedCount: 0,
          deletedCount: 0,
          unlinkedTaskCount: 0,
          tokenReset: false,
          periodicVerification: false,
          success: false,
          error: _calendarErrorsByProfile[profileId],
        );
      }
      await authenticateCalendarProfile(profileId);
    }
    return _syncCalendarProfileInternal(
      profile: profile,
      anchor: _selectedDate,
      replace: true,
    );
  }

  SprintCalendarProfile? preferredEditableCalendarProfile([
    String? preferredProfileId,
  ]) {
    final preferred = calendarProfileById(preferredProfileId);
    if (preferred?.enabled == true && preferred!.canEditEvents) {
      return preferred;
    }
    final defaultProfile = this.defaultCalendarProfile;
    if (defaultProfile?.canEditEvents == true) return defaultProfile;
    for (final profile in editableCalendarProfiles) {
      return profile;
    }
    return null;
  }

  SprintExternalEvent? externalEventById(String? eventId) {
    if (eventId == null) return null;
    for (final event in _externalEvents) {
      if (event.id == eventId) return event;
    }
    return null;
  }

  bool canEditExternalEvent(SprintExternalEvent event) {
    final profile = calendarProfileById(event.calendarProfileId);
    return profile?.enabled == true && profile!.canEditEvents;
  }

  Future<SprintExternalEvent> createExternalCalendarEvent({
    required String calendarProfileId,
    required String title,
    required String description,
    required DateTime start,
    required DateTime end,
    required bool allDay,
  }) async {
    final normalizedTitle = title.trim();
    if (normalizedTitle.isEmpty) {
      throw ArgumentError.value(title, 'title');
    }
    if (!end.isAfter(start)) {
      throw StateError('calendar_event_invalid_range');
    }
    final profile = calendarProfileById(calendarProfileId);
    final account = accountForProfile(calendarProfileId);
    if (profile == null || account == null || !profile.enabled) {
      throw StateError('calendar_profile_not_found');
    }
    final accessRole = await _calendarService.verifyCalendarWriteAccess(
      accountEmail: account.email,
      calendarId: profile.calendarId,
    );
    profile
      ..accessRole = accessRole
      ..lastSyncError = null
      ..updatedAt = DateTime.now();
    debugPrint(
      '[SprintCalendarEvent] create profile=${profile.id} calendar=${profile.calendarId} '
      'accessRole=$accessRole allDay=$allDay start=${start.toIso8601String()} '
      'end=${end.toIso8601String()} titleLength=${normalizedTitle.length}',
    );
    try {
      final created = await _calendarService.createEvent(
        accountEmail: account.email,
        calendarId: profile.calendarId,
        summary: normalizedTitle,
        description: description.trim(),
        start: start,
        end: end,
        allDay: allDay,
        privateProperties: <String, String>{
          'source': 'parkinworkin_calendar_event',
          'calendarProfileId': profile.id,
        },
      );
      final mapped = _mapGoogleEvent(created, profile.id);
      if (mapped == null) {
        throw StateError('calendar_event_mapping_failed');
      }
      _replaceExternalEvent(mapped);
      final now = DateTime.now();
      profile
        ..lastSyncedAt = now
        ..lastSyncError = null
        ..updatedAt = now;
      _calendarStatesByProfile[profile.id] =
          SprintCalendarConnectionState.connected;
      _calendarErrorsByProfile[profile.id] = null;
      _recomputeCalendarState();
      notifyListeners();
      await _persistNow();
      debugPrint(
        '[SprintCalendarEvent] create success profile=${profile.id} '
        'event=${mapped.googleEventId} etag=${mapped.etag ?? ''}',
      );
      return mapped;
    } catch (error) {
      debugPrint(
        '[SprintCalendarEvent] create failure profile=${profile.id} error=$error',
      );
      rethrow;
    }
  }

  Future<SprintExternalEvent> updateExternalCalendarEvent({
    required String eventId,
    required String title,
    required String description,
    required DateTime start,
    required DateTime end,
    required bool allDay,
  }) async {
    final current = externalEventById(eventId);
    if (current == null) throw StateError('calendar_event_not_found');
    final normalizedTitle = title.trim();
    if (normalizedTitle.isEmpty) {
      throw ArgumentError.value(title, 'title');
    }
    if (!end.isAfter(start)) {
      throw StateError('calendar_event_invalid_range');
    }
    final profile = calendarProfileById(current.calendarProfileId);
    final account = accountForProfile(current.calendarProfileId);
    if (profile == null || account == null || !profile.enabled) {
      throw StateError('calendar_profile_not_found');
    }
    final accessRole = await _calendarService.verifyCalendarWriteAccess(
      accountEmail: account.email,
      calendarId: profile.calendarId,
    );
    profile
      ..accessRole = accessRole
      ..lastSyncError = null
      ..updatedAt = DateTime.now();
    debugPrint(
      '[SprintCalendarEvent] update profile=${profile.id} calendar=${profile.calendarId} '
      'event=${current.googleEventId} accessRole=$accessRole allDay=$allDay '
      'start=${start.toIso8601String()} end=${end.toIso8601String()} '
      'etag=${current.etag ?? ''}',
    );
    try {
      final updated = await _calendarService.updateEvent(
        accountEmail: account.email,
        calendarId: profile.calendarId,
        eventId: current.googleEventId,
        summary: normalizedTitle,
        description: description.trim(),
        start: start,
        end: end,
        allDay: allDay,
        expectedEtag: current.etag,
      );
      final mapped = _mapGoogleEvent(updated, profile.id);
      if (mapped == null) {
        throw StateError('calendar_event_mapping_failed');
      }
      _replaceExternalEvent(mapped);
      final now = DateTime.now();
      profile
        ..lastSyncedAt = now
        ..lastSyncError = null
        ..updatedAt = now;
      _calendarStatesByProfile[profile.id] =
          SprintCalendarConnectionState.connected;
      _calendarErrorsByProfile[profile.id] = null;
      _recomputeCalendarState();
      notifyListeners();
      await _persistNow();
      debugPrint(
        '[SprintCalendarEvent] update success profile=${profile.id} '
        'event=${mapped.googleEventId} etag=${mapped.etag ?? ''}',
      );
      return mapped;
    } catch (error) {
      debugPrint(
        '[SprintCalendarEvent] update failure profile=${profile.id} '
        'event=${current.googleEventId} error=$error',
      );
      rethrow;
    }
  }

  Future<void> deleteExternalCalendarEvent(String eventId) async {
    final current = externalEventById(eventId);
    if (current == null) return;
    final profile = calendarProfileById(current.calendarProfileId);
    final account = accountForProfile(current.calendarProfileId);
    if (profile == null || account == null || !profile.enabled) {
      throw StateError('calendar_profile_not_found');
    }
    final accessRole = await _calendarService.verifyCalendarWriteAccess(
      accountEmail: account.email,
      calendarId: profile.calendarId,
    );
    profile
      ..accessRole = accessRole
      ..lastSyncError = null
      ..updatedAt = DateTime.now();
    debugPrint(
      '[SprintCalendarEvent] delete profile=${profile.id} calendar=${profile.calendarId} '
      'event=${current.googleEventId} accessRole=$accessRole '
      'etag=${current.etag ?? ''}',
    );
    try {
      await _calendarService.deleteEvent(
        accountEmail: account.email,
        calendarId: profile.calendarId,
        eventId: current.googleEventId,
        expectedEtag: current.etag,
      );
      _externalEvents.removeWhere((event) => event.id == current.id);
      final now = DateTime.now();
      profile
        ..lastSyncedAt = now
        ..lastSyncError = null
        ..updatedAt = now;
      _calendarStatesByProfile[profile.id] =
          SprintCalendarConnectionState.connected;
      _calendarErrorsByProfile[profile.id] = null;
      _recomputeCalendarState();
      notifyListeners();
      await _persistNow();
      debugPrint(
        '[SprintCalendarEvent] delete success profile=${profile.id} '
        'event=${current.googleEventId}',
      );
    } catch (error) {
      final value = error.toString().toLowerCase();
      if (value.contains('404') || value.contains('not found')) {
        _externalEvents.removeWhere((event) => event.id == current.id);
        notifyListeners();
        await _persistNow();
        debugPrint(
          '[SprintCalendarEvent] delete remote-missing profile=${profile.id} '
          'event=${current.googleEventId}',
        );
        return;
      }
      debugPrint(
        '[SprintCalendarEvent] delete failure profile=${profile.id} '
        'event=${current.googleEventId} error=$error',
      );
      rethrow;
    }
  }

  void _replaceExternalEvent(SprintExternalEvent event) {
    final index = _externalEvents.indexWhere((candidate) =>
        candidate.calendarProfileId == event.calendarProfileId &&
        candidate.googleEventId == event.googleEventId);
    if (index < 0) {
      _externalEvents.add(event);
    } else {
      _externalEvents[index] = event;
    }
    _externalEvents.sort((a, b) => a.start.compareTo(b.start));
  }

  void ensureCalendarRangeFor(
    DateTime anchor, {
    bool immediate = false,
  }) {
    final profiles = _activeCalendarSlots()
        .where((profile) => isProfileAuthenticated(profile.id))
        .toList(growable: false);
    if (profiles.isEmpty) return;
    final day = _day(anchor);
    if (_isCalendarRangeLoaded(day, profiles)) return;
    _calendarRangeDebounce?.cancel();
    Future<void> run() async {
      for (final profile in profiles) {
        final loadedStart = _calendarLoadedStartByProfile[profile.id];
        final loadedEnd = _calendarLoadedEndByProfile[profile.id];
        final loaded = loadedStart != null &&
            loadedEnd != null &&
            !day.isBefore(loadedStart) &&
            !day.isAfter(loadedEnd);
        if (loaded) continue;
        await _syncCalendarProfileInternal(
          profile: profile,
          anchor: day,
          replace: false,
        );
      }
    }
    if (immediate) {
      unawaited(run());
      return;
    }
    _calendarRangeDebounce = Timer(
      const Duration(milliseconds: 280),
      () => unawaited(run()),
    );
  }

  bool _isCalendarRangeLoaded(
    DateTime day,
    List<SprintCalendarProfile> profiles,
  ) {
    if (profiles.isEmpty) return false;
    for (final profile in profiles) {
      final loadedStart = _calendarLoadedStartByProfile[profile.id];
      final loadedEnd = _calendarLoadedEndByProfile[profile.id];
      if (loadedStart == null ||
          loadedEnd == null ||
          day.isBefore(loadedStart) ||
          day.isAfter(loadedEnd)) {
        return false;
      }
    }
    return true;
  }

  Future<SprintCalendarSyncReport> _syncCalendarProfileInternal({
    required SprintCalendarProfile profile,
    DateTime? anchor,
    bool replace = true,
  }) async {
    final account = accountForProfile(profile.id);
    if (account == null || !profile.enabled) {
      _calendarStatesByProfile[profile.id] =
          SprintCalendarConnectionState.notConnected;
      _calendarErrorsByProfile[profile.id] = null;
      _recomputeCalendarState();
      notifyListeners();
      return SprintCalendarSyncReport(
        profileId: profile.id,
        calendarId: profile.calendarId,
        mode: SprintCalendarSyncMode.full,
        pageCount: 0,
        receivedCount: 0,
        insertedCount: 0,
        updatedCount: 0,
        deletedCount: 0,
        unlinkedTaskCount: 0,
        tokenReset: false,
        periodicVerification: false,
        success: false,
        error: 'calendar_profile_not_connected',
      );
    }
    if (!isProfileAuthenticated(profile.id)) {
      account.requiresReauthentication = true;
      _calendarStatesByProfile[profile.id] =
          SprintCalendarConnectionState.reauthenticationRequired;
      _calendarErrorsByProfile[profile.id] = '현재 앱 사용자 계정의 Calendar 권한 갱신이 필요합니다.';
      _recomputeCalendarState();
      notifyListeners();
      await _persistNow();
      return SprintCalendarSyncReport(
        profileId: profile.id,
        calendarId: profile.calendarId,
        mode: SprintCalendarSyncMode.full,
        pageCount: 0,
        receivedCount: 0,
        insertedCount: 0,
        updatedCount: 0,
        deletedCount: 0,
        unlinkedTaskCount: 0,
        tokenReset: false,
        periodicVerification: false,
        success: false,
        error: _calendarErrorsByProfile[profile.id],
      );
    }
    final generation = (_calendarSyncGenerationByProfile[profile.id] ?? 0) + 1;
    _calendarSyncGenerationByProfile[profile.id] = generation;
    final center = weekStart(anchor ?? _selectedDate);
    final rangeStart = center.subtract(const Duration(days: 28));
    final rangeEnd = center.add(const Duration(days: 42));
    _calendarStatesByProfile[profile.id] =
        SprintCalendarConnectionState.syncing;
    _calendarErrorsByProfile[profile.id] = null;
    _recomputeCalendarState();
    notifyListeners();
    var mode = SprintCalendarSyncMode.full;
    var tokenReset = false;
    var periodicVerification = false;
    SprintCalendarFullSyncReason? fullSyncReason;
    var pageCount = 0;
    var receivedCount = 0;
    var insertedCount = 0;
    var updatedCount = 0;
    var deletedCount = 0;
    var unlinkedTaskCount = 0;
    try {
      final accessRole = await _calendarService.calendarAccessRole(
        accountEmail: account.email,
        calendarId: profile.calendarId,
      );
      profile.accessRole = accessRole;
      final tokenCoversRange = _syncTokenCoversRange(
        profile,
        rangeStart: rangeStart,
        rangeEnd: rangeEnd,
      );
      periodicVerification = replace &&
          tokenCoversRange &&
          _periodicFullVerificationDue(profile, DateTime.now());
      final canIncremental = replace &&
          tokenCoversRange &&
          !periodicVerification;
      if (periodicVerification) {
        fullSyncReason = SprintCalendarFullSyncReason.periodicVerification;
        debugPrint(
          '[SprintCalendarSync] periodic-full-verification profile=${profile.id} '
          'calendar=${profile.calendarId} lastFull=${profile.lastFullSyncAt?.toIso8601String() ?? ''} '
          'intervalDays=${_calendarFullVerificationInterval.inDays}',
        );
      } else if (!tokenCoversRange) {
        final hasToken = profile.syncToken?.trim().isNotEmpty == true;
        fullSyncReason = hasToken
            ? SprintCalendarFullSyncReason.scopeChanged
            : SprintCalendarFullSyncReason.initial;
      }
      GoogleCalendarEventSyncResult syncResult;
      if (canIncremental) {
        mode = SprintCalendarSyncMode.incremental;
        try {
          syncResult = await _calendarService.listEventChanges(
            accountEmail: account.email,
            calendarId: profile.calendarId,
            syncToken: profile.syncToken!,
            maxResults: 500,
          );
        } on GoogleCalendarSyncTokenExpiredException {
          tokenReset = true;
          mode = SprintCalendarSyncMode.full;
          fullSyncReason = SprintCalendarFullSyncReason.tokenExpired;
          _clearProfileSyncToken(profile);
          syncResult = await _calendarService.listEventsSnapshot(
            accountEmail: account.email,
            calendarId: profile.calendarId,
            timeMin: rangeStart,
            timeMax: rangeEnd.add(const Duration(days: 1)),
            maxResults: 500,
          );
        }
      } else {
        syncResult = await _calendarService.listEventsSnapshot(
          accountEmail: account.email,
          calendarId: profile.calendarId,
          timeMin: rangeStart,
          timeMax: rangeEnd.add(const Duration(days: 1)),
          maxResults: 500,
        );
      }
      if (_calendarSyncIsStale(generation, profile.id)) {
        return SprintCalendarSyncReport(
          profileId: profile.id,
          calendarId: profile.calendarId,
          mode: mode,
          pageCount: syncResult.pageCount,
          receivedCount: syncResult.events.length,
          insertedCount: 0,
          updatedCount: 0,
          deletedCount: 0,
          unlinkedTaskCount: 0,
          tokenReset: tokenReset,
          periodicVerification: periodicVerification,
          success: false,
          fullSyncReason: fullSyncReason,
          error: 'calendar_sync_stale',
        );
      }
      pageCount = syncResult.pageCount;
      receivedCount = syncResult.events.length;
      if (mode == SprintCalendarSyncMode.incremental) {
        final stats = _applyIncrementalGoogleEvents(
          syncResult.events,
          profile: profile,
        );
        insertedCount = stats.insertedCount;
        updatedCount = stats.updatedCount;
        deletedCount = stats.deletedCount;
        unlinkedTaskCount = stats.unlinkedTaskCount;
        final nextToken = syncResult.nextSyncToken?.trim();
        if (nextToken?.isNotEmpty == true) profile.syncToken = nextToken;
        profile.lastIncrementalSyncAt = DateTime.now();
      } else {
        final before = _externalEventsForSyncRange(
          profile.id,
          rangeStart: rangeStart,
          rangeEnd: rangeEnd,
          replace: replace,
        );
        final reconciled = _reconcileGoogleEvents(
          syncResult.events,
          profile: profile,
          rangeStart: rangeStart,
          rangeEnd: rangeEnd,
        );
        final afterById = <String, SprintExternalEvent>{
          for (final event in reconciled.externalEvents) event.id: event,
        };
        final beforeById = <String, SprintExternalEvent>{
          for (final event in before) event.id: event,
        };
        insertedCount = afterById.keys
            .where((id) => !beforeById.containsKey(id))
            .length;
        deletedCount = beforeById.keys
            .where((id) => !afterById.containsKey(id))
            .length;
        updatedCount = afterById.keys.where((id) {
          final previous = beforeById[id];
          final next = afterById[id];
          return previous != null && next != null &&
              _externalEventChanged(previous, next);
        }).length + reconciled.managedUpdatedCount;
        unlinkedTaskCount = reconciled.unlinkedTaskCount;
        _mergeProfileEvents(
          profileId: profile.id,
          mapped: reconciled.externalEvents,
          rangeStart: rangeStart,
          rangeEnd: rangeEnd,
          replace: replace,
        );
        profile
          ..syncToken = syncResult.nextSyncToken?.trim()
          ..syncScopeStart = rangeStart
          ..syncScopeEnd = rangeEnd
          ..lastFullSyncAt = DateTime.now();
      }
      final syncedAt = DateTime.now();
      profile
        ..lastSyncedAt = syncedAt
        ..lastSyncError = null
        ..updatedAt = syncedAt;
      account
        ..requiresReauthentication = false
        ..updatedAt = syncedAt;
      _calendarStatesByProfile[profile.id] =
          SprintCalendarConnectionState.connected;
      _calendarErrorsByProfile[profile.id] = null;
      _externalEvents.sort((a, b) => a.start.compareTo(b.start));
      _refreshAttention();
      _recomputeCalendarState();
      notifyListeners();
      await _persistNow();
      debugPrint(
        '[SprintCalendarSync] success profile=${profile.id} '
        'mode=${mode.name} pages=$pageCount received=$receivedCount '
        'inserted=$insertedCount updated=$updatedCount deleted=$deletedCount '
        'unlinkedTasks=$unlinkedTaskCount tokenReset=$tokenReset '
        'periodicVerification=$periodicVerification '
        'fullReason=${fullSyncReason?.name ?? ''}',
      );
      _retryPendingTaskSyncs(profile.id);
      return SprintCalendarSyncReport(
        profileId: profile.id,
        calendarId: profile.calendarId,
        mode: mode,
        pageCount: pageCount,
        receivedCount: receivedCount,
        insertedCount: insertedCount,
        updatedCount: updatedCount,
        deletedCount: deletedCount,
        unlinkedTaskCount: unlinkedTaskCount,
        tokenReset: tokenReset,
        periodicVerification: periodicVerification,
        success: true,
        fullSyncReason: fullSyncReason,
      );
    } catch (error) {
      if (_calendarSyncIsStale(generation, profile.id)) {
        return SprintCalendarSyncReport(
          profileId: profile.id,
          calendarId: profile.calendarId,
          mode: mode,
          pageCount: pageCount,
          receivedCount: receivedCount,
          insertedCount: insertedCount,
          updatedCount: updatedCount,
          deletedCount: deletedCount,
          unlinkedTaskCount: unlinkedTaskCount,
          tokenReset: tokenReset,
          periodicVerification: periodicVerification,
          success: false,
          fullSyncReason: fullSyncReason,
          error: 'calendar_sync_stale',
        );
      }
      final authenticationFailure =
          error is GoogleAccountMismatchException ||
              GoogleAuthSession.isInvalidTokenError(error) ||
              error.toString().contains('google_authentication_required');
      account
        ..requiresReauthentication = authenticationFailure
        ..updatedAt = DateTime.now();
      profile
        ..lastSyncError = error.toString()
        ..updatedAt = DateTime.now();
      _calendarStatesByProfile[profile.id] = authenticationFailure
          ? SprintCalendarConnectionState.reauthenticationRequired
          : SprintCalendarConnectionState.failed;
      _calendarErrorsByProfile[profile.id] = error.toString();
      debugPrint(
        '[SprintCalendarSync] failure profile=${profile.id} '
        'calendar=${profile.calendarId} mode=${mode.name} '
        'periodicVerification=$periodicVerification '
        'fullReason=${fullSyncReason?.name ?? ''} error=$error',
      );
      _recomputeCalendarState();
      notifyListeners();
      await _persistNow();
      return SprintCalendarSyncReport(
        profileId: profile.id,
        calendarId: profile.calendarId,
        mode: mode,
        pageCount: pageCount,
        receivedCount: receivedCount,
        insertedCount: insertedCount,
        updatedCount: updatedCount,
        deletedCount: deletedCount,
        unlinkedTaskCount: unlinkedTaskCount,
        tokenReset: tokenReset,
        periodicVerification: periodicVerification,
        success: false,
        fullSyncReason: fullSyncReason,
        error: error.toString(),
      );
    }
  }

  bool _periodicFullVerificationDue(
    SprintCalendarProfile profile,
    DateTime now,
  ) {
    final last = profile.lastFullSyncAt;
    if (last == null) return false;
    if (now.isBefore(last)) return true;
    return now.difference(last) >= _calendarFullVerificationInterval;
  }

  bool _syncTokenCoversRange(
    SprintCalendarProfile profile, {
    required DateTime rangeStart,
    required DateTime rangeEnd,
  }) {
    final token = profile.syncToken?.trim();
    final scopeStart = profile.syncScopeStart;
    final scopeEnd = profile.syncScopeEnd;
    if (token == null || token.isEmpty || scopeStart == null || scopeEnd == null) {
      return false;
    }
    return !rangeStart.isBefore(scopeStart) && !rangeEnd.isAfter(scopeEnd);
  }

  void _clearProfileSyncToken(SprintCalendarProfile profile) {
    profile
      ..syncToken = null
      ..syncScopeStart = null
      ..syncScopeEnd = null
      ..lastIncrementalSyncAt = null;
  }

  List<SprintExternalEvent> _externalEventsForSyncRange(
    String profileId, {
    required DateTime rangeStart,
    required DateTime rangeEnd,
    required bool replace,
  }) {
    return _externalEvents.where((event) {
      if (event.calendarProfileId != profileId) return false;
      if (replace) return true;
      final eventStart = _day(event.start);
      final eventEnd = event.allDay
          ? _day(event.end.subtract(const Duration(days: 1)))
          : _day(event.end.subtract(const Duration(microseconds: 1)));
      return !eventEnd.isBefore(rangeStart) && !eventStart.isAfter(rangeEnd);
    }).toList(growable: false);
  }

  bool _externalEventChanged(
    SprintExternalEvent previous,
    SprintExternalEvent next,
  ) {
    return previous.title != next.title ||
        previous.description != next.description ||
        previous.start != next.start ||
        previous.end != next.end ||
        previous.allDay != next.allDay ||
        previous.blocksTime != next.blocksTime ||
        previous.colorId != next.colorId ||
        previous.etag != next.etag ||
        previous.remoteUpdatedAt != next.remoteUpdatedAt;
  }

  bool _calendarSyncIsStale(int generation, String profileId) {
    return generation != _calendarSyncGenerationByProfile[profileId] ||
        calendarProfileById(profileId)?.enabled != true;
  }

  void _invalidateCalendarProfileSync(
    String profileId, {
    bool clearRange = true,
  }) {
    _calendarSyncGenerationByProfile[profileId] =
        (_calendarSyncGenerationByProfile[profileId] ?? 0) + 1;
    if (!clearRange) return;
    _calendarLoadedStartByProfile.remove(profileId);
    _calendarLoadedEndByProfile.remove(profileId);
  }

  void _invalidateAllCalendarProfileSyncs() {
    for (final profile in _calendarProfiles) {
      _invalidateCalendarProfileSync(
        profile.id,
        clearRange: false,
      );
    }
  }

  void _mergeProfileEvents({
    required String profileId,
    required List<SprintExternalEvent> mapped,
    required DateTime rangeStart,
    required DateTime rangeEnd,
    required bool replace,
  }) {
    if (replace) {
      _externalEvents.removeWhere(
        (event) => event.calendarProfileId == profileId,
      );
      _externalEvents.addAll(mapped);
      _calendarLoadedStartByProfile[profileId] = rangeStart;
      _calendarLoadedEndByProfile[profileId] = rangeEnd;
      return;
    }
    _externalEvents.removeWhere((event) {
      if (event.calendarProfileId != profileId) return false;
      final eventStart = _day(event.start);
      final eventEnd = event.allDay
          ? _day(event.end.subtract(const Duration(days: 1)))
          : _day(event.end);
      return !eventEnd.isBefore(rangeStart) && !eventStart.isAfter(rangeEnd);
    });
    _externalEvents.addAll(mapped);
    final loadedStart = _calendarLoadedStartByProfile[profileId];
    final loadedEnd = _calendarLoadedEndByProfile[profileId];
    if (loadedStart != null &&
        loadedEnd != null &&
        !rangeEnd.isBefore(loadedStart.subtract(const Duration(days: 1))) &&
        !rangeStart.isAfter(loadedEnd.add(const Duration(days: 1)))) {
      _calendarLoadedStartByProfile[profileId] =
          rangeStart.isBefore(loadedStart) ? rangeStart : loadedStart;
      _calendarLoadedEndByProfile[profileId] =
          rangeEnd.isAfter(loadedEnd) ? rangeEnd : loadedEnd;
    } else {
      _calendarLoadedStartByProfile[profileId] = rangeStart;
      _calendarLoadedEndByProfile[profileId] = rangeEnd;
    }
  }

  void _clearCalendarRangeCache() {
    _calendarLoadedStartByProfile.clear();
    _calendarLoadedEndByProfile.clear();
  }

  Future<bool> retryTaskGoogleSync(String taskId) async {
    final task = taskById(taskId);
    if (task == null) return false;
    task.googleCalendarProfileId ??= _defaultCalendarProfileId;
    final profileId = task.googleCalendarProfileId;
    if (profileId == null) return false;
    if (!isProfileAuthenticated(profileId)) {
      try {
        await authenticateCalendarProfile(
          profileId,
        );
      } catch (_) {
        return false;
      }
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
    task.googleCalendarProfileId ??= _defaultCalendarProfileId;
    final taskProfile = calendarProfileById(task.googleCalendarProfileId);
    if (taskProfile == null || !taskProfile.enabled) return;
    task
      ..googleSyncState = task.hasGoogleEvent
          ? SprintGoogleSyncState.pendingUpdate
          : SprintGoogleSyncState.pendingCreate
      ..googleSyncError = null
      ..deleteAfterSync = false;
    notifyListeners();
    _queuePersist();
    if (!_canRunCalendarWritesFor(taskProfile.id)) return;
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
    if (!_couldHaveRemoteCalendarEvent(task)) {
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
    _enqueuePendingTaskCalendarDelete(taskId);
  }

  void _enqueuePendingTaskCalendarDelete(String taskId) {
    final task = taskById(taskId);
    if (task == null) return;
    task.googleCalendarProfileId ??= _defaultCalendarProfileId;
    final profile = calendarProfileById(task.googleCalendarProfileId);
    if (profile == null || !profile.enabled) return;
    if (!_canRunCalendarWritesFor(profile.id)) return;
    _enqueueCalendarWrite(() async {
      await _performTaskCalendarDelete(taskId);
    });
  }

  bool _couldHaveRemoteCalendarEvent(SprintTask task) {
    return task.hasGoogleEvent ||
        task.googleSyncState != SprintGoogleSyncState.none;
  }

  bool _canRunCalendarWritesFor(String profileId) {
    final profile = calendarProfileById(profileId);
    return profile != null &&
        profile.enabled &&
        profile.canEditEvents &&
        isProfileAuthenticated(profileId) &&
        calendarStateForProfile(profileId) !=
            SprintCalendarConnectionState.reauthenticationRequired;
  }

  void _markCalendarWriteUnavailable(
    SprintCalendarProfile profile,
    SprintGoogleAccount account,
  ) {
    final authenticated = isProfileAuthenticated(profile.id);
    final requiresAuthentication = !authenticated ||
        calendarStateForProfile(profile.id) ==
            SprintCalendarConnectionState.reauthenticationRequired;
    if (requiresAuthentication) {
      account
        ..requiresReauthentication = true
        ..updatedAt = DateTime.now();
      _calendarStatesByProfile[profile.id] =
          SprintCalendarConnectionState.reauthenticationRequired;
      _calendarErrorsByProfile[profile.id] = '현재 앱 사용자 계정의 Calendar 권한 갱신이 필요합니다.';
    } else if (!profile.canEditEvents) {
      account
        ..requiresReauthentication = false
        ..updatedAt = DateTime.now();
      _calendarStatesByProfile[profile.id] =
          SprintCalendarConnectionState.connected;
      _calendarErrorsByProfile[profile.id] =
          '이 Google 캘린더는 읽기 전용입니다.';
    } else {
      _calendarStatesByProfile[profile.id] =
          SprintCalendarConnectionState.failed;
      _calendarErrorsByProfile[profile.id] =
          'Google 캘린더 동기화 상태를 확인하세요.';
    }
    debugPrint(
      '[SprintCalendarWrite] blocked profile=${profile.id} '
      'accessRole=${profile.accessRole} authenticated=$authenticated '
      'state=${calendarStateForProfile(profile.id).name}',
    );
    _recomputeCalendarState();
    notifyListeners();
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
    task.googleCalendarProfileId ??= _defaultCalendarProfileId;
    final profile = calendarProfileById(task.googleCalendarProfileId);
    final account = accountForProfile(profile?.id);
    if (profile == null || account == null || !profile.enabled) return false;
    if (!_canRunCalendarWritesFor(profile.id)) {
      _markCalendarWriteUnavailable(profile, account);
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
      if (result.error != null &&
          (GoogleAuthSession.isInvalidTokenError(StateError(result.error!)) ||
              result.error!.contains('google_account_mismatch'))) {
        account.requiresReauthentication = true;
        _calendarStatesByProfile[profile.id] =
            SprintCalendarConnectionState.reauthenticationRequired;
      }
    }
    _recomputeCalendarState();
    notifyListeners();
    await _persistNow();
    return result.success;
  }

  Future<bool> _performTaskCalendarDelete(String taskId) async {
    final task = taskById(taskId);
    if (task == null) return false;
    task.googleCalendarProfileId ??= _defaultCalendarProfileId;
    final profile = calendarProfileById(task.googleCalendarProfileId);
    final account = accountForProfile(profile?.id);
    if (profile == null || account == null || !profile.enabled) return false;
    if (task.hasGoogleEvent && !_canRunCalendarWritesFor(profile.id)) {
      _markCalendarWriteUnavailable(profile, account);
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

  void _retryPendingTaskSyncs([String? onlyProfileId]) {
    final profileIds = onlyProfileId == null
        ? _activeCalendarSlots().map((profile) => profile.id).toSet()
        : <String>{onlyProfileId};
    var localStateChanged = false;
    for (final profileId in profileIds) {
      if (!_canRunCalendarWritesFor(profileId)) continue;
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
          task.googleCalendarProfileId = _defaultCalendarProfileId;
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
    }
    if (localStateChanged) {
      notifyListeners();
      _queuePersist();
    }
  }

  _CalendarReconcileResult _reconcileGoogleEvents(
    List<gcal.Event> events, {
    required SprintCalendarProfile profile,
    required DateTime rangeStart,
    required DateTime rangeEnd,
  }) {
    final external = <SprintExternalEvent>[];
    final remoteManagedIds = <String>{};
    var managedUpdatedCount = 0;
    var unlinkedTaskCount = 0;
    for (final event in events) {
      final mapped = _mapGoogleEvent(event, profile.id);
      if (mapped == null) continue;
      final task = _taskForMappedGoogleEvent(mapped, profile.id);
      if (mapped.managedBySprint && task != null) {
        remoteManagedIds.add(mapped.googleEventId);
        if (!_taskHasPendingCalendarMutation(task)) {
          if (_applyMappedGoogleEventToTask(task, mapped, profile)) {
            managedUpdatedCount += 1;
          }
        }
        continue;
      }
      external.add(mapped);
    }
    for (final task in _tasks) {
      if (task.googleCalendarProfileId != profile.id ||
          !task.hasGoogleEvent ||
          _taskHasPendingCalendarMutation(task)) {
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
      debugPrint(
        '[SprintCalendarSync] remote event removed profile=${profile.id} '
        'task=${task.id} event=${task.googleEventId ?? ''}',
      );
      _unlinkTaskFromGoogleCalendar(task);
      unlinkedTaskCount += 1;
    }
    return _CalendarReconcileResult(
      externalEvents: external,
      managedUpdatedCount: managedUpdatedCount,
      unlinkedTaskCount: unlinkedTaskCount,
    );
  }

  _CalendarApplyStats _applyIncrementalGoogleEvents(
    List<gcal.Event> events, {
    required SprintCalendarProfile profile,
  }) {
    var insertedCount = 0;
    var updatedCount = 0;
    var deletedCount = 0;
    var unlinkedTaskCount = 0;
    for (final event in events) {
      final googleEventId = event.id?.trim();
      if (googleEventId == null || googleEventId.isEmpty) continue;
      if (event.status == 'cancelled') {
        final beforeExternal = _externalEvents.length;
        _externalEvents.removeWhere(
          (candidate) =>
              candidate.calendarProfileId == profile.id &&
              candidate.googleEventId == googleEventId,
        );
        if (_externalEvents.length != beforeExternal) deletedCount += 1;
        final task = _taskByGoogleEventId(profile.id, googleEventId);
        if (task != null && !_taskHasPendingCalendarMutation(task)) {
          _unlinkTaskFromGoogleCalendar(task);
          unlinkedTaskCount += 1;
        }
        continue;
      }
      final mapped = _mapGoogleEvent(event, profile.id);
      if (mapped == null) continue;
      final task = _taskForMappedGoogleEvent(mapped, profile.id);
      if (mapped.managedBySprint && task != null) {
        if (!_taskHasPendingCalendarMutation(task) &&
            _applyMappedGoogleEventToTask(task, mapped, profile)) {
          updatedCount += 1;
        }
        _externalEvents.removeWhere(
          (candidate) =>
              candidate.calendarProfileId == profile.id &&
              candidate.googleEventId == mapped.googleEventId,
        );
        continue;
      }
      final existing = externalEventById(mapped.id);
      if (existing == null) {
        insertedCount += 1;
      } else if (_externalEventChanged(existing, mapped)) {
        updatedCount += 1;
      }
      _replaceExternalEvent(mapped);
    }
    return _CalendarApplyStats(
      insertedCount: insertedCount,
      updatedCount: updatedCount,
      deletedCount: deletedCount,
      unlinkedTaskCount: unlinkedTaskCount,
    );
  }

  SprintTask? _taskForMappedGoogleEvent(
    SprintExternalEvent event,
    String profileId,
  ) {
    final linked = taskById(event.linkedTaskId);
    if (linked != null) return linked;
    return _taskByGoogleEventId(profileId, event.googleEventId);
  }

  SprintTask? _taskByGoogleEventId(String profileId, String googleEventId) {
    for (final task in _tasks) {
      if (task.googleCalendarProfileId == profileId &&
          task.googleEventId == googleEventId) {
        return task;
      }
    }
    return null;
  }

  bool _taskHasPendingCalendarMutation(SprintTask task) {
    return task.googleSyncState == SprintGoogleSyncState.pendingCreate ||
        task.googleSyncState == SprintGoogleSyncState.pendingUpdate ||
        task.googleSyncState == SprintGoogleSyncState.pendingDelete ||
        task.googleSyncState == SprintGoogleSyncState.failed ||
        task.deleteAfterSync;
  }

  bool _applyMappedGoogleEventToTask(
    SprintTask task,
    SprintExternalEvent event,
    SprintCalendarProfile profile,
  ) {
    final nextStart = _day(event.start);
    final rawEnd = event.allDay
        ? event.end.subtract(const Duration(days: 1))
        : event.end.subtract(const Duration(microseconds: 1));
    final nextEndCandidate = _day(rawEnd);
    final nextEnd = nextEndCandidate.isBefore(nextStart)
        ? nextStart
        : nextEndCandidate;
    final changed = task.title != event.title ||
        task.description != event.description ||
        task.startDate != nextStart ||
        task.endDate != nextEnd ||
        task.googleEventId != event.googleEventId ||
        task.googleCalendarId != profile.calendarId ||
        task.googleCalendarProfileId != profile.id ||
        task.googleSyncState != SprintGoogleSyncState.synced;
    task
      ..title = event.title
      ..description = event.description
      ..startDate = nextStart
      ..endDate = nextEnd
      ..googleEventId = event.googleEventId
      ..googleCalendarId = profile.calendarId
      ..googleCalendarProfileId = profile.id
      ..googleSyncState = SprintGoogleSyncState.synced
      ..googleSyncError = null
      ..deleteAfterSync = false;
    _syncBlockFromTask(task);
    return changed;
  }

  void _unlinkTaskFromGoogleCalendar(SprintTask task) {
    task
      ..googleEventId = null
      ..googleCalendarId = null
      ..googleCalendarProfileId = null
      ..googleSyncState = SprintGoogleSyncState.none
      ..googleSyncError = null
      ..deleteAfterSync = false;
  }

  void _removeTaskLocally(
    SprintTask task, {
    bool refreshAttention = true,
    bool recordActivity = true,
  }) {
    _blocks.removeWhere((block) => block.taskId == task.id);
    _attentionItems.removeWhere((item) => item.taskId == task.id);
    _tasks.remove(task);
    if (recordActivity) {
      _recordActivity(
        type: SprintActivityEventType.taskDeleted,
        projectId: task.projectId,
        taskId: task.id,
      );
    }
    if (refreshAttention) _refreshAttention();
  }

  Future<void> disconnectCalendarProfile(String profileId) async {
    if (_accountOperationInProgress) return;
    final profile = calendarProfileById(profileId);
    final account = accountForProfile(profileId);
    if (profile == null || account == null) return;
    _calendarRangeDebounce?.cancel();
    GoogleAuthSession.instance.forgetAccount(account.email);
    account
      ..requiresReauthentication = true
      ..updatedAt = DateTime.now();
    for (final candidate in _calendarProfiles.where(
      (candidate) => candidate.accountId == account.id,
    )) {
      _invalidateCalendarProfileSync(candidate.id);
      _calendarStatesByProfile[candidate.id] =
          SprintCalendarConnectionState.reauthenticationRequired;
      _calendarErrorsByProfile[candidate.id] = null;
    }
    _recomputeCalendarState();
    notifyListeners();
    await _persistNow();
  }

  Future<void> disconnectGoogleCalendar() async {
    final profileId = _defaultCalendarProfileId;
    if (profileId == null) return;
    await disconnectCalendarProfile(profileId);
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
        task.googleCalendarProfileId = _defaultCalendarProfileId;
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

  bool _isUnplacedTask(SprintTask task) {
    return !task.deleteAfterSync &&
        _taskBelongsToActiveProject(task) &&
        task.state != SprintTaskState.completed &&
        task.state != SprintTaskState.cancelled &&
        _blockForTask(task.id) == null;
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
      description: event.description?.trim() ?? '',
      start: start,
      end: end,
      allDay: allDay,
      blocksTime: event.transparency != 'transparent',
      sourceUrl: event.htmlLink,
      colorId: event.colorId,
      etag: event.etag,
      remoteUpdatedAt: event.updated?.toLocal(),
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
        defaultCalendarProfileId: _defaultCalendarProfileId,
        workspaceScope: _workspaceScope,
        selectedDate: _selectedDate,
        lastObservedToday: _lastObservedToday,
        weekMode: _weekMode,
        googleCalendarId: googleCalendarId,
        googleCalendarIdLocked: googleCalendarIdLocked,
        legacyCalendarConfigured: defaultCalendarProfile != null,
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


class _CalendarReconcileResult {
  const _CalendarReconcileResult({
    required this.externalEvents,
    required this.managedUpdatedCount,
    required this.unlinkedTaskCount,
  });

  final List<SprintExternalEvent> externalEvents;
  final int managedUpdatedCount;
  final int unlinkedTaskCount;
}

class _CalendarApplyStats {
  const _CalendarApplyStats({
    required this.insertedCount,
    required this.updatedCount,
    required this.deletedCount,
    required this.unlinkedTaskCount,
  });

  final int insertedCount;
  final int updatedCount;
  final int deletedCount;
  final int unlinkedTaskCount;
}
