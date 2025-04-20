import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../repositories/user/user_repository.dart';
import '../../models/user_model.dart';
import 'package:easydev/services/plate_tts_listener_service.dart';

class UserState extends ChangeNotifier {
  final UserRepository _repository;
  UserModel? _user;
  List<UserModel> _users = [];
  Map<String, bool> _selectedUsers = {};
  bool _isLoading = true;

  UserState(this._repository);

  Future<void> loadUsersOnly() async {
    _isLoading = true;
    notifyListeners();

    try {
      _realtimeUsers();
    } catch (e) {
      debugPrint("📛 사용자 목록 로딩 실패: $e");
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

  String get area => _user?.area ?? '';

  String get name => _user?.name ?? '';

  String get phone => _user?.phone ?? '';

  String get password => _user?.password ?? '';

  String get division => _user?.division ?? '';

  String get currentArea => _user?.currentArea ?? area;

  Future<void> saveCardToUserPhone(UserModel user) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('phone', user.phone);
    await prefs.setString('area', user.area);
    debugPrint("📌 SharedPreferences 저장 완료: phone=${user.phone}, area=${user.area}");
  }

  Future<void> loadUserToLogIn() async {
    debugPrint("[DEBUG] 자동 로그인 시도");

    try {
      final prefs = await SharedPreferences.getInstance();
      final phone = prefs.getString('phone')?.trim();
      final area = prefs.getString('area')?.trim();

      if (phone == null || area == null) {
        debugPrint("[DEBUG] 자동 로그인 실패 - 저장된 전화번호 또는 지역 정보 없음");
        return;
      }

      final userId = "$phone-$area";
      var userData = await _repository.getUserById(userId);

      if (userData == null) {
        debugPrint("[DEBUG] 자동 로그인 실패 - Firestore에서 사용자 정보 없음");
        return;
      }

      // ✅ currentArea를 SharedPreferences의 area로 강제 동기화
      final trimmedPhone = userData.phone.trim();
      final trimmedArea = userData.area.trim();
      debugPrint("[DEBUG] updateCurrentArea 요청: userId=${trimmedPhone}-${trimmedArea} → currentArea=$trimmedArea");

      await _repository.updateCurrentArea(trimmedPhone, trimmedArea, trimmedArea);
      userData = userData.copyWith(currentArea: trimmedArea);
      debugPrint("🛠 currentArea 동기화 완료: $trimmedArea");

      await _repository.updateUserStatus(phone, area, isSaved: true);
      _user = userData.copyWith(isSaved: true);
      notifyListeners();

      PlateTtsListenerService.start(currentArea);
      debugPrint("[TTS] 자동 로그인 후 감지 시작: $currentArea");
    } catch (e) {
      debugPrint("[DEBUG] 자동 로그인 중 오류 발생: $e");
    }
  }

  void _realtimeUsers() {
    _repository.getUsersStream().listen(
      (data) {
        _users = data;
        _selectedUsers = {for (var user in data) user.id: user.isSelected};
        _isLoading = false;
        notifyListeners();
      },
      onError: (error) {
        debugPrint('Error syncing users: $error');
      },
    );
  }

  Future<void> isHeWorking() async {
    if (_user == null) return;

    final newStatus = !_user!.isWorking;

    await _repository.updateUserStatus(
      _user!.phone,
      _user!.area,
      isWorking: newStatus,
    );

    _user = _user!.copyWith(isWorking: newStatus);
    notifyListeners();
  }

  Future<void> clearUserToPhone() async {
    if (_user == null) return;

    await _repository.updateUserStatus(
      _user!.phone,
      _user!.area,
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
      final correctedUser = UserModel(
        id: user.id,
        name: user.name,
        phone: user.phone,
        email: user.email,
        role: user.role,
        password: user.password,
        area: user.area,
        division: user.division,
        currentArea: user.currentArea,
        isSelected: user.isSelected,
        isWorking: user.isWorking,
        isSaved: user.isSaved,
      );
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
        _user!.area.trim(),
        newArea.trim(),
      );
      debugPrint("✅ Firestore currentArea 업데이트 완료 → ${_user!.phone.trim()}-${_user!.area.trim()} → $newArea");
    } catch (e) {
      debugPrint("❌ Firestore currentArea 업데이트 실패: $e / userId: ${_user!.phone.trim()}-${_user!.area.trim()}");
    }

    PlateTtsListenerService.start(newArea);
  }
}
