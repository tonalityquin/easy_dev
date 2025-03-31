import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../models/user_model.dart';
import '../../../utils/snackbar_helper.dart';
import '../../../widgets/navigation/secondary_role_navigation.dart';
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
  @override
  void initState() {
    super.initState();

    // UserState 초기화 (자동 로그인 및 실시간 유저 수신)
    Future.microtask(() {
      final userState = context.read<UserState>();
      userState.initialize();
    });
  }

  void buildAddUserDialog(
      BuildContext context,
      void Function(String, String, String, String, String, String, bool, bool) onSave,
      ) {
    final currentArea = Provider.of<AreaState>(context, listen: false).currentArea;
    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return UserSetting(
          onSave: onSave,
          areaValue: currentArea,
        );
      },
    );
  }

  List<IconData> getNavigationIcons(bool hasSelectedUsers) {
    return hasSelectedUsers ? [Icons.schedule, Icons.delete] : [Icons.add, Icons.work];
  }

  void onIconTapped(BuildContext context, int index, UserState userState) {
    final selectedIds = userState.selectedUsers.keys
        .where((id) => userState.selectedUsers[id] == true)
        .toList();

    if (index == 0) {
      buildAddUserDialog(context, (name, phone, email, role, area, password, isWorking, isSaved) {
        final newUser = UserModel(
          id: '$phone-$area',
          name: name,
          phone: phone,
          email: email,
          role: role,
          password: password,
          area: area,
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
      });
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
    final currentArea = context.watch<AreaState>().currentArea;
    final filteredUsers = userState.users
        .where((user) => user.area == currentArea)
        .toList();

    return Scaffold(
      appBar: const SecondaryRoleNavigation(),
      body: userState.isLoading
          ? const Center(child: CircularProgressIndicator())
          : filteredUsers.isEmpty
          ? const Center(child: Text('생성된 계정이 없습니다'))
          : ListView.builder(
        itemCount: filteredUsers.length,
        itemBuilder: (context, index) {
          final userContainer = filteredUsers[index];
          final isSelected = userState.selectedUsers[userContainer.id] ?? false;

          return UserCustomBox(
            topLeftText: userContainer.name,
            topRightText: userContainer.email,
            midLeftText: userContainer.role,
            midCenterText: userContainer.phone,
            midRightText: userContainer.area,
            onTap: () => userState.toggleUserCard(userContainer.id),
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
