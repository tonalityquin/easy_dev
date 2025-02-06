import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../repositories/user_repository.dart';

/// 사용자 상태 관리 클래스
/// - Firestore와 SharedPreferences를 통해 사용자 정보를 관리
class UserState extends ChangeNotifier {
  final UserRepository _repository;

  UserState(this._repository) {
    _fetchUsers(); // Firestore 데이터 실시간 동기화
    loadUser(); // SharedPreferences에서 사용자 정보 복구
  }

  // 사용자 정보 및 상태
  String _name = ''; // 사용자 이름
  String _phone = ''; // 사용자 전화번호
  String _role = ''; // 사용자 역할
  String _area = ''; // 사용자 지역
  bool _isLoggedIn = false; // 로그인 상태

  // Firestore 사용자 리스트
  List<Map<String, String>> _users = [];
  Map<String, bool> _selectedUsers = {}; // 선택된 사용자 상태
  bool _isLoading = true; // 로딩 상태

  // 게터(Getter)
  String get name => _name;

  String get phone => _phone;

  String get role => _role;

  String get area => _area;

  bool get isLoggedIn => _isLoggedIn;

  List<Map<String, String>> get users => _users;

  Map<String, bool> get selectedUsers => _selectedUsers;

  bool get isLoading => _isLoading;

  /// Firestore 사용자 데이터 실시간 동기화
  void _fetchUsers() {
    _repository.getUsersStream().listen((data) {
      _users = data
          .map((user) => {
                'id': user['id'] as String,
                'name': user['name'] as String,
                'phone': user['phone'] as String,
                'email': user['email'] as String,
                'role': user['role'] as String,
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

  /// SharedPreferences에 사용자 정보 저장
  Future<void> _saveToPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('name', _name);
    await prefs.setString('phone', _phone);
    await prefs.setString('role', _role);
    await prefs.setString('area', _area);
    await prefs.setBool('isLoggedIn', _isLoggedIn);
  }

  /// 사용자 정보 업데이트 (로그인 시 호출)
  Future<void> updateUser({
    required String name,
    required String phone,
    required String role,
    required String area,
  }) async {
    _name = name;
    _phone = phone;
    _role = role;
    _area = area;
    _isLoggedIn = true;

    notifyListeners();
    await _saveToPreferences();
  }

  /// SharedPreferences에서 사용자 정보 불러오기
  Future<void> loadUser() async {
    final prefs = await SharedPreferences.getInstance();
    _isLoggedIn = prefs.getBool('isLoggedIn') ?? false;

    if (_isLoggedIn) {
      _name = prefs.getString('name') ?? '';
      _phone = prefs.getString('phone') ?? '';
      _role = prefs.getString('role') ?? '';
      _area = prefs.getString('area') ?? '';
    } else {
      _clearState();
    }

    notifyListeners();
  }

  /// 사용자 선택 상태 토글
  Future<void> toggleSelection(String id) async {
    final currentState = _selectedUsers[id] ?? false;
    try {
      await _repository.toggleUserSelection(id, !currentState);
    } catch (e) {
      debugPrint('Error toggling selection: $e');
    }
  }

  /// Firestore에서 사용자 추가
  /// Firestore에서 사용자 추가 (UI 피드백 가능)
  Future<void> addUser(String name, String phone, String email, String role, String area,
      {required void Function(String) onError}) async {
    try {
      final id = '$phone-$area';
      await _repository.addUser(id, {
        'name': name,
        'phone': phone,
        'email': email,
        'role': role,
        'area': area,
        'isSelected': false,
      });
    } catch (e) {
      debugPrint('❌ Firestore 사용자 추가 실패: $e');
      onError('🚨 사용자 추가 실패: $e'); // ✅ UI 피드백 추가
    }
  }

  /// Firestore에서 사용자 삭제 (UI 피드백 가능)
  Future<void> deleteUsers(List<String> ids, {required void Function(String) onError}) async {
    try {
      await _repository.deleteUsers(ids);
    } catch (e) {
      debugPrint('❌ Firestore 사용자 삭제 실패: $e');
      onError('🚨 사용자 삭제 실패: $e'); // ✅ UI 피드백 추가
    }
  }

  /// SharedPreferences 및 상태 초기화
  Future<void> clearUser() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    _clearState();
    notifyListeners();
  }

  /// 상태 초기화
  void _clearState() {
    _name = '';
    _phone = '';
    _role = '';
    _area = '';
    _isLoggedIn = false;
  }
}
