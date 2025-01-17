import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../widgets/navigation/secondary_role_navigation.dart';
import '../../../widgets/navigation/secondary_mini_navigation.dart';
import 'user_management_pages/user_accounts.dart';
import '../../../widgets/container/user_custom_box.dart';
import '../../../states/user_state.dart';
import '../../../states/area_state.dart';

class UserManagement extends StatelessWidget {
  const UserManagement({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final userState = context.watch<UserState>();
    final currentArea = context.watch<AreaState>().currentArea;

    final filteredUsers = userState.users.where((user) => user['area'] == currentArea).toList();

    return Scaffold(
      appBar: const SecondaryRoleNavigation(),
      body: userState.isLoading
          ? const Center(child: CircularProgressIndicator())
          : filteredUsers.isEmpty
              ? const Center(child: Text('No users in this area.'))
              : ListView.builder(
                  itemCount: filteredUsers.length,
                  itemBuilder: (context, index) {
                    final userContainer = filteredUsers[index];
                    final isSelected = userState.selectedUsers[userContainer['id']] ?? false;
                    return UserCustomBox(
                      topLeftText: userContainer['name']!,
                      topRightText: userContainer['email']!,
                      midLeftText: userContainer['role']!,
                      midCenterText: userContainer['phone']!,
                      midRightText: userContainer['area']!,
                      onTap: () => userState.toggleSelection(userContainer['id']!),
                      backgroundColor: isSelected ? Colors.green : Colors.white,
                    );
                  },
                ),
      bottomNavigationBar: SecondaryMiniNavigation(
        icons: userState.selectedUsers.containsValue(true)
            ? [Icons.lock, Icons.delete, Icons.edit]
            : [Icons.add, Icons.help_outline, Icons.settings],
        onIconTapped: (index) {
          final selectedIds = userState.selectedUsers.keys.where((id) => userState.selectedUsers[id] == true).toList();

          if (index == 0) {
            showDialog(
              context: context,
              builder: (BuildContext dialogContext) {
                final currentArea = Provider.of<AreaState>(dialogContext, listen: false).currentArea;

                return UserAccounts(
                  onSave: (name, phone, email, role, area) {
                    userState.addUser(name, phone, email, role, area);
                  },
                  areaValue: currentArea,
                );
              },
            );
          } else if (index == 1 && selectedIds.isNotEmpty) {
            userState.deleteUsers(selectedIds);
          }
        },
      ),
    );
  }
}
