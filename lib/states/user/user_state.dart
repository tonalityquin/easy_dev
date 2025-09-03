import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/tablet_model.dart';
import '../../repositories/user/user_repository.dart';
import '../../models/user_model.dart';
import '../../utils/plate_tts_listener_service.dart';
import '../../utils/chat_tts_listener_service.dart'; // ✅ 추가
import '../area/area_state.dart';

class UserState extends ChangeNotifier {
  final UserRepository _repository;
  final AreaState _areaState;

  UserModel? _user;
  List<UserModel> _users = [];
  String? _selectedUserId;
  bool _isLoading = true;

  StreamSubscription<List<UserModel>>? _subscription;
  String _previousSelectedArea = '';

  UserModel? get user => _user;
  List<UserModel> get users => _users;
  String? get selectedUserId => _selectedUserId;
  bool get isLoggedIn => _user != null;
  bool get isWorking => _user?.isWorking ?? false;
  bool get isLoading => _isLoading;

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

  /// ========== 사용자(user_accounts) 목록 갱신 ==========
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

  /// ========== 태블릿(tablet_accounts) 목록 갱신 ==========
  Future<void> refreshTabletsBySelectedAreaAndCache() async {
    final selectedArea = _areaState.currentArea.trim();
    _isLoading = true;
    notifyListeners();

    try {
      // ✅ tablet_accounts 기반 목록 호출 (UserModel로 매핑된 리스트 반환)
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

  Future<void> isHeWorking() async {
    if (_user == null) return;

    final newStatus = !_user!.isWorking;
    await _repository.updateWorkingUserStatus(
      _user!.phone,
      _user!.areas.firstOrNull ?? '',
      isWorking: newStatus,
    );

    _user = _user!.copyWith(isWorking: newStatus);
    notifyListeners();
  }

  Future<void> updateLoginUser(UserModel updatedUser) async {
    _user = updatedUser;
    notifyListeners();
    await _repository.updateUser(updatedUser);
    await saveCardToUserPhone(updatedUser);
    await _fetchUsersByAreaWithCache();
  }

  Future<void> clearUserToPhone() async {
    if (_user == null) return;

    await _repository.updateLogOutUserStatus(
      _user!.phone,
      _user!.areas.firstOrNull ?? '',
      isWorking: false,
      isSaved: false,
    );

    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();

    PlateTtsListenerService.stop();
    ChatTtsListenerService.stop();

    _user = null;
    notifyListeners();
  }

  /// 사용자(user_accounts) 전용 초기 로드
  Future<void> loadUsersOnly() async {
    _isLoading = true;
    _previousSelectedArea = '';
    notifyListeners();
    await _fetchUsersByAreaWithCache();
  }

  /// ✅ 태블릿(tablet_accounts) 전용 초기 로드
  Future<void> loadTabletsOnly() async {
    _isLoading = true;
    _previousSelectedArea = '';
    notifyListeners();
    await _fetchTabletsByArea(); // 캐시 미사용, 바로 Firestore 호출
  }

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
      final correctedTablet = tablet.copyWith(); // 타입: TabletModel
      await _repository.addTabletCard(correctedTablet);
      await _fetchTabletsByArea(); // ✅ tablet 목록 다시 로드
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

  /// ✅ 태블릿 삭제
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

  Future<void> loadTabletToLogIn() async {
    debugPrint("loadTabletToLogIn, 자동 로그인 시도");

    try {
      final prefs = await SharedPreferences.getInstance();

      final handle = prefs.getString('handle')?.trim();
      final selectedArea = prefs.getString('selectedArea')?.trim(); // 한글 지역명
      final areaKey = prefs.getString('englishSelectedAreaName')?.trim() ?? selectedArea;

      final division = prefs.getString('division')?.trim();
      final role = prefs.getString('role')?.trim();
      final startTimeStr = prefs.getString('startTime');
      final endTimeStr = prefs.getString('endTime');
      final fixedHolidays = prefs.getStringList('fixedHolidays') ?? [];
      final position = prefs.getString('position');

      if (handle == null || areaKey == null) return;

      final userId = "$handle-$areaKey";
      var userData = await _repository.getUserById(userId);
      if (userData == null) return;

      final trimmedSelectedArea = (selectedArea ?? userData.currentArea ?? '').trim();

      if (trimmedSelectedArea.isNotEmpty) {
        await _repository.updateLoadCurrentArea(
          handle, // phone 대신 handle
          userData.areas.firstOrNull ?? '',
          trimmedSelectedArea,
        );
      }

      userData = userData.copyWith(
        currentArea: trimmedSelectedArea.isNotEmpty ? trimmedSelectedArea : userData.currentArea,
        role: role ?? userData.role,
        position: position ?? userData.position,
        startTime: _stringToTimeOfDay(startTimeStr),
        endTime: _stringToTimeOfDay(endTimeStr),
        fixedHolidays: fixedHolidays,
        divisions: division != null ? [division] : userData.divisions,
        isSaved: true,
        phone: handle, // 호환 슬롯
        selectedArea: trimmedSelectedArea.isNotEmpty ? trimmedSelectedArea : userData.selectedArea,
        englishSelectedAreaName: areaKey,
      );

      _user = userData;
      notifyListeners();

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
      await _repository.areaPickerCurrentArea(
        _user!.phone.trim(),
        _user!.areas.firstOrNull ?? '',
        newArea.trim(),
      );
    } catch (e) {
      debugPrint("areaPickerCurrentArea 실패: $e");
    }

    PlateTtsListenerService.start(newArea);
    ChatTtsListenerService.start(newArea);
  }

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

  /// ✅ tablet_accounts 전용: 캐시 대신 즉시 Firestore 호출
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
