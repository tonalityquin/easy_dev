import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../models/user_model.dart';
import '../../../repositories/user/user_repository.dart';
import '../../../utils/snackbar_helper.dart';
import '../../../widgets/navigation/secondary_mini_navigation.dart';
import 'user_management_pages/user_setting.dart';
import '../../../widgets/container/user_custom_box.dart';
import '../../../states/user/user_state.dart';
import '../../../states/area/spot_state.dart';

extension SafeFirst<T> on List<T> {
  T? get firstOrNull => isNotEmpty ? first : null;
}

class UserManagement extends StatefulWidget {
  const UserManagement({super.key});

  @override
  State<UserManagement> createState() => _UserManagementState();
}

class _UserManagementState extends State<UserManagement> {
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
      String selectedArea,
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

  void onIconTapped(BuildContext context, int index, UserState userState) async {
    final selectedIds = userState.selectedUsers.keys.where((id) => userState.selectedUsers[id] == true).toList();

    if (index == 0) {
      // 계정 추가
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
          String selectedArea,
        ) async {
          try {
            // Firestore에서 englishName 조회
            final englishName = await context.read<UserRepository>()
                .getEnglishNameByArea(selectedArea, division);

            final newUser = UserModel(
              id: '$phone-$area',
              name: name,
              phone: phone,
              email: email,
              role: role,
              password: password,
              areas: [area],
              divisions: [division],
              currentArea: area,
              selectedArea: selectedArea,
              englishSelectedAreaName: englishName ?? area,
              // ✅ 추가
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
          } catch (e) {
            showFailedSnackbar(context, '사용자 생성 중 오류: $e');
          }
        },
      );
    } else if (index == 1 && selectedIds.isNotEmpty) {
      // 삭제
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

    // ✅ 현재 지역 및 사업소에 속한 사용자만 필터링
    final filteredUsers = userState.users.where((user) {
      return user.areas.contains(currentArea) && user.divisions.contains(currentDivision);
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
              ? Center(
                  child:
                      userState.users.isEmpty ? const Text('전체 계정 데이터가 없습니다') : const Text('현재 지역/사업소에 해당하는 계정이 없습니다'),
                )
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
                      midRightText: user.areas.firstOrNull ?? '-',
                      onTap: () => userState.toggleUserCard(user.id),
                      isSelected: isSelected,
                      backgroundColor: isSelected ? Colors.green[100]! : Colors.white,
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
