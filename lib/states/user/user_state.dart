import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../repositories/user/user_repository.dart';
import '../../models/user_model.dart';
import 'package:easydev/services/plate_tts_listener_service.dart';
import '../area/area_state.dart';

class UserState extends ChangeNotifier {
  final UserRepository _repository;
  final AreaState _areaState;

  UserState(this._repository, this._areaState) {
    _areaState.addListener(_fetchUsersByAreaWithCache); // 캐싱 호출
  }

  UserModel? _user;
  List<UserModel> _users = [];
  Map<String, bool> _selectedUsers = {};
  bool _isLoading = true;

  StreamSubscription<List<UserModel>>? _subscription; // ⚠️ 현재 미사용
  String _previousSelectedArea = '';

  UserModel? get user => _user;
  List<UserModel> get users => _users;
  Map<String, bool> get selectedUsers => _selectedUsers;

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

  /// 🕰 캐시에 있는 사용자들 반환
  Future<void> _fetchUsersByAreaWithCache() async {
    final selectedArea = _areaState.currentArea.trim();
    if (selectedArea.isEmpty || _previousSelectedArea == selectedArea) return;

    _previousSelectedArea = selectedArea;
    _isLoading = true;
    notifyListeners();

    try {
      final data = await _repository.getUsersBySelectedAreaOnceWithCache(selectedArea);
      _users = data;
      _selectedUsers = {for (var user in data) user.id: user.isSelected};
    } catch (e) {
      debugPrint('🔥 Error fetching cached users: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// 🔄 Firestore 호출 + 캐시 갱신 트리거
  Future<void> refreshUsersBySelectedAreaAndCache() async {
    final selectedArea = _areaState.currentArea.trim();
    _isLoading = true;
    notifyListeners();

    try {
      final data = await _repository.refreshUsersBySelectedArea(selectedArea);
      _users = data;
      _selectedUsers = {for (var user in data) user.id: user.isSelected};
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
    if (!_selectedUsers.containsKey(id)) return;

    try {
      final newSelectionState = !_selectedUsers[id]!;
      await _repository.toggleUserSelection(id, newSelectionState);
      _selectedUsers[id] = newSelectionState;
      notifyListeners();
    } catch (e) {
      debugPrint('사용자 선택 오류: $e');
    }
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
    debugPrint("[DEBUG] 자동 로그인 시도");

    try {
      final prefs = await SharedPreferences.getInstance();
      final phone = prefs.getString('phone')?.trim();
      final selectedArea = prefs.getString('selectedArea')?.trim();

      debugPrint("📥 자동 로그인 정보 → phone=$phone / selectedArea=$selectedArea");

      if (phone == null || selectedArea == null) return;

      final userId = "$phone-$selectedArea";
      debugPrint("[DEBUG] 시도할 userId: $userId");

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
      debugPrint("[TTS] 감지 시작: $currentArea");
    } catch (e) {
      debugPrint("[DEBUG] 자동 로그인 오류: $e");
    }
  }

  Future<void> updateCurrentArea(String newArea) async {
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
        "✅ Firestore currentArea 업데이트 완료 → ${_user!.phone.trim()}-${_user!.areas.firstOrNull} → $newArea",
      );
    } catch (e) {
      debugPrint("❌ Firestore currentArea 업데이트 실패: $e");
    }

    PlateTtsListenerService.start(newArea);
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _areaState.removeListener(_fetchUsersByAreaWithCache);
    super.dispose();
  }
}
