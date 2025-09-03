import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/tablet_model.dart';
import '../../repositories/user/user_repository.dart';
import '../../models/user_model.dart';
import '../../utils/plate_tts_listener_service.dart';
import '../../utils/chat_tts_listener_service.dart';
import '../area/area_state.dart';

class UserState extends ChangeNotifier {
  final UserRepository _repository;
  final AreaState _areaState;

  UserModel? _user;
  List<UserModel> _users = [];
  String? _selectedUserId;
  bool _isLoading = true;

  // ✅ 현재 세션이 태블릿 계정 기반인지 여부
  bool _isTablet = false;

  StreamSubscription<List<UserModel>>? _subscription;
  String _previousSelectedArea = '';

  UserModel? get user => _user;
  List<UserModel> get users => _users;
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

  // ==========================
  // ===== 목록 갱신 (유저) =====
  // ==========================
  Future<void> refreshUsersBySelectedAreaAndCache() async {
    final selectedArea = _areaState.currentArea.trim();
    _isLoading = true;
    notifyListeners();

    try {
      final data = await _repository.refreshUsersBySelectedArea(selectedArea);
      _users = data;
      _selectedUserId = null;
    } catch (e) {
      debugPrint('🔥 Error refreshing users: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // ============================
  // ===== 목록 갱신 (태블릿) =====
  // ============================
  Future<void> refreshTabletsBySelectedAreaAndCache() async {
    final selectedArea = _areaState.currentArea.trim();
    _isLoading = true;
    notifyListeners();

    try {
      // tablet_accounts 기반 조회 (UserModel로 매핑되어 반환)
      final data = await _repository.refreshTabletsBySelectedArea(selectedArea);
      _users = data;
      _selectedUserId = null;
    } catch (e) {
      debugPrint('🔥 Error refreshing tablets: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // =======================
  // ===== 상태 토글 등 =====
  // =======================
  Future<void> isHeWorking() async {
    if (_user == null) return;

    final newStatus = !_user!.isWorking;

    // ✅ 분기: user_accounts vs tablet_accounts
    if (_isTablet) {
      await _repository.updateWorkingTabletStatus(
        _user!.phone, // tablet 모드에서는 phone 슬롯 = handle
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
    _isTablet = false; // ✅ 서비스(사람) 계정
    _user = updatedUser;
    notifyListeners();
    await _repository.updateUser(updatedUser);
    await saveCardToUserPhone(updatedUser);
    await _fetchUsersByAreaWithCache();
  }

  /// ✅ 태블릿 계정용 업데이트(UserModel로 들어오지만 tablet_accounts로 저장)
  Future<void> updateLoginTablet(UserModel updatedUserAsTablet) async {
    _isTablet = true; // ✅ 태블릿 계정
    _user = updatedUserAsTablet;
    notifyListeners();

    // UserModel → TabletModel 매핑 (A안: docId = handle(=phone)-한글지역명)
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
      handle: handle, // 핵심: phone을 handle로
      position: updatedUserAsTablet.position,
      role: updatedUserAsTablet.role,
      selectedArea: updatedUserAsTablet.selectedArea,
      startTime: updatedUserAsTablet.startTime,
    );

    await _repository.updateTablet(tablet);
    await _saveTabletPrefsFromUser(updatedUserAsTablet);
    await _fetchTabletsByArea();
  }

  Future<void> clearUserToPhone() async {
    if (_user == null) return;

    // ✅ 분기: user_accounts vs tablet_accounts
    if (_isTablet) {
      await _repository.updateLogOutTabletStatus(
        _user!.phone, // tablet 모드에서는 phone 슬롯 = handle
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

    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();

    PlateTtsListenerService.stop();
    ChatTtsListenerService.stop();

    _user = null;
    _isTablet = false;
    notifyListeners();
  }

  // =========================
  // ===== 초기 로드 분기 =====
  // =========================
  Future<void> loadUsersOnly() async {
    _isLoading = true;
    _previousSelectedArea = '';
    notifyListeners();
    await _fetchUsersByAreaWithCache();
  }

  /// ✅ 태블릿(tablet_accounts) 전용 초기 로드 (캐시 생략, 바로 네트워크)
  Future<void> loadTabletsOnly() async {
    _isLoading = true;
    _previousSelectedArea = '';
    notifyListeners();
    await _fetchTabletsByArea();
  }

  // ===========================
  // ===== CRUD 래핑 메서드 =====
  // ===========================
  Future<void> addUserCard(UserModel user, {void Function(String)? onError}) async {
    try {
      final correctedUser = user.copyWith();
      await _repository.addUserCard(correctedUser);
      await _fetchUsersByAreaWithCache();
    } catch (e) {
      onError?.call('사용자 추가 실패: $e');
    }
  }

  Future<void> addTabletCard(TabletModel tablet, {void Function(String)? onError}) async {
    try {
      final correctedTablet = tablet.copyWith();
      await _repository.addTabletCard(correctedTablet);
      await _fetchTabletsByArea();
    } catch (e, st) {
      debugPrint('addTabletCard error: $e\n$st');
      onError?.call('태블릿 계정 추가 실패: $e');
    }
  }

  Future<void> deleteUserCard(List<String> ids, {void Function(String)? onError}) async {
    try {
      await _repository.deleteUsers(ids);
      await _fetchUsersByAreaWithCache();
    } catch (e) {
      onError?.call('사용자 삭제 실패: $e');
    }
  }

  Future<void> deleteTabletCard(List<String> ids, {void Function(String)? onError}) async {
    try {
      await _repository.deleteTablets(ids);
      await _fetchTabletsByArea();
    } catch (e) {
      onError?.call('태블릿 삭제 실패: $e');
    }
  }

  Future<void> toggleUserCard(String id) async {
    _selectedUserId = (_selectedUserId == id) ? null : id;
    notifyListeners();
  }

  // ========================
  // ===== Prefs 저장 등 =====
  // ========================
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
    debugPrint("📌 SharedPreferences 저장 완료");
  }

  Future<void> _saveTabletPrefsFromUser(UserModel asUser) async {
    final prefs = await SharedPreferences.getInstance();
    final handle = asUser.phone.trim().toLowerCase();
    final areaName =
    (asUser.selectedArea ?? asUser.currentArea ?? asUser.areas.firstOrNull ?? '').trim();

    await prefs.setString('handle', handle);
    await prefs.setString('selectedArea', areaName); // 한글 지역명
    await prefs.setString(
      'englishSelectedAreaName',
      asUser.englishSelectedAreaName ?? areaName, // 값 없으면 한글명 보존
    );
    await prefs.setString('division', asUser.divisions.firstOrNull ?? '');
    await prefs.setString('role', asUser.role);
    await prefs.setString('startTime', _timeToString(asUser.startTime) ?? '');
    await prefs.setString('endTime', _timeToString(asUser.endTime) ?? '');
    await prefs.setStringList('fixedHolidays', asUser.fixedHolidays);
    await prefs.setString('position', asUser.position ?? '');
  }

  // ===========================
  // ===== 자동 로그인(유저) =====
  // ===========================
  Future<void> loadUserToLogIn() async {
    debugPrint("loadUserToLogIn, 자동 로그인 시도");

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

      _isTablet = false; // ✅ 사람 계정 세션
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

      Future.microtask(() {
        PlateTtsListenerService.start(currentArea);
        ChatTtsListenerService.start(currentArea);
      });
    } catch (e) {
      debugPrint("loadUserToLogIn, 오류: $e");
    }
  }

  // =============================
  // ===== 자동 로그인(태블릿) =====
  // =============================
  Future<void> loadTabletToLogIn() async {
    debugPrint("loadTabletToLogIn, 자동 로그인 시도");

    try {
      final prefs = await SharedPreferences.getInstance();

      // A안: 한글 지역명 사용
      final handle = prefs.getString('handle')?.trim().toLowerCase();
      final selectedArea = prefs.getString('selectedArea')?.trim(); // 한글 지역명
      final division = prefs.getString('division')?.trim();
      final role = prefs.getString('role')?.trim();
      final startTimeStr = prefs.getString('startTime');
      final endTimeStr = prefs.getString('endTime');
      final fixedHolidays = prefs.getStringList('fixedHolidays') ?? [];
      final position = prefs.getString('position');

      if (handle == null || selectedArea == null) return;

      // tablet_accounts에서 조회 (docId = handle-한글지역명)
      final tablet = await _repository.getTabletByHandleAndAreaName(handle, selectedArea);
      if (tablet == null) return;

      _isTablet = true; // ✅ 태블릿 계정 세션

      // TabletModel → UserModel 매핑 (UI/상태 호환)
      var userData = _mapTabletToUser(
        tablet,
        currentAreaOverride: selectedArea, // 표시 영역은 한글 지역명
      );

      // 프리퍼런스 값으로 일부 필드 보강(있을 때만)
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

      // tablet_accounts의 currentArea를 세션 시작 시 동기화
      await _repository.updateLoadCurrentAreaTablet(handle, userData.areas.firstOrNull ?? '', selectedArea);

      Future.microtask(() {
        PlateTtsListenerService.start(currentArea);
        ChatTtsListenerService.start(currentArea);
      });
    } catch (e) {
      debugPrint("loadTabletToLogIn, 오류: $e");
    }
  }

  Future<void> areaPickerCurrentArea(String newArea) async {
    if (_user == null) return;

    final updatedUser = _user!.copyWith(currentArea: newArea);
    _user = updatedUser;
    notifyListeners();

    try {
      // ✅ 분기: user_accounts vs tablet_accounts
      if (_isTablet) {
        await _repository.areaPickerCurrentAreaTablet(
          _user!.phone.trim(), // tablet 모드에서는 phone 슬롯 = handle
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

    PlateTtsListenerService.start(newArea);
    ChatTtsListenerService.start(newArea);
  }

  // ===========================
  // ===== 내부 리스트 로드 =====
  // ===========================
  Future<void> _fetchUsersByAreaWithCache() async {
    final selectedArea = _areaState.currentArea.trim();
    if (selectedArea.isEmpty || _previousSelectedArea == selectedArea) return;

    _previousSelectedArea = selectedArea;
    _isLoading = true;
    notifyListeners();

    try {
      final data = await _repository.getUsersByAreaOnceWithCache(selectedArea);
      _users = data;
      _selectedUserId = null;
    } catch (e) {
      debugPrint('_fetchUsersByAreaWithCache 실패: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// tablet_accounts 전용: 캐시 대신 즉시 Firestore 호출
  Future<void> _fetchTabletsByArea() async {
    final selectedArea = _areaState.currentArea.trim();
    if (selectedArea.isEmpty || _previousSelectedArea == selectedArea) return;

    _previousSelectedArea = selectedArea;
    _isLoading = true;
    notifyListeners();

    try {
      final data = await _repository.refreshTabletsBySelectedArea(selectedArea);
      _users = data; // UserModel(핸들→phone 매핑) 리스트
      _selectedUserId = null;
    } catch (e) {
      debugPrint('_fetchTabletsByArea 실패: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // =====================
  // ===== 유틸 메서드 =====
  // =====================
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
      phone: t.handle, // UI 호환: handle → phone 슬롯
      position: t.position,
      role: t.role,
      selectedArea: currentAreaOverride ?? t.selectedArea,
      startTime: t.startTime,
    );
    // 주의: 캐시/상태 호환을 위해 UserModel로 유지
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
}
