import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../models/user_model.dart';
import '../../../utils/snackbar_helper.dart';
import '../../../widgets/navigation/secondary_mini_navigation.dart';
import 'user_management_pages/user_setting.dart';
import '../../../widgets/container/user_custom_box.dart';
import '../../../states/user/user_state.dart';
import '../../../states/area/area_state.dart';

class UserManagement extends StatefulWidget {
  const UserManagement({super.key});

  @override
  State<UserManagement> createState() => _UserManagementState();
}

class _UserManagementState extends State<UserManagement> {
  // ✅ initialize() 호출 제거 – Document Mode와 동일하게 처리
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<UserState>().loadUsersOnly();
    });
  }

  void buildAddUserDialog(
    BuildContext context,
    void Function(
      String name,
      String phone,
      String email,
      String role,
      String password,
      String area,
      String division,
      bool isWorking,
      bool isSaved,
    ) onSave,
  ) {
    final areaState = context.read<AreaState>();
    final currentArea = areaState.currentArea;
    final currentDivision = areaState.currentDivision;

    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return UserSetting(
          onSave: onSave,
          areaValue: currentArea,
          division: currentDivision,
        );
      },
    );
  }

  List<IconData> getNavigationIcons(bool hasSelectedUsers) {
    return hasSelectedUsers ? [Icons.schedule, Icons.delete] : [Icons.add, Icons.work];
  }

  void onIconTapped(BuildContext context, int index, UserState userState) {
    final selectedIds = userState.selectedUsers.keys.where((id) => userState.selectedUsers[id] == true).toList();

    if (index == 0) {
      buildAddUserDialog(
        context,
        (
          String name,
          String phone,
          String email,
          String role,
          String password,
          String area,
          String division,
          bool isWorking,
          bool isSaved,
        ) {
          final newUser = UserModel(
            id: '$phone-$area',
            name: name,
            phone: phone,
            email: email,
            role: role,
            password: password,
            area: area,
            division: division,
            isSelected: false,
            isWorking: isWorking,
            isSaved: isSaved,
          );

          userState.addUserCard(
            newUser,
            onError: (errorMessage) {
              showFailedSnackbar(context, errorMessage);
            },
          );
        },
      );
    } else if (index == 1 && selectedIds.isNotEmpty) {
      userState.deleteUserCard(
        selectedIds,
        onError: (errorMessage) {
          showFailedSnackbar(context, errorMessage);
        },
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final userState = context.watch<UserState>();
    final areaState = context.watch<AreaState>();
    final currentArea = areaState.currentArea;
    final currentDivision = areaState.currentDivision;

    final filteredUsers = userState.users.where((user) {
      return user.area == currentArea && user.division == currentDivision;
    }).toList();

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: Colors.black87,
        title: const Text(
          '계정',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        automaticallyImplyLeading: false,
      ),
      body: userState.isLoading
          ? const Center(child: CircularProgressIndicator())
          : filteredUsers.isEmpty
              ? const Center(child: Text('생성된 계정이 없습니다'))
              : ListView.builder(
                  itemCount: filteredUsers.length,
                  itemBuilder: (context, index) {
                    final user = filteredUsers[index];
                    final isSelected = userState.selectedUsers[user.id] ?? false;

                    return UserCustomBox(
                      topLeftText: user.name,
                      topRightText: user.email,
                      midLeftText: user.role,
                      midCenterText: user.phone,
                      midRightText: user.area,
                      onTap: () => userState.toggleUserCard(user.id),
                      isSelected: isSelected,
                      backgroundColor: isSelected ? Colors.green : Colors.white,
                    );
                  },
                ),
      bottomNavigationBar: SecondaryMiniNavigation(
        icons: getNavigationIcons(userState.selectedUsers.containsValue(true)),
        onIconTapped: (index) => onIconTapped(context, index, userState),
      ),
    );
  }
}
