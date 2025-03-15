import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../repositories/user/firestore_user_repository.dart';
import '../repositories/user/user_repository.dart';
import '../models/user_model.dart';

class UserState extends ChangeNotifier {
  final UserRepository _repository;
  UserModel? _user;
  List<UserModel> _users = [];
  Map<String, bool> _selectedUsers = {};
  bool _isLoading = true;

  UserState(this._repository) {
    loadUser();
    _initializeUsers();
  }

  UserModel? get user => _user;
  List<UserModel> get users => _users;
  Map<String, bool> get selectedUsers => _selectedUsers;
  bool get isLoggedIn => _user != null;
  bool get isWorking => _user?.isWorking ?? false;
  bool get isLoading => _isLoading;
  String get role => _user?.role ?? '';
  String get area => _user?.area ?? '';
  String get name => _user?.name ?? '';
  String get phone => _user?.phone ?? '';
  String get password => _user?.password ?? '';

  Future<void> saveUserToPreferences(UserModel user) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('phone', user.phone);
    await prefs.setString('area', user.area);
    debugPrint("📌 SharedPreferences 저장 완료: phone=${user.phone}, area=${user.area}");
  }


  Future<void> loadUser() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final phone = prefs.getString('phone');
      final area = prefs.getString('area');

      if (phone == null || area == null) {
        debugPrint("❌ 자동 로그인 실패: 저장된 전화번호 또는 지역 정보가 없습니다.");
        return;
      }

      final userId = "$phone-$area";
      if (_repository is FirestoreUserRepository) {
        final userData = await _repository.getUserById(userId);
        if (userData == null) {
          debugPrint("❌ 자동 로그인 실패: Firestore에서 사용자 정보를 찾을 수 없습니다.");
          return;
        }

        _user = userData;
        await saveUserToPreferences(userData); // ✅ SharedPreferences에 사용자 정보 저장
        notifyListeners();
        debugPrint("✅ 자동 로그인 성공: ${_user!.name} (${_user!.phone})");
      }
    } catch (e) {
      debugPrint("❌ 자동 로그인 중 오류 발생: $e");
    }
  }


  void _initializeUsers() {
    _repository.getUsersStream().listen(
          (data) {
        _users = data;
        _selectedUsers = { for (var user in data) user.id: user.isSelected };
        _isLoading = false;
        notifyListeners();
      },
      onError: (error) {
        debugPrint('Error syncing users: \$error');
      },
    );
  }

  Future<void> toggleWorkStatus() async {
    if (_user == null) return;

    final newStatus = !_user!.isWorking;
    await _repository.updateWorkStatus(_user!.phone, _user!.area, newStatus);
    _user = UserModel(
      id: _user!.id,
      name: _user!.name,
      phone: _user!.phone,
      email: _user!.email,
      role: _user!.role,
      password: _user!.password,
      area: _user!.area,
      isSelected: _user!.isSelected,
      isWorking: newStatus,
    );
    notifyListeners();
  }

  Future<void> clearUser() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    _user = null;
    notifyListeners();
  }

  Future<void> updateUser(UserModel updatedUser) async {
    _user = updatedUser;
    notifyListeners();
    await _repository.addUser(updatedUser);
    await saveUserToPreferences(updatedUser); // ✅ 로그인 성공 후 SharedPreferences 저장
  }


  Future<void> addUser(UserModel user, {void Function(String)? onError}) async {
    try {
      final correctedUser = UserModel(
        id: user.id,
        name: user.name,
        phone: user.phone,
        email: user.email,
        role: user.role,
        password: user.password,
        area: user.area,
        isSelected: user.isSelected,
        isWorking: user.isWorking,
      );
      await _repository.addUser(correctedUser);
    } catch (e) {
      onError?.call('사용자 추가 실패: \$e');
    }
  }

  Future<void> deleteUsers(List<String> ids, {void Function(String)? onError}) async {
    try {
      await _repository.deleteUsers(ids);
    } catch (e) {
      onError?.call('사용자 삭제 실패: \$e');
    }
  }

  Future<void> toggleSelection(String id) async {
    if (!_selectedUsers.containsKey(id)) return;
    try {
      final newSelectionState = !_selectedUsers[id]!;
      await _repository.toggleUserSelection(id, newSelectionState);
      _selectedUsers[id] = newSelectionState;
      notifyListeners();
    } catch (e) {
      debugPrint('사용자 선택 오류: \$e');
    }
  }
}