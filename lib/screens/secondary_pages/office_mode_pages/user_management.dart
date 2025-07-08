import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../models/user_model.dart';
import '../../../repositories/user/user_repository.dart';
import '../../../utils/snackbar_helper.dart';
import '../../../widgets/navigation/secondary_mini_navigation.dart';
import 'user_management_pages/user_setting.dart';
import '../../../states/user/user_state.dart';
import '../../../states/area/area_state.dart';

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

  TimeOfDay? _stringToTimeOfDay(String? timeString) {
    if (timeString == null || !timeString.contains(':')) return null;
    final parts = timeString.split(':');
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null || minute == null) return null;
    return TimeOfDay(hour: hour, minute: minute);
  }

  String formatTime(TimeOfDay? time) {
    if (time == null) return '--:--';
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  void buildUserDialog({
    required BuildContext context,
    required void Function(
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
      String? startTime,
      String? endTime,
      List<String> fixedHolidays,
    ) onSave,
    UserModel? initialUser,
  }) {
    final areaState = context.read<AreaState>();
    final currentArea = areaState.currentArea;
    final currentDivision = areaState.currentDivision;

    showDialog(
      context: context,
      builder: (context) => UserSetting(
        onSave: onSave,
        areaValue: currentArea,
        division: currentDivision,
        isEditMode: initialUser != null,
        initialUser: initialUser,
      ),
    );
  }

  List<IconData> getNavigationIcons(bool hasSelection) {
    return hasSelection ? [Icons.edit, Icons.delete] : [Icons.add];
  }

  void onIconTapped(BuildContext context, int index, UserState userState) async {
    final selectedId = userState.selectedUserId;

    if (index == 0 && selectedId == null) {
      // 새 계정 추가
      buildUserDialog(
        context: context,
        onSave: (
          name,
          phone,
          email,
          role,
          password,
          area,
          division,
          isWorking,
          isSaved,
          selectedArea,
          startTime,
          endTime,
          fixedHolidays,
        ) async {
          try {
            final englishName = await context.read<UserRepository>().getEnglishNameByArea(selectedArea, division);
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
              isSelected: false,
              isWorking: isWorking,
              isSaved: isSaved,
              startTime: _stringToTimeOfDay(startTime),
              endTime: _stringToTimeOfDay(endTime),
              fixedHolidays: fixedHolidays,
            );

            userState.addUserCard(newUser, onError: (msg) => showFailedSnackbar(context, msg));
          } catch (e) {
            showFailedSnackbar(context, '계정 생성 실패: $e');
          }
        },
      );
    } else if (index == 0 && selectedId != null) {
      // 선택된 계정 수정
      final selectedUser = userState.users.firstWhere((u) => u.id == selectedId);

      buildUserDialog(
        context: context,
        initialUser: selectedUser,
        onSave: (
          name,
          phone,
          email,
          role,
          password,
          area,
          division,
          isWorking,
          isSaved,
          selectedArea,
          startTime,
          endTime,
          fixedHolidays,
        ) async {
          try {
            final englishName = await context.read<UserRepository>().getEnglishNameByArea(selectedArea, division);
            final updatedUser = selectedUser.copyWith(
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
              isWorking: isWorking,
              isSaved: isSaved,
              startTime: _stringToTimeOfDay(startTime),
              endTime: _stringToTimeOfDay(endTime),
              fixedHolidays: fixedHolidays,
            );

            await userState.updateLoginUser(updatedUser);
          } catch (e) {
            showFailedSnackbar(context, '수정 실패: $e');
          }
        },
      );
    } else if (index == 1 && selectedId != null) {
      // 계정 삭제
      userState.deleteUserCard(
        [selectedId],
        onError: (msg) => showFailedSnackbar(context, msg),
      );
    } else {
      showFailedSnackbar(context, '선택된 계정이 없습니다.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final userState = context.watch<UserState>();
    final areaState = context.watch<AreaState>();
    final currentArea = areaState.currentArea;
    final currentDivision = areaState.currentDivision;

    final filteredUsers = userState.users.where((user) {
      return user.areas.contains(currentArea) && user.divisions.contains(currentDivision);
    }).toList();

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: Colors.black87,
        title: const Text('계정', style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: '새로고침',
            onPressed: () async {
              try {
                await userState.refreshUsersBySelectedAreaAndCache();
                showSuccessSnackbar(context, '목록이 새로고침되었습니다.');
              } catch (e) {
                showFailedSnackbar(context, '새로고침 실패: $e');
              }
            },
          ),
        ],
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
                    final isSelected = userState.selectedUserId == user.id;

                    return ListTile(
                      title: Text(user.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('이메일: ${user.email}'),
                          Text('출근: ${formatTime(user.startTime)} / 퇴근: ${formatTime(user.endTime)}'),
                          Text('역할: ${user.role}'),
                        ],
                      ),
                      trailing: isSelected ? const Icon(Icons.check_circle, color: Colors.green) : null,
                      selected: isSelected,
                      onTap: () => userState.toggleUserCard(user.id),
                    );
                  },
                ),
      bottomNavigationBar: SecondaryMiniNavigation(
        icons: getNavigationIcons(userState.selectedUserId != null),
        onIconTapped: (index) => onIconTapped(context, index, userState),
      ),
    );
  }
}
