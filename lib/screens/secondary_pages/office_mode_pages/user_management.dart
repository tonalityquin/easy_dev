import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart'; // Firestore 패키지
import 'package:provider/provider.dart';
import '../../../widgets/navigation/secondary_role_navigation.dart'; // 상단 내비게이션 바
import '../../../widgets/navigation/secondary_mini_navigation.dart'; // 하단 내비게이션 바
import 'user_management_pages/user_accounts.dart'; // UserAccounts 위젯 임포트
import '../../../widgets/container/user_custom_box.dart'; // UserCustomBox 위젯 임포트
import '../../../states/area_state.dart';

class UserManagement extends StatefulWidget {
  const UserManagement({Key? key}) : super(key: key);

  @override
  State<UserManagement> createState() => _UserManagementState();
}

class _UserManagementState extends State<UserManagement> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance; // Firestore 인스턴스
  final List<Map<String, String>> _users = []; // 사용자 데이터 저장
  final Map<String, bool> _selectedUsers = {}; // Firestore 문서 ID를 키로 사용하는 선택 상태 저장
  bool _isLoading = true; // 로딩 상태 관리

  // SecondaryMiniNavigation 아이콘 상태
  List<IconData> _navigationIcons = [
    Icons.question_mark,
    Icons.add,
    Icons.question_mark,
  ];

  /// Firestore에서 데이터 가져오기
  Future<void> _fetchUsers() async {
    try {
      final snapshot = await _firestore.collection('user_accounts').get();
      if (snapshot.docs.isEmpty) {
        setState(() {
          _users.clear();
          _selectedUsers.clear();
          _isLoading = false;
        });
        return;
      }

      final fetchedUsers = <Map<String, String>>[];
      final fetchedSelectedUsers = <String, bool>{};

      for (var doc in snapshot.docs) {
        final data = doc.data();
        final id = doc.id;

        fetchedUsers.add({
          'id': id,
          'name': data['name'] ?? '',
          'phone': data['phone'] ?? '',
          'email': data['email'] ?? '',
          'role': data['role'] ?? '',
          'area': data['area'] ?? '',
        });

        fetchedSelectedUsers[id] = data['isSelected'] == true;
      }

      setState(() {
        _users
          ..clear()
          ..addAll(fetchedUsers);
        _selectedUsers
          ..clear()
          ..addAll(fetchedSelectedUsers);
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error fetching users: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  /// Firestore에 사용자 추가 (문서 ID로 phone 사용)
  Future<void> _addUser(String name, String phone, String email, String role, String area) async {
    try {
      // phone과 area를 결합한 고유 ID 사용
      final docRef = _firestore.collection('user_accounts').doc('$phone-$area');
      await docRef.set({
        'name': name,
        'phone': phone,
        'email': email,
        'role': role,
        'area': area,
        'isSelected': false, // 초기 선택 상태
      });

      setState(() {
        _users.add({
          'id': '$phone-$area', // 고유 ID
          'name': name,
          'phone': phone,
          'email': email,
          'role': role,
          'area': area,
        });
        _selectedUsers['$phone-$area'] = false; // 초기 선택 상태
      });
    } catch (e) {
      debugPrint('Error adding user: $e');
    }
  }


  /// 선택 상태 토글 및 Firestore 업데이트
  Future<void> _toggleSelection(String id) async {
    final currentState = _selectedUsers[id] ?? false;
    try {
      await _firestore.collection('user_accounts').doc(id).update({
        'isSelected': !currentState,
      });
      setState(() {
        _selectedUsers[id] = !currentState;

        // SecondaryMiniNavigation 아이콘 변경
        if (_selectedUsers.containsValue(true)) {
          _navigationIcons = [Icons.lock, Icons.delete, Icons.edit];
        } else {
          _navigationIcons = [Icons.question_mark, Icons.add, Icons.question_mark];
        }
      });
    } catch (e) {
      debugPrint('Error toggling selection: $e');
    }
  }

  @override
  void initState() {
    super.initState();
    _fetchUsers(); // Firestore에서 초기 데이터 로드
  }

  @override
  Widget build(BuildContext context) {
    // 현재 선택된 지역 가져오기
    final currentArea = context.watch<AreaState>().currentArea;

    // 현재 지역과 일치하는 사용자만 필터링
    final filteredUsers = _users.where((user) => user['area'] == currentArea).toList();

    return Scaffold(
      appBar: const SecondaryRoleNavigation(), // 상단 내비게이션
      body: _isLoading
          ? const Center(child: CircularProgressIndicator()) // 로딩 중 표시
          : filteredUsers.isEmpty
              ? const Center(child: Text('No users in this area.')) // 지역에 사용자 없음 메시지
              : ListView.builder(
                  itemCount: filteredUsers.length,
                  itemBuilder: (context, index) {
                    final userContainer = filteredUsers[index];
                    final isSelected = _selectedUsers[userContainer['id']] ?? false;
                    return UserCustomBox(
                      topLeftText: userContainer['name']!,
                      topRightText: userContainer['email']!,
                      midLeftText: userContainer['role']!,
                      midCenterText: userContainer['phone']!,
                      midRightText: userContainer['area']!,
                      onTap: () => _toggleSelection(userContainer['id']!),
                      // 선택 상태 토글
                      backgroundColor: isSelected ? Colors.green : Colors.white, // 배경색 설정
                    );
                  },
                ),
      bottomNavigationBar: SecondaryMiniNavigation(
        icons: _navigationIcons, // 동적으로 변경되는 아이콘
        onIconTapped: (index) {
          final selectedIds = _selectedUsers.keys.where((id) => _selectedUsers[id] == true).toList();

          if (_navigationIcons[index] == Icons.add) {
            // Add 아이콘 동작
            showDialog(
              context: context,
              builder: (BuildContext dialogContext) {
                // Provider에서 현재 선택된 지역 가져오기
                final currentArea = Provider.of<AreaState>(dialogContext, listen: false).currentArea;

                return UserAccounts(
                  onSave: (name, phone, email, role, area) {
                    _addUser(name, phone, email, role, area);
                  },
                  areaValue: currentArea, // 동적으로 가져온 지역 값 전달
                );
              },
            );
          } else if (_navigationIcons[index] == Icons.delete && selectedIds.isNotEmpty) {
            // Delete 아이콘 동작
            for (final id in selectedIds) {
              _firestore.collection('user_accounts').doc(id).delete().then((_) {
                setState(() {
                  _users.removeWhere((user) => user['id'] == id);
                  _selectedUsers.remove(id);
                  _navigationIcons = [Icons.question_mark, Icons.add, Icons.question_mark];
                });
              }).catchError((error) {
                debugPrint('Error deleting user: $error');
              });
            }
          }
        },
      ),
    );
  }
}
