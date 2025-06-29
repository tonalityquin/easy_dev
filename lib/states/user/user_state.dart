import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../repositories/user/user_repository.dart';
import '../../models/user_model.dart';
import '../../utils/plate_tts_listener_service.dart';
import '../area/area_state.dart';

class UserState extends ChangeNotifier {
  // 🔹 1. 필드
  final UserRepository _repository;
  final AreaState _areaState;

  UserModel? _user;
  List<UserModel> _users = [];
  String? _selectedUserId;
  bool _isLoading = true;

  StreamSubscription<List<UserModel>>? _subscription;
  String _previousSelectedArea = '';

  // 🔹 2. 생성자
  UserState(this._repository, this._areaState) {
    _areaState.addListener(_fetchUsersByAreaWithCache);
  }

  // 🔹 3. 게터
  UserModel? get user => _user;
  List<UserModel> get users => _users;
  String? get selectedUserId => _selectedUserId;

  bool get isLoggedIn => _user != null;
  bool get isWorking => _user?.isWorking ?? false;
  bool get isSaved => _user?.isSaved ?? false;
  bool get isLoading => _isLoading;

  String get role => _user?.role ?? '';
  String get name => _user?.name ?? '';
  String get phone => _user?.phone ?? '';
  String get password => _user?.password ?? '';
  String get area => _user?.areas.firstOrNull ?? '';
  String get division => _user?.divisions.firstOrNull ?? '';
  String get currentArea => _user?.currentArea ?? area;

  // 🔹 4. Public 메서드

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

  Future<void> isHeWorking() async {
    if (_user == null) return;

    final newStatus = !_user!.isWorking;
    await _repository.updateUserStatus(
      _user!.phone,
      _user!.areas.firstOrNull ?? '',
      isWorking: newStatus,
    );

    _user = _user!.copyWith(isWorking: newStatus);
    notifyListeners();
  }

  Future<void> loadUsersOnly() async {
    _isLoading = true;
    _previousSelectedArea = '';
    notifyListeners();

    await _fetchUsersByAreaWithCache();
  }

  Future<void> clearUserToPhone() async {
    if (_user == null) return;

    await _repository.updateUserStatus(
      _user!.phone,
      _user!.areas.firstOrNull ?? '',
      isWorking: false,
      isSaved: false,
    );

    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    _user = null;
    notifyListeners();
  }

  Future<void> addUserCard(UserModel user, {void Function(String)? onError}) async {
    try {
      final correctedUser = user.copyWith();
      await _repository.addUser(correctedUser);
      await _fetchUsersByAreaWithCache();
    } catch (e) {
      onError?.call('사용자 추가 실패: $e');
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

  Future<void> toggleUserCard(String id) async {
    if (_selectedUserId == id) {
      _selectedUserId = null;
    } else {
      _selectedUserId = id;
    }
    notifyListeners();
  }

  Future<void> saveCardToUserPhone(UserModel user) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('phone', user.phone);
    await prefs.setString('selectedArea', user.selectedArea ?? '');
    await prefs.setString('division', user.divisions.firstOrNull ?? '');
    debugPrint(
      "📌 SharedPreferences 저장 완료: phone=${user.phone}, selectedArea=${user.selectedArea}",
    );
  }

  Future<void> updateUserCard(UserModel updatedUser) async {
    _user = updatedUser;
    notifyListeners();
    await _repository.addUser(updatedUser);
    await saveCardToUserPhone(updatedUser);
    await _fetchUsersByAreaWithCache();
  }

  Future<void> loadUserToLogIn() async {
    debugPrint("loadUserToLogIn, 자동 로그인 시도");

    try {
      final prefs = await SharedPreferences.getInstance();
      final phone = prefs.getString('phone')?.trim();
      final selectedArea = prefs.getString('selectedArea')?.trim();

      debugPrint("loadUserToLogIn, 자동 로그인 정보 → phone=$phone / selectedArea=$selectedArea");

      if (phone == null || selectedArea == null) return;

      final userId = "$phone-$selectedArea";
      debugPrint("loadUserToLogIn, 시도할 userId: $userId");

      var userData = await _repository.getUserById(userId);
      if (userData == null) return;

      final trimmedPhone = userData.phone.trim();
      final trimmedArea = selectedArea.trim();

      await _repository.updateCurrentArea(trimmedPhone, trimmedArea, trimmedArea);
      userData = userData.copyWith(currentArea: trimmedArea);

      await _repository.updateUserStatus(phone, trimmedArea, isSaved: true);
      _user = userData.copyWith(isSaved: true);
      notifyListeners();

      Future.microtask(() => PlateTtsListenerService.start(currentArea));
      debugPrint("loadUserToLogIn, TTS 감지 시작: $currentArea");
    } catch (e) {
      debugPrint("loadUserToLogIn, 자동 로그인 오류: $e");
    }
  }

  Future<void> areaPickerCurrentArea(String newArea) async {
    if (_user == null) return;

    final updatedUser = _user!.copyWith(currentArea: newArea);
    _user = updatedUser;
    notifyListeners();

    try {
      await _repository.updateCurrentArea(
        _user!.phone.trim(),
        _user!.areas.firstOrNull ?? '',
        newArea.trim(),
      );
      debugPrint(
        "areaPickerCurrentArea, currentArea 업데이트 완료 → ${_user!.phone.trim()}-${_user!.areas.firstOrNull} → $newArea",
      );
    } catch (e) {
      debugPrint("areaPickerCurrentArea, currentArea 업데이트 실패: $e");
    }

    PlateTtsListenerService.start(newArea);
  }

  // 🔹 5. Private 메서드

  Future<void> _fetchUsersByAreaWithCache() async {
    final selectedArea = _areaState.currentArea.trim();
    if (selectedArea.isEmpty || _previousSelectedArea == selectedArea) return;

    _previousSelectedArea = selectedArea;
    _isLoading = true;
    notifyListeners();

    try {
      final data = await _repository.getUsersBySelectedAreaOnceWithCache(selectedArea);
      _users = data;
      _selectedUserId = null;
    } catch (e) {
      debugPrint('_fetchUsersByAreaWithCache, Error fetching cached users: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // 🔹 6. Override

  @override
  void dispose() {
    _subscription?.cancel();
    _areaState.removeListener(_fetchUsersByAreaWithCache);
    super.dispose();
  }
}
