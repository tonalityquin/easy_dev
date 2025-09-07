import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../models/user_model.dart';
import '../../../repositories/user/user_repository.dart';
import '../../../utils/snackbar_helper.dart';
import '../../../widgets/navigation/secondary_mini_navigation.dart';
import 'user_management_package/user_setting.dart';
import '../../../states/user/user_state.dart';
import '../../../states/area/area_state.dart';

/// Iterable 안전 확장: 조건에 맞는 첫 원소를 찾되 없으면 null
extension IterableX<T> on Iterable<T> {
  T? firstWhereOrNull(bool Function(T) test) {
    for (final e in this) {
      if (test(e)) return e;
    }
    return null;
  }
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
    if (timeString == null) return null;
    final parts = timeString.split(':');
    if (parts.length != 2) return null;
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null || minute == null) return null;
    if (hour < 0 || hour > 23 || minute < 0 || minute > 59) return null;
    return TimeOfDay(hour: hour, minute: minute);
  }

  String formatTime(TimeOfDay? time) {
    if (time == null) return '--:--';
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  void buildUserBottomSheet({
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
      String position,
    ) onSave,
    UserModel? initialUser,
  }) {
    final areaState = context.read<AreaState>();
    final currentArea = areaState.currentArea;
    final currentDivision = areaState.currentDivision;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetCtx) => Padding(
        padding: MediaQuery.of(sheetCtx).viewInsets, // ✅ sheetCtx 사용
        child: UserSettingBottomSheet(
          onSave: onSave,
          areaValue: currentArea,
          division: currentDivision,
          isEditMode: initialUser != null,
          initialUser: initialUser,
        ),
      ),
    );
  }

  List<IconData> getNavigationIcons(bool hasSelection) {
    return hasSelection ? [Icons.edit, Icons.delete] : [Icons.add];
  }

  Future<bool> _confirmDelete(BuildContext context) async {
    return await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('삭제 확인'),
            content: const Text('선택한 계정을 삭제하시겠습니까?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('취소'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('삭제'),
              ),
            ],
          ),
        ) ??
        false;
  }

  void onIconTapped(BuildContext context, int index, UserState userState) async {
    final selectedId = userState.selectedUserId;

    // 추가
    if (index == 0 && selectedId == null) {
      buildUserBottomSheet(
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
          position,
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
              position: position,
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

            userState.addUserCard(
              newUser,
              onError: (msg) => showFailedSnackbar(context, msg),
            );
          } catch (e) {
            if (!context.mounted) return;
            showFailedSnackbar(context, '계정 생성 실패: $e');
          }
        },
      );
      return;
    }

    // 수정
    if (index == 0 && selectedId != null) {
      final selectedUser = userState.users.firstWhereOrNull((u) => u.id == selectedId);
      if (selectedUser == null) {
        showFailedSnackbar(context, '선택된 계정을 찾지 못했습니다.');
        return;
      }

      buildUserBottomSheet(
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
          position,
        ) async {
          try {
            final englishName = await context.read<UserRepository>().getEnglishNameByArea(selectedArea, division);

            final updatedUser = selectedUser.copyWith(
              name: name,
              phone: phone,
              email: email,
              role: role,
              password: password,
              position: position,
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
            if (!context.mounted) return;
            showSuccessSnackbar(context, '수정되었습니다.');
          } catch (e) {
            if (!context.mounted) return;
            showFailedSnackbar(context, '수정 실패: $e');
          }
        },
      );
      return;
    }

    // 삭제
    if (index == 1 && selectedId != null) {
      final ok = await _confirmDelete(context);
      if (!ok) return;

      userState.deleteUserCard(
        [selectedId],
        onError: (msg) => showFailedSnackbar(context, msg),
      );
      return;
    }

    // 그 외
    showFailedSnackbar(context, '선택된 계정이 없습니다.');
  }

  @override
  Widget build(BuildContext context) {
    final userState = context.watch<UserState>();
    final areaState = context.watch<AreaState>();
    final currentArea = areaState.currentArea; // non-nullable 가정
    final currentDivision = areaState.currentDivision; // non-nullable 가정

    bool matches(UserModel u) {
      // non-nullable 가정: dead_null_aware_expression 경고 제거
      final areas = u.areas;
      final divisions = u.divisions;

      // unnecessary_null_comparison 경고 제거
      final areaOk = currentArea.isEmpty || areas.contains(currentArea);
      final divisionOk = currentDivision.isEmpty || divisions.contains(currentDivision);
      return areaOk && divisionOk;
    }

    final filteredUsers = userState.users.where(matches).toList();

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
                if (!context.mounted) return;
                showSuccessSnackbar(context, '목록이 새로고침되었습니다.');
              } catch (e) {
                if (!context.mounted) return;
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
                      key: ValueKey(user.id),
                      title: Text(
                        user.name,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('이메일: ${user.email}'),
                          Text('출근: ${formatTime(user.startTime)} / 퇴근: ${formatTime(user.endTime)}'),
                          Text('역할: ${user.role}'),
                          if (user.position?.isNotEmpty == true) Text('직책: ${user.position!}'),
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
