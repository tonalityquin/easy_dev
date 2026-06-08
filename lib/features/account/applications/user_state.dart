import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';
import '../../../app/init/work_schedule_prefs.dart';
import '../../../app/utils/dev_firebase_debug_dialog.dart';
import '../../../shared/tts/application/tts_ownership.dart';
import '../../../shared/tts/application/tts_user_filters.dart';
import '../../../shared/tts/services/plate/plate_tts_listener_service.dart';
import '../../commute/domain/repositories/commute_log_repository.dart';
import '../../mode_single/application/att_brk_repository.dart';
import '../../dashboard/applications/common/firebase_google_auth_bridge.dart';
import '../../dev/application/area_state.dart';
import '../domain/models/session_account.dart';
import '../domain/models/tablet/tablet_model.dart';
import '../domain/models/user/user_model.dart';
import '../domain/repositories/user_repository.dart';


class UserState extends ChangeNotifier {
  final UserRepository _repository;
  final AreaState _areaState;

  SessionAccount? _session;
  UserModel? _user;
  TabletModel? _tablet;

  List<UserModel> _userList = const [];
  List<TabletModel> _tabletList = const [];

  String? _selectedUserId;
  bool _isLoading = true;

  bool _isTablet = false;

  bool _hasClockInToday = false;
  String? _hasClockInTodayForDate;

  StreamSubscription<List<UserModel>>? _subscription;

  String _prevAreaUsers = '';
  String _prevAreaTablets = '';

  static const String _prefsKeyCachedUser = 'cachedUserJson';

  static const Set<String> _userSensitiveKeys = <String>{
    'phone',
    'handle',
    'role',
    'division',
    'position',
    'startTime',
    'endTime',
    'fixedHolidays',
    WorkSchedulePrefs.breakDaysKey,
    WorkSchedulePrefs.startMapKey,
    WorkSchedulePrefs.endMapKey,
    _prefsKeyCachedUser,
  };

  SessionAccount? get session => _session;

  TabletModel? get tablet => _tablet;

  UnmodifiableListView<UserModel> get users => UnmodifiableListView(_userList);

  UnmodifiableListView<TabletModel> get tabletUsers =>
      UnmodifiableListView(_tabletList);

  UnmodifiableListView<TabletModel> get tablets => tabletUsers;

  String? get selectedUserId => _selectedUserId;

  bool get isLoggedIn => _session != null;

  bool get isWorking => _session?.isWorking ?? false;

  bool get isLoading => _isLoading;

  bool get isTablet => _isTablet;

  bool get hasClockInToday => _hasClockInToday;

  String get role => _session?.role ?? '';

  String get position => _user?.position ?? _tablet?.position ?? '';

  String get name => _session?.displayName ?? '';

  String get phone => _user?.phone ?? _tablet?.handle ?? '';

  String get password => _user?.password ?? _tablet?.password ?? '';

  String get area =>
      _user?.areas.firstOrNull ?? _tablet?.areas.firstOrNull ?? '';

  String get division =>
      _user?.divisions.firstOrNull ?? _tablet?.divisions.firstOrNull ?? '';

  String get currentArea => _session?.currentArea ?? area;

  String? get _clockInCacheDateKey => _session == null ? null : 'clockInDate';

  String? get _clockInCacheFlagKey => _session == null ? null : 'clockInHas';

  UserState(this._repository, this._areaState) {
    _areaState.addListener(_fetchUsersByAreaWithCache);
  }

  Future<void> _startTtsForArea(String area) async {
    final trimmed = area.trim();
    if (trimmed.isEmpty) return;

    Future<bool> sendToForeground(String a) async {
      try {
        final running = await FlutterForegroundTask.isRunningService;
        if (!running) return false;
        final filters = await TtsUserFilters.load();
        FlutterForegroundTask.sendDataToTask({
          'area': a,
          'ttsFilters': filters.toMap(),
        });
        return true;
      } catch (_) {
        return false;
      }
    }

    try {
      final owner = await TtsOwnership.getOwner();
      if (owner == TtsOwner.app) {
        PlateTtsListenerService.start(trimmed);
        return;
      }

      final ok = await sendToForeground(trimmed);
      await PlateTtsListenerService.stop();
      if (!ok) {
        try {
          await TtsOwnership.setOwner(TtsOwner.app);
        } catch (_) {}
        PlateTtsListenerService.start(trimmed);
      }
    } catch (_) {
      PlateTtsListenerService.start(trimmed);
    }
  }

  void _clearSelectionSilently() {
    _selectedUserId = null;
  }

  void _guardSessionSwitchOrThrow(String updatedId,
      {required bool expectTablet}) {
    if (_session == null) return;
    if (_session!.id != updatedId) {
      throw StateError('SESSION_SWITCH_BLOCKED: ${_session!.id} -> $updatedId');
    }

    if (_isTablet != expectTablet) {
      debugPrint(
          '⚠️ Session mode mismatch: isTablet=$_isTablet expect=$expectTablet');
    }
  }

  Future<void> refreshUsersBySelectedAreaAndCache() async {
    final selectedArea = _areaState.currentArea.trim();
    final currentDivision = _areaState.currentDivision.trim();

    _clearSelectionSilently();

    _isLoading = true;
    notifyListeners();

    try {
      final data = currentDivision.isNotEmpty
          ? await _repository.refreshUsersByDivisionAreaFromShow(
              currentDivision, selectedArea)
          : await _repository.refreshUsersBySelectedArea(selectedArea);

      _userList = List<UserModel>.of(data, growable: false);
      _clearSelectionSilently();
      _prevAreaUsers = selectedArea;
    } catch (e) {
      _clearSelectionSilently();
      debugPrint('🔥 Error refreshing users: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> refreshTabletsBySelectedAreaAndCache() async {
    final selectedArea = _areaState.currentArea.trim();

    _clearSelectionSilently();

    _isLoading = true;
    notifyListeners();

    try {
      final data = await _repository.refreshTabletsBySelectedArea(selectedArea);
      _tabletList = List<TabletModel>.of(data, growable: false);
      _clearSelectionSilently();
      _prevAreaTablets = selectedArea;
    } catch (e) {
      _clearSelectionSilently();
      debugPrint('🔥 Error refreshing tablets: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> isHeWorking() async {
    if (_isTablet) {
      if (_tablet == null) return;
      final newStatus = !_tablet!.isWorking;
      await _repository.updateWorkingTabletStatus(
        _tablet!.handle,
        _tablet!.areas.firstOrNull ?? '',
        isWorking: newStatus,
      );
      _tablet = _tablet!.copyWith(isWorking: newStatus);
      _session = TabletSessionAccount(_tablet!);
      notifyListeners();
      return;
    }

    if (_user == null) return;
    final newStatus = !_user!.isWorking;
    await _repository.updateWorkingUserStatus(
      _user!.phone,
      _user!.areas.firstOrNull ?? '',
      isWorking: newStatus,
    );
    _user = _user!.copyWith(isWorking: newStatus);
    _session = UserSessionAccount(_user!);
    notifyListeners();
  }

  String? _tryParseLimitError(Object e, String key) {
    final s = e.toString();
    final idx = s.indexOf(key);
    if (idx < 0) return null;
    return s.substring(idx + key.length).trim();
  }

  String? _tryParseActiveLimitError(Object e) {
    return _tryParseLimitError(e, 'ACTIVE_LIMIT_REACHED:');
  }

  String? _tryParseTotalLimitError(Object e) {
    return _tryParseLimitError(e, 'TOTAL_LIMIT_REACHED:');
  }

  Future<void> setSelectedUserActiveStatus(
    bool isActive, {
    void Function(String)? onError,
  }) async {
    final selectedId = _selectedUserId;
    if (selectedId == null) {
      onError?.call('선택된 계정이 없습니다.');
      return;
    }

    try {
      await _repository.setUserActiveStatus(selectedId, isActive: isActive);

      final area = _areaState.currentArea.trim();
      final idx = _userList.indexWhere((u) => u.id == selectedId);
      if (idx >= 0) {
        final updated = _userList[idx].copyWith(isActive: isActive);
        _userList = _replaceItem(_userList, updated);
        await _repository.updateUsersCache(area, _userList);
      }

      notifyListeners();
    } catch (e) {
      final activeLimit = _tryParseActiveLimitError(e);
      if (activeLimit != null && isActive) {
        onError?.call('활성화 제한에 도달했습니다. (최대 $activeLimit)');
        return;
      }
      final totalLimit = _tryParseTotalLimitError(e);
      if (totalLimit != null) {
        onError?.call('전체 계정 제한에 도달했습니다. (최대 $totalLimit)');
        return;
      }
      onError?.call('계정 활성 상태 변경 실패: $e');
    }
  }

  Future<void> ensureTodayClockInStatus() async {
    if (_user == null) return;

    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());

    if (_hasClockInTodayForDate == today) {
      return;
    }

    try {
      final dateKey = _clockInCacheDateKey;
      final flagKey = _clockInCacheFlagKey;

      if (dateKey != null && flagKey != null) {
        final prefs = await SharedPreferences.getInstance();
        final cachedDate = prefs.getString(dateKey);
        final cachedHas = prefs.getBool(flagKey);

        if (cachedDate == today && cachedHas != null) {
          _hasClockInToday = cachedHas;
          _hasClockInTodayForDate = today;
          notifyListeners();
          return;
        }
      }
    } catch (e, st) {
      debugPrint('ensureTodayClockInStatus prefs 캐시 읽기 실패: $e\n$st');
    }

    try {
      final repo = CommuteLogRepository();
      final exists = await repo.hasLogForDate(
        status: '출근',
        userId: _user!.id,
        dateStr: today,
      );

      _hasClockInToday = exists;
      _hasClockInTodayForDate = today;

      final dateKey = _clockInCacheDateKey;
      final flagKey = _clockInCacheFlagKey;
      if (dateKey != null && flagKey != null) {
        try {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(dateKey, today);
          await prefs.setBool(flagKey, exists);
        } catch (e, st) {
          debugPrint('ensureTodayClockInStatus prefs 캐시 쓰기 실패: $e\n$st');
        }
      }

      notifyListeners();
    } catch (e, st) {
      debugPrint('ensureTodayClockInStatus Firestore 실패: $e\n$st');
    }
  }

  void markClockInToday() {
    if (_user == null) return;

    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    _hasClockInToday = true;
    _hasClockInTodayForDate = today;
    notifyListeners();

    final dateKey = _clockInCacheDateKey;
    final flagKey = _clockInCacheFlagKey;
    if (dateKey != null && flagKey != null) {
      SharedPreferences.getInstance().then((prefs) async {
        try {
          await prefs.setString(dateKey, today);
          await prefs.setBool(flagKey, true);
        } catch (e, st) {
          debugPrint('markClockInToday prefs 캐시 쓰기 실패: $e\n$st');
        }
      });
    }
  }

  Future<void> clearClockInIssueFlag() async {
    if (_user == null) return;

    final now = DateTime.now();
    final today = DateFormat('yyyy-MM-dd').format(now);
    _hasClockInToday = false;
    _hasClockInTodayForDate = today;
    notifyListeners();

    try {
      await AttBrkRepository.instance.clearEventsForDate(now);
    } catch (e, st) {
      debugPrint('clearClockInIssueFlag 로컬 펀칭 초기화 실패: $e\n$st');
    }

    final dateKey = _clockInCacheDateKey;
    final flagKey = _clockInCacheFlagKey;
    if (dateKey == null || flagKey == null) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(dateKey, today);
      await prefs.setBool(flagKey, false);
    } catch (e, st) {
      debugPrint('clearClockInIssueFlag prefs 캐시 쓰기 실패: $e\n$st');
    }
  }

  Future<void> updateLoginUser(UserModel updatedUser) async {
    _guardSessionSwitchOrThrow(updatedUser.id, expectTablet: false);

    _isTablet = false;
    _user = updatedUser;
    _tablet = null;
    _session = UserSessionAccount(updatedUser);
    notifyListeners();

    final firebaseOk = await FirebaseGoogleAuthBridge.instance
        .ensureSignedInFromGoogleSession(interactive: false);
    debugPrint(
        '[USER-STATE][${DateTime.now().toIso8601String()}] updateLoginUser firebaseOk=$firebaseOk currentUser=${FirebaseGoogleAuthBridge.instance.currentUser?.email} anonymous=${FirebaseGoogleAuthBridge.instance.currentUser?.isAnonymous}');

    await _repository.updateUser(updatedUser);

    final area = _areaState.currentArea.trim();
    _userList = _replaceItem(_userList, updatedUser);
    await _repository.updateUsersCache(area, _userList);

    await saveCardToUserPhone(updatedUser);
  }

  Future<void> updateLoginUserLocalOnly(UserModel updatedUser) async {
    _isTablet = false;
    _user = updatedUser;
    _tablet = null;
    _session = UserSessionAccount(updatedUser);

    _hasClockInToday = false;
    _hasClockInTodayForDate = null;

    notifyListeners();

    final firebaseOk = await FirebaseGoogleAuthBridge.instance
        .ensureSignedInFromGoogleSession(interactive: false);
    debugPrint(
        '[USER-STATE][${DateTime.now().toIso8601String()}] updateLoginUserLocalOnly firebaseOk=$firebaseOk currentUser=${FirebaseGoogleAuthBridge.instance.currentUser?.email} anonymous=${FirebaseGoogleAuthBridge.instance.currentUser?.isAnonymous}');

    await saveCardToUserPhone(updatedUser);
  }

  Future<void> _applyCurrentUserScheduleLocalOnly(UserModel updatedUser) async {
    _guardSessionSwitchOrThrow(updatedUser.id, expectTablet: false);

    _isTablet = false;
    _user = updatedUser;
    _tablet = null;
    _session = UserSessionAccount(updatedUser);
    _userList = _replaceItem(_userList, updatedUser);
    notifyListeners();

    await saveCardToUserPhone(updatedUser);
    final prefs = await SharedPreferences.getInstance();
    await WorkSchedulePrefs.refreshReminderFromPrefs(prefs);
  }


  List<String> _normalizedBreakDaysForUser({
    required UserModel user,
    required SharedPreferences prefs,
    required Map<String, TimeOfDay?> startByWeekday,
    required Map<String, TimeOfDay?> endByWeekday,
  }) {
    final raw = prefs.containsKey(WorkSchedulePrefs.breakDaysKey)
        ? WorkSchedulePrefs.readBreakDaysFromPrefs(prefs)
        : user.breakDays;
    return WorkSchedulePrefs.normalizeBreakDaysForWorkingMap(
      breakDays: raw,
      startByDay: startByWeekday,
      endByDay: endByWeekday,
    );
  }

  Future<bool> setCurrentUserWeekdayEndTime({
    required String day,
    required TimeOfDay endTime,
  }) async {
    if (_isTablet || _user == null) return false;
    if (!WorkSchedulePrefs.days.contains(day)) return false;

    final normalizedEnd = WorkSchedulePrefs.normalizeDayTimeMap(
      _user!.endTimeByWeekday,
    );
    normalizedEnd[day] = endTime;

    final fixedHolidays = _user!.fixedHolidays
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty && value != day)
        .toList(growable: false);

    final updatedUser = _user!.copyWith(
      endTime: WorkSchedulePrefs.pickRepresentative(normalizedEnd) ?? endTime,
      endTimeByWeekday: normalizedEnd,
      fixedHolidays: fixedHolidays,
    );

    try {
      await _applyCurrentUserScheduleLocalOnly(updatedUser);
      return true;
    } catch (e, st) {
      debugPrint('setCurrentUserWeekdayEndTime local error: $e\n$st');
      return false;
    }
  }

  Future<bool> setCurrentUserWeekdayWorkTimeLocalOnly({
    required String day,
    required TimeOfDay? startTime,
    required TimeOfDay? endTime,
  }) async {
    if (_isTablet || _user == null) return false;
    if (!WorkSchedulePrefs.days.contains(day)) return false;
    if ((startTime == null) != (endTime == null)) return false;

    final normalizedStart = WorkSchedulePrefs.normalizeDayTimeMap(
      _user!.startTimeByWeekday,
    );
    final normalizedEnd = WorkSchedulePrefs.normalizeDayTimeMap(
      _user!.endTimeByWeekday,
    );

    final wasWorking = normalizedStart[day] != null && normalizedEnd[day] != null;

    normalizedStart[day] = startTime;
    normalizedEnd[day] = endTime;

    final holidaySet = _user!.fixedHolidays
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toSet();

    if (startTime == null && endTime == null) {
      holidaySet.add(day);
    } else {
      holidaySet.remove(day);
    }

    final fixedHolidays = <String>[
      for (final value in WorkSchedulePrefs.days)
        if (holidaySet.contains(value)) value,
      for (final value in holidaySet)
        if (!WorkSchedulePrefs.days.contains(value)) value,
    ];

    final breakSet = _user!.breakDays
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toSet();

    if (startTime == null && endTime == null) {
      breakSet.remove(day);
    } else if (!wasWorking) {
      breakSet.add(day);
    }

    final breakDays = WorkSchedulePrefs.normalizeBreakDaysForWorkingMap(
      breakDays: breakSet,
      startByDay: normalizedStart,
      endByDay: normalizedEnd,
    );

    final current = _user!;
    final updatedUser = UserModel(
      id: current.id,
      areas: current.areas,
      currentArea: current.currentArea,
      divisions: current.divisions,
      modes: current.modes,
      email: current.email,
      endTime: WorkSchedulePrefs.pickRepresentative(normalizedEnd),
      englishSelectedAreaName: current.englishSelectedAreaName,
      fixedHolidays: fixedHolidays,
      breakDays: breakDays,
      isSaved: current.isSaved,
      isSelected: current.isSelected,
      isWorking: current.isWorking,
      name: current.name,
      password: current.password,
      phone: current.phone,
      position: current.position,
      role: current.role,
      selectedArea: current.selectedArea,
      startTime: WorkSchedulePrefs.pickRepresentative(normalizedStart),
      startTimeByWeekday: normalizedStart,
      endTimeByWeekday: normalizedEnd,
      isActive: current.isActive,
    );

    try {
      await _applyCurrentUserScheduleLocalOnly(updatedUser);
      return true;
    } catch (e, st) {
      debugPrint('setCurrentUserWeekdayWorkTimeLocalOnly error: $e\n$st');
      return false;
    }
  }

  Future<bool> setCurrentUserWeekdayWorkTime({
    required String day,
    required TimeOfDay? startTime,
    required TimeOfDay? endTime,
  }) {
    return setCurrentUserWeekdayWorkTimeLocalOnly(
      day: day,
      startTime: startTime,
      endTime: endTime,
    );
  }


  Future<bool> setCurrentUserBreakDayLocalOnly({
    required String day,
    required bool hasBreak,
  }) async {
    if (_isTablet || _user == null) return false;
    if (!WorkSchedulePrefs.days.contains(day)) return false;

    final normalizedStart = WorkSchedulePrefs.normalizeDayTimeMap(
      _user!.startTimeByWeekday,
    );
    final normalizedEnd = WorkSchedulePrefs.normalizeDayTimeMap(
      _user!.endTimeByWeekday,
    );

    if (hasBreak && (normalizedStart[day] == null || normalizedEnd[day] == null)) {
      return false;
    }

    final breakSet = _user!.breakDays
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toSet();

    if (hasBreak) {
      breakSet.add(day);
    } else {
      breakSet.remove(day);
    }

    final breakDays = WorkSchedulePrefs.normalizeBreakDaysForWorkingMap(
      breakDays: breakSet,
      startByDay: normalizedStart,
      endByDay: normalizedEnd,
    );

    final updatedUser = _user!.copyWith(breakDays: breakDays);

    try {
      await _applyCurrentUserScheduleLocalOnly(updatedUser);
      return true;
    } catch (e, st) {
      debugPrint('setCurrentUserBreakDayLocalOnly error: $e\n$st');
      return false;
    }
  }

  Future<void> updateLoginTablet(TabletModel updatedTablet) async {
    _guardSessionSwitchOrThrow(updatedTablet.id, expectTablet: true);

    _isTablet = true;
    _user = null;
    _tablet = updatedTablet;
    _session = TabletSessionAccount(updatedTablet);
    notifyListeners();

    final firebaseOk = await FirebaseGoogleAuthBridge.instance
        .ensureSignedInFromGoogleSession(interactive: false);
    debugPrint(
        '[USER-STATE][${DateTime.now().toIso8601String()}] updateLoginTablet firebaseOk=$firebaseOk currentUser=${FirebaseGoogleAuthBridge.instance.currentUser?.email} anonymous=${FirebaseGoogleAuthBridge.instance.currentUser?.isAnonymous}');

    await _repository.updateTablet(updatedTablet);

    final area = _areaState.currentArea.trim();
    _tabletList = _replaceTabletItem(_tabletList, updatedTablet);
    await _repository.updateTabletsCache(area, _tabletList);

    await _saveTabletPrefs(updatedTablet);
  }

  Future<bool> updateUserCardAsAdmin(
    UserModel updatedUser, {
    void Function(String)? onError,
  }) async {
    try {
      await _repository.updateUser(updatedUser);

      final area = _areaState.currentArea.trim();
      _userList = _replaceItem(_userList, updatedUser);
      await _repository.updateUsersCache(area, _userList);

      notifyListeners();
      return true;
    } catch (e, st) {
      debugPrint('updateUserCardAsAdmin error: $e\n$st');
      final activeLimit = _tryParseActiveLimitError(e);
      if (activeLimit != null) {
        onError?.call('활성화 제한에 도달했습니다. (최대 $activeLimit)');
        return false;
      }
      final totalLimit = _tryParseTotalLimitError(e);
      if (totalLimit != null) {
        onError?.call('전체 계정 제한에 도달했습니다. (최대 $totalLimit)');
        return false;
      }
      onError?.call('사용자 수정 실패: $e');
      return false;
    }
  }

  Future<bool> updateTabletCardAsAdmin(
    TabletModel updatedTablet, {
    String? previousId,
    void Function(String)? onError,
  }) async {
    try {
      await _repository.updateTablet(updatedTablet);
      if (previousId != null &&
          previousId.isNotEmpty &&
          previousId != updatedTablet.id) {
        await _repository.deleteTablets(<String>[previousId]);
      }

      final area = _areaState.currentArea.trim();
      if (previousId != null &&
          previousId.isNotEmpty &&
          previousId != updatedTablet.id) {
        _tabletList = _tabletList
            .where((t) => t.id != previousId)
            .toList(growable: false);
      }
      _tabletList = _replaceTabletItem(_tabletList, updatedTablet);
      await _repository.updateTabletsCache(area, _tabletList);

      notifyListeners();
      return true;
    } catch (e, st) {
      debugPrint('updateTabletCardAsAdmin error: $e\n$st');
      onError?.call('태블릿 수정 실패: $e');
      return false;
    }
  }

  Future<void> clearUserToPhone() async {
    if (_isTablet) {
      if (_tablet == null) return;
    } else {
      if (_user == null) return;
    }

    try {
      if (_isTablet) {
        await _repository.updateLogOutTabletStatus(
          _tablet!.handle,
          _tablet!.areas.firstOrNull ?? '',
          isWorking: false,
          isSaved: false,
        );
      } else {
        await _repository.updateLogOutUserStatus(
          _user!.phone,
          _user!.areas.firstOrNull ?? '',
          isWorking: false,
          isSaved: false,
        );
      }

      try {
        final prefs = await SharedPreferences.getInstance();
        final dateKey = _clockInCacheDateKey;
        final flagKey = _clockInCacheFlagKey;
        if (dateKey != null) {
          await prefs.remove(dateKey);
        }
        if (flagKey != null) {
          await prefs.remove(flagKey);
        }
      } catch (e, st) {
        debugPrint('clearUserToPhone clock-in 캐시 제거 실패: $e\n$st');
      }

      await _clearUserPrefsSelective(keepArea: true);
    } catch (e, st) {
      debugPrint('clearUserToPhone error: $e');
      await DevFirebaseDebugDialog.show(
        operation: _isTablet ? 'tablet.logout.updateStatus' : 'user.logout.updateStatus',
        error: e,
        stackTrace: st,
        details: <String, Object?>{
          'isTablet': _isTablet,
          'tabletId': _tablet?.id,
          'userId': _user?.id,
          'source': 'UserState.clearUserToPhone',
        },
      );
    } finally {
      try {
        PlateTtsListenerService.stop();
      } catch (_) {}

      try {
        await FirebaseGoogleAuthBridge.instance.signOutFirebaseOnly();
        debugPrint(
            '[USER-STATE][${DateTime.now().toIso8601String()}] clearUserToPhone Firebase signOut complete');
      } catch (e, st) {
        debugPrint(
            '[USER-STATE][${DateTime.now().toIso8601String()}] clearUserToPhone Firebase signOut failed: $e\n$st');
        await DevFirebaseDebugDialog.show(
          operation: 'firebaseAuth.signOutFirebaseOnly',
          error: e,
          stackTrace: st,
          details: <String, Object?>{
            'isTablet': _isTablet,
            'source': 'UserState.clearUserToPhone.finally',
          },
        );
      }

      _hasClockInToday = false;
      _hasClockInTodayForDate = null;

      _user = null;
      _tablet = null;
      _session = null;
      _isTablet = false;
      notifyListeners();
    }
  }

  Future<void> loadUsersOnly() async {
    _isLoading = true;
    _resetPrevAreaGateUsers();

    _clearSelectionSilently();
    notifyListeners();
    await _fetchUsersByAreaWithCache();
  }

  Future<void> loadTabletsOnly() async {
    _isLoading = true;
    _resetPrevAreaGateTablets();

    _clearSelectionSilently();
    notifyListeners();
    await _fetchTabletsByAreaWithCache();
  }

  Future<void> addUserCard(
    UserModel user, {
    void Function(String)? onError,
  }) async {
    try {
      await _repository.addUserCard(user.copyWith());

      final area = _areaState.currentArea.trim();
      _userList = _insertOrReplace(_userList, user);
      await _repository.updateUsersCache(area, _userList);

      notifyListeners();
    } catch (e) {
      final activeLimit = _tryParseActiveLimitError(e);
      if (activeLimit != null) {
        onError?.call('활성화 제한에 도달했습니다. (최대 $activeLimit)');
        return;
      }
      final totalLimit = _tryParseTotalLimitError(e);
      if (totalLimit != null) {
        onError?.call('전체 계정 제한에 도달했습니다. (최대 $totalLimit)');
        return;
      }
      onError?.call('사용자 추가 실패: $e');
    }
  }

  Future<void> addTabletCard(
    TabletModel tablet, {
    void Function(String)? onError,
  }) async {
    try {
      await _repository.addTabletCard(tablet.copyWith());

      final area = _areaState.currentArea.trim();
      _tabletList = _insertOrReplaceTablet(_tabletList, tablet);
      await _repository.updateTabletsCache(area, _tabletList);

      notifyListeners();
    } catch (e, st) {
      debugPrint('addTabletCard error: $e\n$st');
      onError?.call('태블릿 계정 추가 실패: $e');
    }
  }

  Future<void> deleteUserCard(
    List<String> ids, {
    void Function(String)? onError,
  }) async {
    try {
      await _repository.deleteUsers(ids);

      final area = _areaState.currentArea.trim();
      _userList =
          _userList.where((u) => !ids.contains(u.id)).toList(growable: false);
      await _repository.updateUsersCache(area, _userList);

      _clearSelectionSilently();

      notifyListeners();
    } catch (e) {
      onError?.call('사용자 삭제 실패: $e');
    }
  }

  Future<void> deleteTabletCard(
    List<String> ids, {
    void Function(String)? onError,
  }) async {
    try {
      await _repository.deleteTablets(ids);

      final area = _areaState.currentArea.trim();
      _tabletList =
          _tabletList.where((u) => !ids.contains(u.id)).toList(growable: false);
      await _repository.updateTabletsCache(area, _tabletList);

      _clearSelectionSilently();

      notifyListeners();
    } catch (e) {
      onError?.call('태블릿 삭제 실패: $e');
    }
  }

  Future<void> toggleUserCard(String id) async {
    _selectedUserId = (_selectedUserId == id) ? null : id;
    notifyListeners();
  }

  Future<void> saveCardToUserPhone(UserModel user) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('phone', user.phone);
    await prefs.setString('selectedArea', user.selectedArea ?? '');
    await prefs.setString('division', user.divisions.firstOrNull ?? '');
    await prefs.setString('role', user.role);
    await prefs.setString('position', user.position ?? '');
    await WorkSchedulePrefs.saveUserSchedule(prefs: prefs, user: user);

    try {
      final map = user.toMap();
      final json = jsonEncode(map);
      await prefs.setString(_prefsKeyCachedUser, json);
    } catch (e, st) {
      debugPrint('saveCardToUserPhone cachedUserJson 저장 실패: $e\n$st');
    }
  }

  Future<void> _saveTabletPrefs(TabletModel tablet) async {
    final prefs = await SharedPreferences.getInstance();
    final handle = tablet.handle.trim().toLowerCase();
    final areaName = (tablet.selectedArea ??
            tablet.currentArea ??
            tablet.areas.firstOrNull ??
            '')
        .trim();

    await prefs.setString('handle', handle);
    await prefs.setString('selectedArea', areaName);
    await prefs.setString(
        'englishSelectedAreaName', tablet.englishSelectedAreaName ?? areaName);
    await prefs.setString('division', tablet.divisions.firstOrNull ?? '');
    await prefs.setString('role', tablet.role);
    await prefs.setString('position', tablet.position ?? '');
  }

  Future<void> loadUserToLogInLocalOnly() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final phone = prefs.getString('phone')?.trim();
      final selectedArea = prefs.getString('selectedArea')?.trim();
      final division = prefs.getString('division')?.trim();
      final role = prefs.getString('role')?.trim();
      final startTimeStr = prefs.getString('startTime');
      final endTimeStr = prefs.getString('endTime');
      final fixedHolidays = prefs.getStringList('fixedHolidays') ?? [];
      final startTimeByWeekday = WorkSchedulePrefs.readDayTimeMapFromPrefs(
          prefs, WorkSchedulePrefs.startMapKey);
      final endTimeByWeekday = WorkSchedulePrefs.readDayTimeMapFromPrefs(
          prefs, WorkSchedulePrefs.endMapKey);
      final position = prefs.getString('position');
      final cachedJson = prefs.getString(_prefsKeyCachedUser);

      if (phone == null || selectedArea == null || cachedJson == null) {
        return;
      }

      final firebaseOk = await FirebaseGoogleAuthBridge.instance
          .ensureSignedInFromGoogleSession(interactive: false);
      debugPrint(
          '[USER-STATE][${DateTime.now().toIso8601String()}] loadUserToLogInLocalOnly firebaseOk=$firebaseOk currentUser=${FirebaseGoogleAuthBridge.instance.currentUser?.email} anonymous=${FirebaseGoogleAuthBridge.instance.currentUser?.isAnonymous}');

      final userId = "$phone-$selectedArea";
      final decoded = jsonDecode(cachedJson) as Map<String, dynamic>;
      var userData = UserModel.fromMap(userId, decoded);

      _isTablet = false;
      final trimmedArea = selectedArea.trim();

      final effectiveStartByWeekday = startTimeByWeekday.values.any((value) => value != null)
          ? startTimeByWeekday
          : userData.startTimeByWeekday;
      final effectiveEndByWeekday = endTimeByWeekday.values.any((value) => value != null)
          ? endTimeByWeekday
          : userData.endTimeByWeekday;
      final effectiveBreakDays = _normalizedBreakDaysForUser(
        user: userData,
        prefs: prefs,
        startByWeekday: effectiveStartByWeekday,
        endByWeekday: effectiveEndByWeekday,
      );

      userData = userData.copyWith(
        currentArea: trimmedArea,
        role: role ?? userData.role,
        position: position ?? userData.position,
        startTime: _stringToTimeOfDay(startTimeStr) ?? userData.startTime,
        endTime: _stringToTimeOfDay(endTimeStr) ?? userData.endTime,
        fixedHolidays:
            fixedHolidays.isNotEmpty ? fixedHolidays : userData.fixedHolidays,
        breakDays: effectiveBreakDays,
        startTimeByWeekday: effectiveStartByWeekday,
        endTimeByWeekday: effectiveEndByWeekday,
        divisions: division != null ? [division] : userData.divisions,
        isSaved: true,
      );

      _hasClockInToday = false;
      _hasClockInTodayForDate = null;

      _user = userData;
      _tablet = null;
      _session = UserSessionAccount(userData);
      notifyListeners();

      _areaState.setAreaLocalOnly(trimmedArea, division: division);

      await _startTtsForArea(trimmedArea);
    } catch (e, st) {
      debugPrint("loadUserToLogInLocalOnly, 오류: $e\n$st");
    }
  }

  Future<void> loadUserToLogIn() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final phone = prefs.getString('phone')?.trim();
      final selectedArea = prefs.getString('selectedArea')?.trim();
      final division = prefs.getString('division')?.trim();
      final role = prefs.getString('role')?.trim();
      final startTimeStr = prefs.getString('startTime');
      final endTimeStr = prefs.getString('endTime');
      final fixedHolidays = prefs.getStringList('fixedHolidays') ?? [];
      final startTimeByWeekday = WorkSchedulePrefs.readDayTimeMapFromPrefs(
          prefs, WorkSchedulePrefs.startMapKey);
      final endTimeByWeekday = WorkSchedulePrefs.readDayTimeMapFromPrefs(
          prefs, WorkSchedulePrefs.endMapKey);
      final position = prefs.getString('position');

      if (phone == null || selectedArea == null) return;

      final firebaseOk = await FirebaseGoogleAuthBridge.instance
          .ensureSignedInFromGoogleSession(interactive: false);
      debugPrint(
          '[USER-STATE][${DateTime.now().toIso8601String()}] loadUserToLogIn firebaseOk=$firebaseOk currentUser=${FirebaseGoogleAuthBridge.instance.currentUser?.email} anonymous=${FirebaseGoogleAuthBridge.instance.currentUser?.isAnonymous}');

      final userId = "$phone-$selectedArea";
      var userData = await _repository.getUserById(userId);
      if (userData == null) return;

      _isTablet = false;
      final trimmedArea = selectedArea.trim();

      await _repository.updateLoadCurrentArea(phone, trimmedArea, trimmedArea);

      final effectiveStartByWeekday = startTimeByWeekday.values.any((value) => value != null)
          ? startTimeByWeekday
          : userData.startTimeByWeekday;
      final effectiveEndByWeekday = endTimeByWeekday.values.any((value) => value != null)
          ? endTimeByWeekday
          : userData.endTimeByWeekday;
      final effectiveBreakDays = _normalizedBreakDaysForUser(
        user: userData,
        prefs: prefs,
        startByWeekday: effectiveStartByWeekday,
        endByWeekday: effectiveEndByWeekday,
      );

      userData = userData.copyWith(
        currentArea: trimmedArea,
        role: role ?? userData.role,
        position: position ?? userData.position,
        startTime: _stringToTimeOfDay(startTimeStr) ?? userData.startTime,
        endTime: _stringToTimeOfDay(endTimeStr) ?? userData.endTime,
        fixedHolidays:
            fixedHolidays.isNotEmpty ? fixedHolidays : userData.fixedHolidays,
        breakDays: effectiveBreakDays,
        startTimeByWeekday: effectiveStartByWeekday,
        endTimeByWeekday: effectiveEndByWeekday,
        divisions: division != null ? [division] : userData.divisions,
        isSaved: true,
      );

      _hasClockInToday = false;
      _hasClockInTodayForDate = null;

      _user = userData;
      _tablet = null;
      _session = UserSessionAccount(userData);
      notifyListeners();

      await _areaState.initializeArea(trimmedArea);

      await _startTtsForArea(trimmedArea);
    } catch (e) {
      debugPrint("loadUserToLogIn, 오류: $e");
    }
  }

  Future<void> loadTabletToLogIn() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final handle = prefs.getString('handle')?.trim().toLowerCase();
      final selectedArea = prefs.getString('selectedArea')?.trim();
      final division = prefs.getString('division')?.trim();
      final role = prefs.getString('role')?.trim();
      final position = prefs.getString('position');
      final englishSelectedAreaName =
          prefs.getString('englishSelectedAreaName')?.trim();

      if (handle == null || selectedArea == null) return;

      final firebaseOk = await FirebaseGoogleAuthBridge.instance
          .ensureSignedInFromGoogleSession(interactive: false);
      debugPrint(
          '[USER-STATE][${DateTime.now().toIso8601String()}] loadTabletToLogIn firebaseOk=$firebaseOk currentUser=${FirebaseGoogleAuthBridge.instance.currentUser?.email} anonymous=${FirebaseGoogleAuthBridge.instance.currentUser?.isAnonymous}');

      final tablet =
          await _repository.getTabletByHandleAndAreaName(handle, selectedArea);
      if (tablet == null) return;

      _isTablet = true;

      final tabletData = tablet.copyWith(
        currentArea: selectedArea,
        selectedArea: selectedArea,
        role: role ?? tablet.role,
        position: position ?? tablet.position,
        divisions: division != null ? <String>[division] : tablet.divisions,
        englishSelectedAreaName: (englishSelectedAreaName?.isNotEmpty ?? false)
            ? englishSelectedAreaName
            : tablet.englishSelectedAreaName,
        isSaved: true,
      );

      _hasClockInToday = false;
      _hasClockInTodayForDate = null;

      _user = null;
      _tablet = tabletData;
      _session = TabletSessionAccount(tabletData);
      notifyListeners();

      await _repository.updateLoadCurrentAreaTablet(
        handle,
        tabletData.areas.firstOrNull ?? '',
        selectedArea,
      );
      await _areaState.initializeArea(selectedArea);

      await _startTtsForArea(selectedArea);
    } catch (e, st) {
      debugPrint('loadTabletToLogIn, 오류: $e');
      await DevFirebaseDebugDialog.show(
        operation: 'tablet.autoLogin.loadTabletToLogIn',
        error: e,
        stackTrace: st,
        details: <String, Object?>{
          'source': 'UserState.loadTabletToLogIn',
        },
      );
    }
  }

  Future<void> areaPickerCurrentArea(String newArea) async {
    if (_isTablet) {
      if (_tablet == null) return;
      _tablet = _tablet!.copyWith(currentArea: newArea, selectedArea: newArea);
      _session = TabletSessionAccount(_tablet!);
      notifyListeners();

      try {
        await _repository.areaPickerCurrentAreaTablet(
          _tablet!.handle.trim(),
          _tablet!.areas.firstOrNull ?? '',
          newArea.trim(),
        );
      } catch (e) {
        debugPrint("areaPickerCurrentArea 실패: $e");
      }

      await _areaState.updateArea(newArea, isSyncing: true);
      await _startTtsForArea(newArea);
      return;
    }

    if (_user == null) return;

    _user = _user!.copyWith(currentArea: newArea);
    _session = UserSessionAccount(_user!);
    notifyListeners();

    try {
      await _repository.areaPickerCurrentArea(
        _user!.phone.trim(),
        _user!.areas.firstOrNull ?? '',
        newArea.trim(),
      );
    } catch (e) {
      debugPrint("areaPickerCurrentArea 실패: $e");
    }

    await _areaState.updateArea(newArea, isSyncing: true);

    await _startTtsForArea(newArea);
  }

  Future<void> _fetchUsersByAreaWithCache({bool force = false}) async {
    final selectedArea = _areaState.currentArea.trim();
    if (selectedArea.isEmpty) return;
    if (!force && _prevAreaUsers == selectedArea) return;

    _prevAreaUsers = selectedArea;

    _clearSelectionSilently();

    _isLoading = true;
    notifyListeners();

    try {
      final data = await _repository.getUsersByAreaOnceWithCache(selectedArea);
      _userList = List<UserModel>.of(data, growable: false);
      _clearSelectionSilently();
    } catch (e) {
      _clearSelectionSilently();
      debugPrint('_fetchUsersByAreaWithCache 실패: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> _fetchTabletsByAreaWithCache({bool force = false}) async {
    final selectedArea = _areaState.currentArea.trim();
    if (selectedArea.isEmpty) return;
    if (!force && _prevAreaTablets == selectedArea) return;

    _prevAreaTablets = selectedArea;

    _clearSelectionSilently();

    _isLoading = true;
    notifyListeners();

    try {
      final data =
          await _repository.getTabletsByAreaOnceWithCache(selectedArea);
      _tabletList = List<TabletModel>.of(data, growable: false);
      _clearSelectionSilently();
    } catch (e) {
      _clearSelectionSilently();
      debugPrint('_fetchTabletsByAreaWithCache 실패: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void _resetPrevAreaGateUsers() => _prevAreaUsers = '';

  void _resetPrevAreaGateTablets() => _prevAreaTablets = '';

  List<UserModel> _replaceItem(List<UserModel> list, UserModel item) {
    final idx = list.indexWhere((e) => e.id == item.id);
    if (idx < 0) {
      final copied = List<UserModel>.of(list);
      copied.add(item);
      return copied;
    }
    final copied = List<UserModel>.of(list);
    copied[idx] = item;
    return copied;
  }

  List<UserModel> _insertOrReplace(List<UserModel> list, UserModel item) {
    final idx = list.indexWhere((e) => e.id == item.id);
    final copied = List<UserModel>.of(list);
    if (idx < 0) {
      copied.add(item);
    } else {
      copied[idx] = item;
    }
    return copied;
  }

  List<TabletModel> _replaceTabletItem(
      List<TabletModel> list, TabletModel item) {
    final idx = list.indexWhere((e) => e.id == item.id);
    if (idx < 0) {
      final copied = List<TabletModel>.of(list);
      copied.add(item);
      return copied;
    }
    final copied = List<TabletModel>.of(list);
    copied[idx] = item;
    return copied;
  }

  List<TabletModel> _insertOrReplaceTablet(
      List<TabletModel> list, TabletModel item) {
    final idx = list.indexWhere((e) => e.id == item.id);
    final copied = List<TabletModel>.of(list);
    if (idx < 0) {
      copied.add(item);
    } else {
      copied[idx] = item;
    }
    return copied;
  }

  TimeOfDay? _stringToTimeOfDay(String? timeString) {
    if (timeString == null || !timeString.contains(':')) return null;
    final parts = timeString.split(':');
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null || minute == null) return null;
    return TimeOfDay(hour: hour, minute: minute);
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _areaState.removeListener(_fetchUsersByAreaWithCache);
    super.dispose();
  }

  Future<void> _clearUserPrefsSelective({bool keepArea = true}) async {
    final prefs = await SharedPreferences.getInstance();

    for (final k in _userSensitiveKeys) {
      await prefs.remove(k);
    }

    if (!keepArea) {
      await prefs.remove('selectedArea');
      await prefs.remove('englishSelectedAreaName');
    }
  }
}
