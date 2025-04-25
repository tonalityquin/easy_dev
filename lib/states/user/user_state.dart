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

  UserModel? _user;
  List<UserModel> _users = [];
  Map<String, bool> _selectedUsers = {};
  bool _isLoading = true;

  StreamSubscription<List<UserModel>>? _subscription;
  String _previousArea = '';

  UserState(this._repository, this._areaState) {
    _areaState.addListener(_realtimeUsers);
  }

  Future<void> loadUsersOnly() async {
    _isLoading = true;
    _previousArea = ''; // ✅ 무조건 재구독을 유도하기 위해 초기화
    notifyListeners();

    try {
      _realtimeUsers();
    } catch (e) {
      debugPrint("📛 사용자 목록 로딩 실패: $e");
      _isLoading = false;
      notifyListeners();
    }
  }

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

  Future<void> saveCardToUserPhone(UserModel user) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('phone', user.phone);
    await prefs.setString('area', user.currentArea ?? user.areas.firstOrNull ?? '');
    await prefs.setString('division', user.divisions.firstOrNull ?? '');
    debugPrint("📌 SharedPreferences 저장 완료: phone=${user.phone}");
  }

  Future<void> loadUserToLogIn() async {
    debugPrint("[DEBUG] 자동 로그인 시도");

    try {
      final prefs = await SharedPreferences.getInstance();
      final phone = prefs.getString('phone')?.trim();
      final area = prefs.getString('area')?.trim();

      if (phone == null || area == null) {
        debugPrint("[DEBUG] 자동 로그인 실패 - 저장된 전화번호 또는 지역 없음");
        return;
      }

      final userId = "$phone-$area";
      var userData = await _repository.getUserById(userId);
      if (userData == null) {
        debugPrint("[DEBUG] Firestore에 사용자 없음");
        return;
      }

      final trimmedPhone = userData.phone.trim();
      final trimmedArea = area.trim();
      await _repository.updateCurrentArea(trimmedPhone, trimmedArea, trimmedArea);
      userData = userData.copyWith(currentArea: trimmedArea);
      await _repository.updateUserStatus(phone, area, isSaved: true);
      _user = userData.copyWith(isSaved: true);
      notifyListeners();

      PlateTtsListenerService.start(currentArea);
      debugPrint("[TTS] 감지 시작: $currentArea");
    } catch (e) {
      debugPrint("[DEBUG] 자동 로그인 오류: $e");
    }
  }

  void _realtimeUsers() {
    final area = _areaState.currentArea;
    if (area.isEmpty || _previousArea == area) return;

    _previousArea = area;
    _subscription?.cancel();

    _isLoading = true; // ✅ 시작 시 로딩 처리
    notifyListeners();

    _subscription = _repository.getUsersStream(area).listen(
      (data) {
        _users = data;
        _selectedUsers = {for (var user in data) user.id: user.isSelected};
        _isLoading = false;
        notifyListeners();
      },
      onError: (error) {
        debugPrint('Error syncing users: $error');
        _isLoading = false; // ✅ 에러 시에도 해제
        notifyListeners();
      },
      onDone: () {
        if (_isLoading) {
          _isLoading = false; // ✅ 강제 해제
          notifyListeners();
        }
      },
    );
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

  Future<void> updateUserCard(UserModel updatedUser) async {
    _user = updatedUser;
    notifyListeners();
    await _repository.addUser(updatedUser);
    await saveCardToUserPhone(updatedUser);
  }

  Future<void> addUserCard(UserModel user, {void Function(String)? onError}) async {
    try {
      final correctedUser = user.copyWith();
      await _repository.addUser(correctedUser);
    } catch (e) {
      onError?.call('사용자 추가 실패: $e');
    }
  }

  Future<void> deleteUserCard(List<String> ids, {void Function(String)? onError}) async {
    try {
      await _repository.deleteUsers(ids);
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
      debugPrint("✅ Firestore currentArea 업데이트 완료 → ${_user!.phone.trim()}-${_user!.areas.firstOrNull} → $newArea");
    } catch (e) {
      debugPrint("❌ Firestore currentArea 업데이트 실패: $e");
    }

    PlateTtsListenerService.start(newArea);
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _areaState.removeListener(_realtimeUsers);
    super.dispose();
  }
}
