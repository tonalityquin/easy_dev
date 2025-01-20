import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../widgets/navigation/secondary_role_navigation.dart';
import '../../../widgets/navigation/secondary_mini_navigation.dart';
import 'user_management_pages/user_accounts.dart';
import '../../../widgets/container/user_custom_box.dart';
import '../../../states/user_state.dart';
import '../../../states/area_state.dart';

/// 사용자 관리 화면
/// - 현재 지역에 속한 사용자 목록을 필터링하여 표시
/// - 사용자 추가, 삭제 및 선택 상태 관리
class UserManagement extends StatelessWidget {
  const UserManagement({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final userState = context.watch<UserState>(); // 사용자 상태 관리
    final currentArea = context.watch<AreaState>().currentArea; // 현재 선택된 지역

    // 현재 지역에 해당하는 사용자 필터링
    final filteredUsers = userState.users.where((user) => user['area'] == currentArea).toList();

    return Scaffold(
      appBar: const SecondaryRoleNavigation(), // 상단 내비게이션
      body: userState.isLoading
          ? const Center(child: CircularProgressIndicator()) // 로딩 상태 표시
          : filteredUsers.isEmpty
              ? const Center(child: Text('No users in this area.')) // 사용자가 없는 경우 메시지 표시
              : ListView.builder(
                  itemCount: filteredUsers.length,
                  itemBuilder: (context, index) {
                    final userContainer = filteredUsers[index];
                    final isSelected = userState.selectedUsers[userContainer['id']] ?? false;

                    return UserCustomBox(
                      topLeftText: userContainer['name']!,
                      // 사용자 이름
                      topRightText: userContainer['email']!,
                      // 이메일
                      midLeftText: userContainer['role']!,
                      // 역할
                      midCenterText: userContainer['phone']!,
                      // 전화번호
                      midRightText: userContainer['area']!,
                      // 지역
                      onTap: () => userState.toggleSelection(userContainer['id']!),
                      // 선택 상태 토글
                      backgroundColor: isSelected ? Colors.green : Colors.white, // 선택 여부에 따른 배경색
                    );
                  },
                ),
      bottomNavigationBar: SecondaryMiniNavigation(
        // 선택된 사용자가 있는지에 따라 다른 아이콘 표시
        icons: userState.selectedUsers.containsValue(true)
            ? [Icons.lock, Icons.delete, Icons.edit]
            : [Icons.add, Icons.help_outline, Icons.settings],
        onIconTapped: (index) {
          // 선택된 사용자 ID 목록
          final selectedIds = userState.selectedUsers.keys.where((id) => userState.selectedUsers[id] == true).toList();

          if (index == 0) {
            // 사용자 추가 다이얼로그 표시
            showDialog(
              context: context,
              builder: (BuildContext dialogContext) {
                final currentArea = Provider.of<AreaState>(dialogContext, listen: false).currentArea;

                return UserAccounts(
                  onSave: (name, phone, email, role, area) {
                    userState.addUser(name, phone, email, role, area); // 사용자 추가
                  },
                  areaValue: currentArea,
                );
              },
            );
          } else if (index == 1 && selectedIds.isNotEmpty) {
            // 선택된 사용자 삭제
            userState.deleteUsers(selectedIds);
          }
        },
      ),
    );
  }
}
