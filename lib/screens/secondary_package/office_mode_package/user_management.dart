// lib/screens/secondary_package/office_mode_package/user_management.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../models/user_model.dart';
import '../../../repositories/user_repo_services/user_repository.dart';
import '../../../utils/snackbar_helper.dart';
// import '../../../widgets/navigation/secondary_mini_navigation.dart'; // ❌ 미사용
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
  // ▼ 버튼을 아래에서 얼마나 띄울지 조절(요구사항: 버튼 하단에 SizedBox로 높이 조절)
  static const double _fabBottomGap = 48.0; // 필요시 값만 바꿔 간편 조절
  static const double _fabSpacing = 10.0;   // 버튼간 간격

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<UserState>().loadUsersOnly();
    });
  }

  // ▼ 각 파일에 동일하게 두는 갱신 로직 (복제본)
  Future<void> _refreshUsersForCurrentArea(BuildContext context) async {
    try {
      final userState = context.read<UserState>();
      await userState.refreshUsersBySelectedAreaAndCache();
      if (!context.mounted) return;
      showSuccessSnackbar(context, '목록이 새로고침되었습니다.');
    } catch (e) {
      if (!context.mounted) return;
      showFailedSnackbar(context, '새로고침 실패: $e');
    }
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
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) => FractionallySizedBox(
        heightFactor: 1,
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

  /// ▼ 기존 onIconTapped() 로직을 FAB로 그대로 매핑
  /// - 선택 없음: index 0 → 추가
  /// - 선택 있음: index 0 → 수정, index 1 → 삭제
  Future<void> _handlePrimaryAction(BuildContext context) async {
    final userState = context.read<UserState>();
    final selectedId = userState.selectedUserId;

    // index 0: 추가 (선택 없음)
    if (selectedId == null) {
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
            final englishName = await context
                .read<UserRepository>()
                .getEnglishNameByArea(selectedArea, division);

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

            await userState.addUserCard(
              newUser,
              onError: (msg) => showFailedSnackbar(context, msg),
            );
            if (!context.mounted) return;
            showSuccessSnackbar(context, '계정이 추가되었습니다.');
          } catch (e) {
            if (!context.mounted) return;
            showFailedSnackbar(context, '계정 생성 실패: $e');
          }
        },
      );
      return;
    }

    // index 0: 수정 (선택 있음)
    final selectedUser =
    userState.users.firstWhereOrNull((u) => u.id == selectedId);
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
          final englishName = await context
              .read<UserRepository>()
              .getEnglishNameByArea(selectedArea, division);

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
  }

  Future<void> _handleDelete(BuildContext context) async {
    final userState = context.read<UserState>();
    final selectedId = userState.selectedUserId;
    if (selectedId == null) {
      showFailedSnackbar(context, '선택된 계정이 없습니다.');
      return;
    }

    final ok = await _confirmDelete(context);
    if (!ok) return;

    await userState.deleteUserCard(
      [selectedId],
      onError: (msg) => showFailedSnackbar(context, msg),
    );
    if (!context.mounted) return;
    showSuccessSnackbar(context, '삭제되었습니다.');
  }

  @override
  Widget build(BuildContext context) {
    final userState = context.watch<UserState>();
    final areaState = context.watch<AreaState>();
    final currentArea = areaState.currentArea; // non-nullable 가정
    final currentDivision = areaState.currentDivision; // non-nullable 가정

    bool matches(UserModel u) {
      final areas = u.areas;
      final divisions = u.divisions;
      final areaOk = currentArea.isEmpty || areas.contains(currentArea);
      final divisionOk = currentDivision.isEmpty || divisions.contains(currentDivision);
      return areaOk && divisionOk;
    }

    final filteredUsers = userState.users.where(matches).toList();
    final bool hasSelection = userState.selectedUserId != null;
    final cs = Theme.of(context).colorScheme;

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
            onPressed: () => _refreshUsersForCurrentArea(context),
          ),
        ],
      ),
      body: userState.isLoading
          ? const Center(child: CircularProgressIndicator())
          : filteredUsers.isEmpty
          ? Center(
        child: userState.users.isEmpty
            ? const Text('전체 계정 데이터가 없습니다')
            : const Text('현재 지역/사업소에 해당하는 계정이 없습니다'),
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
            trailing: isSelected
                ? const Icon(Icons.check_circle, color: Colors.green)
                : null,
            selected: isSelected,
            onTap: () => userState.toggleUserCard(user.id),
          );
        },
      ),

      // ▼ 현대적인 FAB 세트(필 팁/그라운드 강조, StadiumBorder, 살짝 떠있는 느낌)
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      floatingActionButton: _FabStack(
        bottomGap: _fabBottomGap,
        spacing: _fabSpacing,
        hasSelection: hasSelection,
        onPrimary: () => _handlePrimaryAction(context), // 추가/수정
        onDelete: hasSelection ? () => _handleDelete(context) : null, // 삭제
        cs: cs,
      ),
    );
  }
}

/// 현대적인 파브 세트(라운드 필 버튼 스타일 + 하단 spacer로 높이 조절)
class _FabStack extends StatelessWidget {
  const _FabStack({
    required this.bottomGap,
    required this.spacing,
    required this.hasSelection,
    required this.onPrimary,
    required this.onDelete,
    required this.cs,
  });

  final double bottomGap;
  final double spacing;
  final bool hasSelection;
  final VoidCallback onPrimary;     // 선택 없음: 추가 / 선택 있음: 수정
  final VoidCallback? onDelete;     // 선택 있음에서만 사용
  final ColorScheme cs;

  @override
  Widget build(BuildContext context) {
    final ButtonStyle primaryStyle = ElevatedButton.styleFrom(
      backgroundColor: hasSelection ? cs.primary : cs.primary, // 동일 톤 유지
      foregroundColor: cs.onPrimary,
      elevation: 3,
      shadowColor: cs.shadow.withOpacity(0.25),
      shape: const StadiumBorder(),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      textStyle: const TextStyle(fontWeight: FontWeight.w700),
    );

    final ButtonStyle deleteStyle = ElevatedButton.styleFrom(
      backgroundColor: cs.error,
      foregroundColor: cs.onError,
      elevation: 3,
      shadowColor: cs.error.withOpacity(0.35),
      shape: const StadiumBorder(),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      textStyle: const TextStyle(fontWeight: FontWeight.w700),
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (hasSelection) ...[
          // index 0 → 수정
          _ElevatedPillButton.icon(
            icon: Icons.edit,
            label: '수정',
            style: primaryStyle,
            onPressed: onPrimary,
          ),
          SizedBox(height: spacing),
          // index 1 → 삭제
          _ElevatedPillButton.icon(
            icon: Icons.delete,
            label: '삭제',
            style: deleteStyle,
            onPressed: onDelete!,
          ),
        ] else ...[
          // index 0 → 추가
          _ElevatedPillButton.icon(
            icon: Icons.add,
            label: '추가',
            style: primaryStyle,
            onPressed: onPrimary,
          ),
        ],

        // ▼ 하단 여백: 버튼을 위로 띄우는 역할(요구사항)
        SizedBox(height: bottomGap),
      ],
    );
  }
}
class _ElevatedPillButton extends StatelessWidget {
  const _ElevatedPillButton({
    required this.child,
    required this.onPressed,
    required this.style,
    Key? key,
  }) : super(key: key);

  // ✅ const 제거 + factory로 위임 (상수 제약 해소)
  factory _ElevatedPillButton.icon({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
    required ButtonStyle style,
    Key? key,
  }) {
    return _ElevatedPillButton(
      key: key,
      onPressed: onPressed,
      style: style,
      child: _FabLabel(icon: icon, label: label),
    );
  }

  final Widget child;
  final VoidCallback onPressed;
  final ButtonStyle style;

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: onPressed,
      style: style,
      child: child,
    );
  }
}

class _FabLabel extends StatelessWidget {
  const _FabLabel({required this.icon, required this.label, Key? key}) : super(key: key);
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 20),
        const SizedBox(width: 8),
        Text(label),
      ],
    );
  }
}

