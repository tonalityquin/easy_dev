import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../repositories/user_repository.dart';

class UserState extends ChangeNotifier {
  final UserRepository _repository;

  UserState(this._repository) {
    loadUser();
    _fetchUsers();
  }

  String _name = '';
  String _phone = '';
  String _role = '';
  String _area = '';
  String _password = '';
  bool _isLoggedIn = false;
  bool _isWorking = false;

  List<Map<String, String>> _users = [];
  Map<String, bool> _selectedUsers = {};
  bool _isLoading = true;

  String get name => _name;

  String get phone => _phone;

  String get role => _role;

  String get area => _area;

  String get password => _password;

  bool get isLoggedIn => _isLoggedIn;

  bool get isWorking => _isWorking;

  List<Map<String, String>> get users => _users;

  Map<String, bool> get selectedUsers => _selectedUsers;

  bool get isLoading => _isLoading;

  Future<void> loadUser() async {
    final prefs = await SharedPreferences.getInstance();
    _isLoggedIn = prefs.getBool('isLoggedIn') ?? false;

    if (_isLoggedIn) {
      _name = prefs.getString('name') ?? '';
      _phone = prefs.getString('phone') ?? '';
      _role = prefs.getString('role') ?? '';
      _area = prefs.getString('area') ?? '';
      _password = prefs.getString('password') ?? '';

      // 🔹 Firestore에서 출근 상태를 강제로 가져옴
      final userData = await _repository.getUserByPhone(_phone);
      if (userData != null) {
        _isWorking = userData['isWorking'] ?? false; // 🔹 Firestore 값 반영
        await prefs.setBool('isWorking', _isWorking); // 🔹 SharedPreferences 동기화
      }

      notifyListeners(); // 🔹 UI 즉시 업데이트
    } else {
      _clearState();
    }

    notifyListeners();
  }

  void _fetchUsers() {
    _repository.getUsersStream().listen((data) {
      _users = data
          .map((user) => {
                'id': user['id'] as String,
                'name': user['name'] as String,
                'phone': user['phone'] as String,
                'email': user['email'] as String,
                'role': user['role'] as String,
                'password': user['password'] as String,
                'area': user['area'] as String,
              })
          .toList();

      _selectedUsers = {
        for (var user in data) user['id'] as String: user['isSelected'] as bool,
      };

      _isLoading = false;
      notifyListeners();
    });
  }

  Future<void> toggleWorkStatus() async {
    _isWorking = !_isWorking;
    await _repository.updateWorkStatus(_phone, _area, _isWorking); // 🔹 Firestore 업데이트
    await _saveToPreferences(); // 🔹 로컬 저장

    // 🔹 Firestore에서 최신 데이터를 다시 불러옴 (다른 기기에서도 일관성 유지)
    final userData = await _repository.getUserByPhone(_phone);
    if (userData != null) {
      _isWorking = userData['isWorking'] ?? false;
      await _saveToPreferences();
    }

    notifyListeners();
  }

  Future<void> _saveToPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('name', _name);
    await prefs.setString('phone', _phone);
    await prefs.setString('role', _role);
    await prefs.setString('area', _area);
    await prefs.setString('password', _password);
    await prefs.setBool('isLoggedIn', _isLoggedIn);
    await prefs.setBool('isWorking', _isWorking);
  }

  Future<void> clearUser() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    _clearState();
    notifyListeners();
  }

  Future<void> updateUser({
    required String name,
    required String phone,
    required String role,
    required String password,
    required String area,
  }) async {
    _name = name;
    _phone = phone;
    _role = role;
    _password = password;
    _area = area;
    _isLoggedIn = true;

    notifyListeners();
    await _saveToPreferences();
  }

  void listenToUserStatus() {
    _repository.listenToUserStatus(_phone).listen((userData) {
      if (userData != null) {
        _isWorking = userData['isWorking'] ?? false;
        notifyListeners();
      }
    });
  }

  void _clearState() {
    _name = '';
    _phone = '';
    _role = '';
    _area = '';
    _password = '';
    _isLoggedIn = false;
    _isWorking = false;
  }

  Future<void> addUser(
      String name, String phone, String email, String role, String password, String area, bool isWorking,
      {required void Function(String) onError}) async {
    try {
      final id = '$phone-$area';
      await _repository.addUser(id, {
        'name': name,
        'phone': phone,
        'email': email,
        'role': role,
        'password': password,
        'area': area,
        'isSelected': false,
        'isWorking': false,
      });
    } catch (e) {
      debugPrint('사용자 추가 실패: $e');
      onError('사용자 추가 실패: $e');
    }
  }

  Future<void> deleteUsers(List<String> ids, {required void Function(String) onError}) async {
    try {
      await _repository.deleteUsers(ids);
    } catch (e) {
      debugPrint('사용자 삭제 실패: $e');
      onError('사용자 삭제 실패: $e');
    }
  }

  Future<void> toggleSelection(String id) async {
    final currentState = _selectedUsers[id] ?? false;
    try {
      await _repository.toggleUserSelection(id, !currentState);
    } catch (e) {
      debugPrint('사용자 선택 오류: $e');
    }
  }
}
