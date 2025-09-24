// lib/states/user/user_state.dart
import 'dart:async';
import 'dart:collection';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/tablet_model.dart';
import '../../repositories/user_repo_services/user_repository.dart';
import '../../models/user_model.dart';
import '../../utils/tts/plate_tts_listener_service.dart';
import '../../utils/tts/chat_tts_listener_service.dart';
import '../area/area_state.dart';

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

  StreamSubscription<List<UserModel>>? _subscription;

  // ── 게이트를 분리 (사람/태블릿 각각)
  String _prevAreaUsers = '';
  String _prevAreaTablets = '';

  // ===== [추가] SharedPreferences 선택 삭제/유지 정책 =====
  // 사용자(세션/신원) 관련 키만 삭제합니다.
  static const Set<String> _userSensitiveKeys = <String>{
    'phone',
    'handle',
    'role',
    'division',
    'position',
    'startTime',
    'endTime',
    'fixedHolidays',
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

  String get role => _user?.role ?? '';
  String get position => _user?.position ?? '';
  String get name => _user?.name ?? '';
  String get phone => _user?.phone ?? '';
  String get password => _user?.password ?? '';

  String get area => _user?.areas.firstOrNull ?? '';
  String get division => _user?.divisions.firstOrNull ?? '';
  String get currentArea => _user?.currentArea ?? area;

  UserState(this._repository, this._areaState) {
    _areaState.addListener(_fetchUsersByAreaWithCache);
  }

  // ========== 목록 갱신(사람) ==========
  Future<void> refreshUsersBySelectedAreaAndCache() async {
    final selectedArea = _areaState.currentArea.trim();
    _isLoading = true;
    notifyListeners();

    try {
      final data = await _repository.refreshUsersBySelectedArea(selectedArea);
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

  Future<void> updateLoginUser(UserModel updatedUser) async {
    _isTablet = false;
    _user = updatedUser;
    notifyListeners();

    await _repository.updateUser(updatedUser);

    // 로컬 리스트 교체 및 캐시 갱신(네트워크 호출 없음)
    final area = _areaState.currentArea.trim();
    _userList = _replaceItem(_userList, updatedUser);
    await _repository.updateUsersCache(area, _userList);

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

    // 로컬 리스트 교체 및 캐시 갱신(네트워크 호출 없음)
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

      // ===== [변경] 전체 삭제 금지 → 선택 삭제로 변경 =====
      await _clearUserPrefsSelective(keepArea: true);
    } catch (e) {
      debugPrint('clearUserToPhone error: $e');
    } finally {
      // TTS는 예외와 무관하게 정리
      try {
        PlateTtsListenerService.stop();
      } catch (_) {}
      try {
        ChatTtsListenerService.stop();
      } catch (_) {}

      _user = null;
      _isTablet = false;
      notifyListeners();
    }
  }

  // ========== 초기 로드 ==========
  Future<void> loadUsersOnly() async {
    _isLoading = true;
    _resetPrevAreaGateUsers(); // ✅ 사람 게이트만 초기화
    notifyListeners();
    await _fetchUsersByAreaWithCache();
  }

  Future<void> loadTabletsOnly() async {
    _isLoading = true;
    _resetPrevAreaGateTablets(); // ✅ 태블릿 게이트만 초기화
    notifyListeners();
    await _fetchTabletsByAreaWithCache();
  }

  // ========== CRUD 래퍼 ==========
  Future<void> addUserCard(UserModel user, {void Function(String)? onError}) async {
    try {
      await _repository.addUserCard(user.copyWith());

      // 로컬 반영 + 캐시 갱신
      final area = _areaState.currentArea.trim();
      _userList = _insertOrReplace(_userList, user);
      await _repository.updateUsersCache(area, _userList);

      notifyListeners();
    } catch (e) {
      onError?.call('사용자 추가 실패: $e');
    }
  }

  Future<void> addTabletCard(TabletModel tablet, {void Function(String)? onError}) async {
    try {
      await _repository.addTabletCard(tablet.copyWith());

      // TabletModel → UserModel로 변환 후 로컬 반영 + 캐시 갱신
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

  Future<void> deleteUserCard(List<String> ids, {void Function(String)? onError}) async {
    try {
      await _repository.deleteUsers(ids);

      // 로컬 반영 + 캐시 갱신
      final area = _areaState.currentArea.trim();
      _userList = _userList.where((u) => !ids.contains(u.id)).toList(growable: false);
      await _repository.updateUsersCache(area, _userList);

      notifyListeners();
    } catch (e) {
      onError?.call('사용자 삭제 실패: $e');
    }
  }

  Future<void> deleteTabletCard(List<String> ids, {void Function(String)? onError}) async {
    try {
      await _repository.deleteTablets(ids);

      // 로컬 반영 + 캐시 갱신
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
  }

  Future<void> _saveTabletPrefsFromUser(UserModel asUser) async {
    final prefs = await SharedPreferences.getInstance();
    final handle = asUser.phone.trim().toLowerCase();
    final areaName =
    (asUser.selectedArea ?? asUser.currentArea ?? asUser.areas.firstOrNull ?? '').trim();

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

      _user = userData;
      notifyListeners();

      await _areaState.initializeArea(trimmedArea);

      // ✅ PlateTTS도 ChatTTS와 동일한 시작 지점에서 무조건 시작
      PlateTtsListenerService.start(trimmedArea);
      ChatTtsListenerService.start(trimmedArea);
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

      final tablet =
      await _repository.getTabletByHandleAndAreaName(handle, selectedArea);
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

      _user = userData;
      notifyListeners();

      await _repository.updateLoadCurrentAreaTablet(
          handle, userData.areas.firstOrNull ?? '', selectedArea);
      await _areaState.initializeArea(selectedArea);

      // ✅ PlateTTS도 ChatTTS와 동일한 시작 지점에서 무조건 시작
      PlateTtsListenerService.start(selectedArea);
      ChatTtsListenerService.start(selectedArea);
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

    // ✅ 지역 변경 시에도 Plate/Chat TTS 모두 동일 타이밍으로 시작
    PlateTtsListenerService.start(newArea);
    ChatTtsListenerService.start(newArea);
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
      final data =
      await _repository.getTabletsByAreaOnceWithCache(selectedArea);
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

  UserModel _mapTabletToUser(TabletModel t, {String? currentAreaOverride}) {
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

  // ===== [추가] 선택 삭제 유틸 =====
  Future<void> _clearUserPrefsSelective({bool keepArea = true}) async {
    final prefs = await SharedPreferences.getInstance();

    // 1) 사용자 민감 키들만 제거
    for (final k in _userSensitiveKeys) {
      await prefs.remove(k);
    }

    // 2) 영역/디바이스 키 보존
    if (!keepArea) {
      // 필요 시 영역 키까지 지우고 싶을 때 호출
      await prefs.remove('selectedArea');
      await prefs.remove('englishSelectedAreaName');
    }

    // 3) 캐시 계열 접두사는 그대로 둡니다(users_ / tablets_ / cached_)
    //    → 여기선 아무 것도 하지 않음(보존).
  }
}
