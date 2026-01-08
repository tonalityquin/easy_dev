import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:intl/intl.dart';

import '../../models/tablet_model.dart';
import '../../repositories/user_repo_services/user_repository.dart';
import '../../models/user_model.dart';
import '../../utils/tts/plate_tts_listener_service.dart';
import '../area/area_state.dart';
import '../../services/latest_message_service.dart';
import '../../repositories/commute_repo_services/commute_log_repository.dart';

class UserState extends ChangeNotifier {
  final UserRepository _repository;
  final AreaState _areaState;

  UserModel? _user;

  // ── 분리: 사람/태블릿 전용 리스트 (항상 "복사본"을 보관)
  List<UserModel> _userList = const [];
  List<UserModel> _tabletList = const [];

  String? _selectedUserId;
  bool _isLoading = true;

  // 현재 세션 모드(사람/태블릿)
  bool _isTablet = false;

  // 🔹 오늘 날짜 기준 출근 여부 캐시 (메모리)
  bool _hasClockInToday = false;
  String? _hasClockInTodayForDate; // 'yyyy-MM-dd'

  StreamSubscription<List<UserModel>>? _subscription;

  // ── 게이트를 분리 (사람/태블릿 각각)
  String _prevAreaUsers = '';
  String _prevAreaTablets = '';

  // ===== [추가] SharedPreferences 선택 삭제/유지 정책 =====
  // 사용자(세션/신원) 관련 키만 삭제합니다.
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
    _prefsKeyCachedUser,
  };

  UserModel? get user => _user;

  /// 사람 계정 리스트(외부에 변경 불가)
  UnmodifiableListView<UserModel> get users => UnmodifiableListView(_userList);

  /// 태블릿 계정 리스트(외부에 변경 불가)
  UnmodifiableListView<UserModel> get tabletUsers => UnmodifiableListView(_tabletList);

  /// 과거 코드 호환용
  UnmodifiableListView<UserModel> get tablets => tabletUsers;

  String? get selectedUserId => _selectedUserId;
  bool get isLoggedIn => _user != null;
  bool get isWorking => _user?.isWorking ?? false;
  bool get isLoading => _isLoading;
  bool get isTablet => _isTablet;

  // 🔹 오늘 출근 여부 외부 노출용 getter
  bool get hasClockInToday => _hasClockInToday;

  String get role => _user?.role ?? '';
  String get position => _user?.position ?? '';
  String get name => _user?.name ?? '';
  String get phone => _user?.phone ?? '';
  String get password => _user?.password ?? '';

  String get area => _user?.areas.firstOrNull ?? '';
  String get division => _user?.divisions.firstOrNull ?? '';
  String get currentArea => _user?.currentArea ?? area;

  // 🔹 유저별 오늘 출근 여부 SharedPreferences 캐시 키
  String? get _clockInCacheDateKey => _user == null ? null : 'clockInDate';
  String? get _clockInCacheFlagKey => _user == null ? null : 'clockInHas';

  UserState(this._repository, this._areaState) {
    _areaState.addListener(_fetchUsersByAreaWithCache);
  }

  // ========== 목록 갱신(사람) ==========

  /// ✅ 새로고침(사람): show 컬렉션 기반 1회 get으로 갱신
  /// - division이 비어있으면 기존 user_accounts 쿼리로 fallback
  Future<void> refreshUsersBySelectedAreaAndCache() async {
    final selectedArea = _areaState.currentArea.trim();
    final currentDivision = _areaState.currentDivision.trim();

    _isLoading = true;
    notifyListeners();

    try {
      final data = currentDivision.isNotEmpty
          ? await _repository.refreshUsersByDivisionAreaFromShow(currentDivision, selectedArea)
          : await _repository.refreshUsersBySelectedArea(selectedArea);

      _userList = List<UserModel>.of(data, growable: false);
      _selectedUserId = null;
      _prevAreaUsers = selectedArea;
    } catch (e) {
      debugPrint('🔥 Error refreshing users: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // ========== 목록 갱신(태블릿) ==========

  Future<void> refreshTabletsBySelectedAreaAndCache() async {
    final selectedArea = _areaState.currentArea.trim();
    _isLoading = true;
    notifyListeners();

    try {
      final data = await _repository.refreshTabletsBySelectedArea(selectedArea);
      _tabletList = List<UserModel>.of(data, growable: false);
      _selectedUserId = null;
      _prevAreaTablets = selectedArea;
    } catch (e) {
      debugPrint('🔥 Error refreshing tablets: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // ========== 상태 토글 ==========

  Future<void> isHeWorking() async {
    if (_user == null) return;
    final newStatus = !_user!.isWorking;

    if (_isTablet) {
      await _repository.updateWorkingTabletStatus(
        _user!.phone,
        _user!.areas.firstOrNull ?? '',
        isWorking: newStatus,
      );
    } else {
      await _repository.updateWorkingUserStatus(
        _user!.phone,
        _user!.areas.firstOrNull ?? '',
        isWorking: newStatus,
      );
    }
    _user = _user!.copyWith(isWorking: newStatus);
    notifyListeners();
  }

  String? _tryParseActiveLimitError(Object e) {
    final s = e.toString();
    const key = 'ACTIVE_LIMIT_REACHED:';
    final idx = s.indexOf(key);
    if (idx < 0) return null;
    return s.substring(idx + key.length).trim();
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
      final limit = _tryParseActiveLimitError(e);
      if (limit != null && isActive) {
        onError?.call('활성화 제한에 도달했습니다. (최대 $limit)');
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

  Future<void> updateLoginUser(UserModel updatedUser) async {
    _isTablet = false;
    _user = updatedUser;
    notifyListeners();

    await _repository.updateUser(updatedUser);

    final area = _areaState.currentArea.trim();
    _userList = _replaceItem(_userList, updatedUser);
    await _repository.updateUsersCache(area, _userList);

    await saveCardToUserPhone(updatedUser);
  }

  Future<void> updateLoginUserLocalOnly(UserModel updatedUser) async {
    _isTablet = false;
    _user = updatedUser;

    _hasClockInToday = false;
    _hasClockInTodayForDate = null;

    notifyListeners();

    await saveCardToUserPhone(updatedUser);
  }

  Future<void> updateLoginTablet(UserModel updatedUserAsTablet) async {
    _isTablet = true;
    _user = updatedUserAsTablet;
    notifyListeners();

    final handle = updatedUserAsTablet.phone.trim().toLowerCase();
    final areaName = (updatedUserAsTablet.selectedArea ??
        updatedUserAsTablet.currentArea ??
        updatedUserAsTablet.areas.firstOrNull ??
        '')
        .trim();

    final tablet = TabletModel(
      id: '$handle-$areaName',
      areas: List<String>.from(updatedUserAsTablet.areas),
      currentArea: updatedUserAsTablet.currentArea,
      divisions: List<String>.from(updatedUserAsTablet.divisions),
      email: updatedUserAsTablet.email,
      endTime: updatedUserAsTablet.endTime,
      englishSelectedAreaName: updatedUserAsTablet.englishSelectedAreaName,
      fixedHolidays: List<String>.from(updatedUserAsTablet.fixedHolidays),
      isSaved: updatedUserAsTablet.isSaved,
      isSelected: updatedUserAsTablet.isSelected,
      isWorking: updatedUserAsTablet.isWorking,
      name: updatedUserAsTablet.name,
      password: updatedUserAsTablet.password,
      handle: handle,
      position: updatedUserAsTablet.position,
      role: updatedUserAsTablet.role,
      selectedArea: updatedUserAsTablet.selectedArea,
      startTime: updatedUserAsTablet.startTime,
    );

    await _repository.updateTablet(tablet);

    final area = _areaState.currentArea.trim();
    final mappedAsUser = _mapTabletToUser(tablet, currentAreaOverride: area);
    _tabletList = _replaceItem(_tabletList, mappedAsUser);
    await _repository.updateTabletsCache(area, _tabletList);

    await _saveTabletPrefsFromUser(updatedUserAsTablet);
  }

  Future<void> clearUserToPhone() async {
    if (_user == null) return;

    try {
      if (_isTablet) {
        await _repository.updateLogOutTabletStatus(
          _user!.phone,
          _user!.areas.firstOrNull ?? '',
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
    } catch (e) {
      debugPrint('clearUserToPhone error: $e');
    } finally {
      try {
        PlateTtsListenerService.stop();
      } catch (_) {}

      // ✅ ChatTtsListenerService.stop() 제거

      try {
        await LatestMessageService.instance.stop();
      } catch (_) {}

      _hasClockInToday = false;
      _hasClockInTodayForDate = null;

      _user = null;
      _isTablet = false;
      notifyListeners();
    }
  }

  // ========== 초기 로드 ==========

  Future<void> loadUsersOnly() async {
    _isLoading = true;
    _resetPrevAreaGateUsers();
    notifyListeners();
    await _fetchUsersByAreaWithCache();
  }

  Future<void> loadTabletsOnly() async {
    _isLoading = true;
    _resetPrevAreaGateTablets();
    notifyListeners();
    await _fetchTabletsByAreaWithCache();
  }

  // ========== CRUD 래퍼 ==========

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
      final asUser = _mapTabletToUser(tablet, currentAreaOverride: area);
      _tabletList = _insertOrReplace(_tabletList, asUser);
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
      _userList = _userList.where((u) => !ids.contains(u.id)).toList(growable: false);
      await _repository.updateUsersCache(area, _userList);

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
      _tabletList = _tabletList.where((u) => !ids.contains(u.id)).toList(growable: false);
      await _repository.updateTabletsCache(area, _tabletList);

      notifyListeners();
    } catch (e) {
      onError?.call('태블릿 삭제 실패: $e');
    }
  }

  Future<void> toggleUserCard(String id) async {
    _selectedUserId = (_selectedUserId == id) ? null : id;
    notifyListeners();
  }

  // ========== Prefs 저장 ==========

  Future<void> saveCardToUserPhone(UserModel user) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('phone', user.phone);
    await prefs.setString('selectedArea', user.selectedArea ?? '');
    await prefs.setString('division', user.divisions.firstOrNull ?? '');
    await prefs.setString('role', user.role);
    await prefs.setString('startTime', _timeToString(user.startTime) ?? '');
    await prefs.setString('endTime', _timeToString(user.endTime) ?? '');
    await prefs.setStringList('fixedHolidays', user.fixedHolidays);
    await prefs.setString('position', user.position ?? '');

    try {
      final map = user.toMap();
      final json = jsonEncode(map);
      await prefs.setString(_prefsKeyCachedUser, json);
    } catch (e, st) {
      debugPrint('saveCardToUserPhone cachedUserJson 저장 실패: $e\n$st');
    }
  }

  Future<void> _saveTabletPrefsFromUser(UserModel asUser) async {
    final prefs = await SharedPreferences.getInstance();
    final handle = asUser.phone.trim().toLowerCase();
    final areaName = (asUser.selectedArea ?? asUser.currentArea ?? asUser.areas.firstOrNull ?? '').trim();

    await prefs.setString('handle', handle);
    await prefs.setString('selectedArea', areaName);
    await prefs.setString('englishSelectedAreaName', asUser.englishSelectedAreaName ?? areaName);
    await prefs.setString('division', asUser.divisions.firstOrNull ?? '');
    await prefs.setString('role', asUser.role);
    await prefs.setString('startTime', _timeToString(asUser.startTime) ?? '');
    await prefs.setString('endTime', _timeToString(asUser.endTime) ?? '');
    await prefs.setStringList('fixedHolidays', asUser.fixedHolidays);
    await prefs.setString('position', asUser.position ?? '');
  }

  // ========== 자동 로그인 ==========

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
      final position = prefs.getString('position');
      final cachedJson = prefs.getString(_prefsKeyCachedUser);

      if (phone == null || selectedArea == null || cachedJson == null) {
        return;
      }

      final userId = "$phone-$selectedArea";
      final decoded = jsonDecode(cachedJson) as Map<String, dynamic>;
      var userData = UserModel.fromMap(userId, decoded);

      _isTablet = false;
      final trimmedArea = selectedArea.trim();

      userData = userData.copyWith(
        currentArea: trimmedArea,
        role: role ?? userData.role,
        position: position ?? userData.position,
        startTime: _stringToTimeOfDay(startTimeStr),
        endTime: _stringToTimeOfDay(endTimeStr),
        fixedHolidays: fixedHolidays.isNotEmpty ? fixedHolidays : userData.fixedHolidays,
        divisions: division != null ? [division] : userData.divisions,
        isSaved: true,
      );

      _hasClockInToday = false;
      _hasClockInTodayForDate = null;

      _user = userData;
      notifyListeners();

      _areaState.setAreaLocalOnly(trimmedArea, division: division);

      PlateTtsListenerService.start(trimmedArea);

      // ✅ ChatTtsListenerService.start 제거
      // ✅ 대신 LatestMessageService를 명시적으로 시작(채팅 최신 캐시/구독 유지 목적)
      LatestMessageService.instance.start(trimmedArea);
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
      final position = prefs.getString('position');

      if (phone == null || selectedArea == null) return;

      final userId = "$phone-$selectedArea";
      var userData = await _repository.getUserById(userId);
      if (userData == null) return;

      _isTablet = false;
      final trimmedArea = selectedArea.trim();

      await _repository.updateLoadCurrentArea(phone, trimmedArea, trimmedArea);

      userData = userData.copyWith(
        currentArea: trimmedArea,
        role: role ?? userData.role,
        position: position ?? userData.position,
        startTime: _stringToTimeOfDay(startTimeStr),
        endTime: _stringToTimeOfDay(endTimeStr),
        fixedHolidays: fixedHolidays,
        divisions: division != null ? [division] : userData.divisions,
        isSaved: true,
      );

      _hasClockInToday = false;
      _hasClockInTodayForDate = null;

      _user = userData;
      notifyListeners();

      await _areaState.initializeArea(trimmedArea);

      PlateTtsListenerService.start(trimmedArea);

      // ✅ ChatTtsListenerService.start 제거
      LatestMessageService.instance.start(trimmedArea);
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
      final startTimeStr = prefs.getString('startTime');
      final endTimeStr = prefs.getString('endTime');
      final fixedHolidays = prefs.getStringList('fixedHolidays') ?? [];
      final position = prefs.getString('position');

      if (handle == null || selectedArea == null) return;

      final tablet = await _repository.getTabletByHandleAndAreaName(handle, selectedArea);
      if (tablet == null) return;

      _isTablet = true;

      var userData = _mapTabletToUser(tablet, currentAreaOverride: selectedArea);
      userData = userData.copyWith(
        role: role ?? userData.role,
        position: position ?? userData.position,
        startTime: _stringToTimeOfDay(startTimeStr),
        endTime: _stringToTimeOfDay(endTimeStr),
        fixedHolidays: fixedHolidays.isNotEmpty ? fixedHolidays : userData.fixedHolidays,
        divisions: division != null ? [division] : userData.divisions,
        isSaved: true,
      );

      _hasClockInToday = false;
      _hasClockInTodayForDate = null;

      _user = userData;
      notifyListeners();

      await _repository.updateLoadCurrentAreaTablet(
        handle,
        userData.areas.firstOrNull ?? '',
        selectedArea,
      );
      await _areaState.initializeArea(selectedArea);

      PlateTtsListenerService.start(selectedArea);

      // ✅ ChatTtsListenerService.start 제거
      LatestMessageService.instance.start(selectedArea);
    } catch (e) {
      debugPrint("loadTabletToLogIn, 오류: $e");
    }
  }

  Future<void> areaPickerCurrentArea(String newArea) async {
    if (_user == null) return;

    _user = _user!.copyWith(currentArea: newArea);
    notifyListeners();

    try {
      if (_isTablet) {
        await _repository.areaPickerCurrentAreaTablet(
          _user!.phone.trim(),
          _user!.areas.firstOrNull ?? '',
          newArea.trim(),
        );
      } else {
        await _repository.areaPickerCurrentArea(
          _user!.phone.trim(),
          _user!.areas.firstOrNull ?? '',
          newArea.trim(),
        );
      }
    } catch (e) {
      debugPrint("areaPickerCurrentArea 실패: $e");
    }

    await _areaState.updateArea(newArea, isSyncing: true);

    PlateTtsListenerService.start(newArea);

    // ✅ ChatTtsListenerService.start 제거
    LatestMessageService.instance.start(newArea);
  }

  // ========== 내부 로드 ==========

  Future<void> _fetchUsersByAreaWithCache({bool force = false}) async {
    final selectedArea = _areaState.currentArea.trim();
    if (selectedArea.isEmpty) return;
    if (!force && _prevAreaUsers == selectedArea) return;

    _prevAreaUsers = selectedArea;
    _isLoading = true;
    notifyListeners();

    try {
      final data = await _repository.getUsersByAreaOnceWithCache(selectedArea);
      _userList = List<UserModel>.of(data, growable: false);
      _selectedUserId = null;
    } catch (e) {
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
    _isLoading = true;
    notifyListeners();

    try {
      final data = await _repository.getTabletsByAreaOnceWithCache(selectedArea);
      _tabletList = List<UserModel>.of(data, growable: false);
      _selectedUserId = null;
    } catch (e) {
      debugPrint('_fetchTabletsByAreaWithCache 실패: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // ========== 유틸 ==========

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

  UserModel _mapTabletToUser(
      TabletModel t, {
        String? currentAreaOverride,
      }) {
    return UserModel(
      id: t.id,
      areas: List<String>.from(t.areas),
      currentArea: currentAreaOverride ?? t.currentArea,
      divisions: List<String>.from(t.divisions),
      email: t.email,
      endTime: t.endTime,
      englishSelectedAreaName: t.englishSelectedAreaName,
      fixedHolidays: List<String>.from(t.fixedHolidays),
      isSaved: t.isSaved,
      isSelected: t.isSelected,
      isWorking: t.isWorking,
      name: t.name,
      password: t.password,
      phone: t.handle,
      position: t.position,
      role: t.role,
      selectedArea: currentAreaOverride ?? t.selectedArea,
      startTime: t.startTime,
      isActive: true,
    );
  }

  String? _timeToString(TimeOfDay? time) {
    if (time == null) return null;
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
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
