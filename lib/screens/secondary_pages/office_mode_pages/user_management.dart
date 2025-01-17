import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import '../../../widgets/navigation/secondary_role_navigation.dart';
import '../../../widgets/navigation/secondary_mini_navigation.dart';
import 'user_management_pages/user_accounts.dart';
import '../../../widgets/container/user_custom_box.dart';
import '../../../states/area_state.dart';

class UserManagement extends StatefulWidget {
  const UserManagement({Key? key}) : super(key: key);

  @override
  State<UserManagement> createState() => _UserManagementState();
}

class _UserManagementState extends State<UserManagement> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final List<Map<String, String>> _users = [];
  final Map<String, bool> _selectedUsers = {};
  bool _isLoading = true;

  List<IconData> _navigationIcons = [
    Icons.add,
    Icons.help_outline,
    Icons.settings,
  ];

  /// Firestore에서 데이터 가져오기
  Future<void> _fetchUsers() async {
    try {
      final snapshot = await _firestore.collection('user_accounts').get();

      if (!mounted) return; // State가 dispose된 경우 return

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

      if (!mounted) return;

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
      if (!mounted) return;

      setState(() {
        _isLoading = false;
      });
    }
  }

  /// Firestore에 사용자 추가
  Future<void> _addUser(String name, String phone, String email, String role, String area) async {
    try {
      final docRef = _firestore.collection('user_accounts').doc('$phone-$area');
      await docRef.set({
        'name': name,
        'phone': phone,
        'email': email,
        'role': role,
        'area': area,
        'isSelected': false,
      });

      if (!mounted) return;

      setState(() {
        _users.add({
          'id': '$phone-$area',
          'name': name,
          'phone': phone,
          'email': email,
          'role': role,
          'area': area,
        });
        _selectedUsers['$phone-$area'] = false;
      });
    } catch (e) {
      debugPrint('Error adding user: $e');
    }
  }

  /// 선택 상태 토글
  Future<void> _toggleSelection(String id) async {
    final currentState = _selectedUsers[id] ?? false;
    try {
      await _firestore.collection('user_accounts').doc(id).update({
        'isSelected': !currentState,
      });

      if (!mounted) return;

      setState(() {
        _selectedUsers[id] = !currentState;

        if (_selectedUsers.containsValue(true)) {
          _navigationIcons = [Icons.lock, Icons.delete, Icons.edit];
        } else {
          _navigationIcons = [Icons.add, Icons.help_outline, Icons.settings];
        }
      });
    } catch (e) {
      debugPrint('Error toggling selection: $e');
    }
  }

  @override
  void initState() {
    super.initState();
    _fetchUsers();
  }

  @override
  void dispose() {
    debugPrint('Disposing UserManagementState');
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final currentArea = context.watch<AreaState>().currentArea;

    final filteredUsers = _users.where((user) => user['area'] == currentArea).toList();

    return Scaffold(
      appBar: const SecondaryRoleNavigation(),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : filteredUsers.isEmpty
          ? const Center(child: Text('No users in this area.'))
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
            backgroundColor: isSelected ? Colors.green : Colors.white,
          );
        },
      ),
      bottomNavigationBar: SecondaryMiniNavigation(
        icons: _navigationIcons,
        onIconTapped: (index) {
          final selectedIds = _selectedUsers.keys.where((id) => _selectedUsers[id] == true).toList();

          if (_navigationIcons[index] == Icons.add) {
            showDialog(
              context: context,
              builder: (BuildContext dialogContext) {
                final currentArea = Provider.of<AreaState>(dialogContext, listen: false).currentArea;

                return UserAccounts(
                  onSave: (name, phone, email, role, area) {
                    _addUser(name, phone, email, role, area);
                  },
                  areaValue: currentArea,
                );
              },
            );
          } else if (_navigationIcons[index] == Icons.delete && selectedIds.isNotEmpty) {
            for (final id in selectedIds) {
              _firestore.collection('user_accounts').doc(id).delete().then((_) {
                if (!mounted) return;

                setState(() {
                  _users.removeWhere((user) => user['id'] == id);
                  _selectedUsers.remove(id);
                  _navigationIcons = [Icons.add, Icons.help_outline, Icons.settings];
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
