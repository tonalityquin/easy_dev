import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../models/user_model.dart';
import '../../../../repositories/user_repo_services/user_repository.dart';
import '../../../../utils/snackbar_helper.dart';
import 'user_management_package/user_setting.dart';
import '../../../../states/user/user_state.dart';
import '../../../../states/area/area_state.dart';

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
  static const double _fabBottomGap = 48.0;
  static const double _fabSpacing = 10.0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<UserState>().refreshUsersBySelectedAreaAndCache();
    });
  }

  // 좌측 상단(11시) 화면 태그: 'user management'
  Widget _buildScreenTag(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final base = Theme.of(context).textTheme.labelSmall;

    final style = (base ??
        const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ))
        .copyWith(
      color: cs.onSurfaceVariant.withOpacity(.72),
      fontWeight: FontWeight.w600,
      letterSpacing: 0.2,
    );

    return SafeArea(
      child: IgnorePointer(
        child: Align(
          alignment: Alignment.topLeft,
          child: Padding(
            padding: const EdgeInsets.only(left: 12, top: 4),
            child: Semantics(
              label: 'screen_tag: user management',
              child: Text('user management', style: style),
            ),
          ),
        ),
      ),
    );
  }

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
        List<String> modes, // ✅ 추가
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

  /// ✅ 삭제 대신: 활성/비활성 확인 다이얼로그
  Future<bool> _confirmToggleActive(BuildContext context, {required bool toActive}) async {
    final title = toActive ? '활성화 확인' : '비활성화 확인';
    final content = toActive ? '선택한 계정을 활성화하시겠습니까?' : '선택한 계정을 비활성화하시겠습니까?';
    final actionLabel = toActive ? '활성화' : '비활성화';

    return await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(actionLabel),
          ),
        ],
      ),
    ) ??
        false;
  }

  /// - 선택 없음: index 0 → 추가
  /// - 선택 있음: index 0 → 수정
  Future<void> _handlePrimaryAction(BuildContext context) async {
    final userState = context.read<UserState>();
    final selectedId = userState.selectedUserId;

    if (selectedId == null) {
      buildUserBottomSheet(
        context: context,
        onSave: (
            name,
            phone,
            email,
            role,
            modes, // ✅ 추가
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
              modes: modes, // ✅ 추가
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
          modes, // ✅ 추가
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
            modes: modes, // ✅ 추가
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

  /// ✅ 삭제 대신: 활성/비활성 토글 실행
  Future<void> _handleToggleActive(BuildContext context) async {
    final userState = context.read<UserState>();
    final selectedId = userState.selectedUserId;
    if (selectedId == null) {
      showFailedSnackbar(context, '선택된 계정이 없습니다.');
      return;
    }

    final selectedUser = userState.users.firstWhereOrNull((u) => u.id == selectedId);
    if (selectedUser == null) {
      showFailedSnackbar(context, '선택된 계정을 찾지 못했습니다.');
      return;
    }

    final toActive = !selectedUser.isActive;
    final ok = await _confirmToggleActive(context, toActive: toActive);
    if (!ok) return;

    await userState.setSelectedUserActiveStatus(
      toActive,
      onError: (msg) => showFailedSnackbar(context, msg),
    );

    if (!context.mounted) return;
    showSuccessSnackbar(context, toActive ? '활성화되었습니다.' : '비활성화되었습니다.');
  }

  Widget _buildUserTile(BuildContext context, UserState userState, UserModel user) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    final isSelected = userState.selectedUserId == user.id;

    // ✅ 비활성 계정은 시각적으로만 약간 낮춤
    final double inactiveOpacity = user.isActive ? 1.0 : 0.55;

    final bg = isSelected ? cs.primaryContainer.withOpacity(.35) : cs.surface;
    final border = isSelected
        ? Border.all(color: cs.primary, width: 1.25)
        : Border.all(color: cs.outlineVariant.withOpacity(.85));

    final modesText = (user.modes.isNotEmpty) ? user.modes.join(', ') : '-';

    final titleStyle = (tt.titleMedium ?? const TextStyle(fontSize: 16)).copyWith(
      fontWeight: FontWeight.w800,
      color: cs.onSurface,
    );

    final subtitleStyle = (tt.bodySmall ?? const TextStyle(fontSize: 12.5)).copyWith(
      color: cs.onSurfaceVariant,
      height: 1.25,
    );

    return Opacity(
      opacity: inactiveOpacity,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(14),
          border: border,
        ),
        child: ListTile(
          key: ValueKey(user.id),
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          leading: CircleAvatar(
            backgroundColor: cs.primaryContainer.withOpacity(.55),
            foregroundColor: cs.onPrimaryContainer,
            child: const Icon(Icons.person_outline),
          ),
          title: Row(
            children: [
              Expanded(child: Text(user.name, style: titleStyle)),
              if (isSelected) Icon(Icons.check_circle, color: cs.primary),
            ],
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 6),
            child: DefaultTextStyle(
              style: subtitleStyle,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('이메일: ${user.email}'),
                  Text('전화번호: ${user.phone}'),
                  if (user.position?.isNotEmpty == true) Text('직책: ${user.position!}'),
                  Text('허용 모드: $modesText'), // ✅ 표시 추가
                ],
              ),
            ),
          ),
          onTap: () => userState.toggleUserCard(user.id),
        ),
      ),
    );
  }

  Widget _buildActiveInactiveDivider(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 10, 2, 6),
      child: Divider(
        height: 18,
        thickness: 1.2,
        color: cs.outlineVariant.withOpacity(.85),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final userState = context.watch<UserState>();
    final areaState = context.watch<AreaState>();
    final currentArea = areaState.currentArea;
    final currentDivision = areaState.currentDivision;

    bool matches(UserModel u) {
      final areas = u.areas;
      final divisions = u.divisions;
      final areaOk = currentArea.isEmpty || areas.contains(currentArea);
      final divisionOk = currentDivision.isEmpty || divisions.contains(currentDivision);
      return areaOk && divisionOk;
    }

    final filteredUsers = userState.users.where(matches).toList();

    // ✅ 활성 상단 / 비활성 하단 분리
    final activeUsers = filteredUsers.where((u) => u.isActive).toList();
    final inactiveUsers = filteredUsers.where((u) => !u.isActive).toList();
    final bool needDivider = activeUsers.isNotEmpty && inactiveUsers.isNotEmpty;

    final bool hasSelection = userState.selectedUserId != null;

    final selectedUser = hasSelection ? userState.users.firstWhereOrNull((u) => u.id == userState.selectedUserId) : null;
    final bool selectedIsActive = selectedUser?.isActive ?? true;
    final String toggleLabel = selectedIsActive ? '비활성화' : '활성화';
    final IconData toggleIcon = selectedIsActive ? Icons.pause_circle : Icons.play_circle;

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        backgroundColor: cs.surface,
        foregroundColor: cs.onSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: const Text('계정', style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
        automaticallyImplyLeading: false,
        flexibleSpace: _buildScreenTag(context),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: cs.outlineVariant.withOpacity(.75)),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: '새로고침',
            onPressed: () => _refreshUsersForCurrentArea(context),
          ),
        ],
      ),
      body: userState.isLoading
          ? Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(cs.primary),
        ),
      )
          : filteredUsers.isEmpty
          ? Center(
        child: userState.users.isEmpty
            ? const Text('전체 계정 데이터가 없습니다')
            : const Text('현재 지역/사업소에 해당하는 계정이 없습니다'),
      )
          : ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        itemCount: 1 + activeUsers.length + (needDivider ? 1 : 0) + inactiveUsers.length,
        itemBuilder: (context, index) {
          if (index == 0) {
            return const _HeaderBanner();
          }

          var cursor = index - 1;

          if (cursor < activeUsers.length) {
            final user = activeUsers[cursor];
            return _buildUserTile(context, userState, user);
          }

          cursor -= activeUsers.length;

          if (needDivider) {
            if (cursor == 0) return _buildActiveInactiveDivider(context);
            cursor -= 1;
          }

          final user = inactiveUsers[cursor];
          return _buildUserTile(context, userState, user);
        },
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      floatingActionButton: _FabStack(
        bottomGap: _fabBottomGap,
        spacing: _fabSpacing,
        hasSelection: hasSelection,
        onPrimary: () => _handlePrimaryAction(context),
        onSecondary: hasSelection ? () => _handleToggleActive(context) : null,
        secondaryLabel: toggleLabel,
        secondaryIcon: toggleIcon,
        secondaryIsDanger: selectedIsActive,
      ),
    );
  }
}

/// 상단 배너(브랜드 톤) - ✅ 전역 ColorScheme 기반
class _HeaderBanner extends StatelessWidget {
  const _HeaderBanner();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    final titleStyle = (tt.titleSmall ?? const TextStyle(fontSize: 14)).copyWith(
      color: cs.onPrimaryContainer,
      fontWeight: FontWeight.w800,
      height: 1.25,
    );

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.primaryContainer.withOpacity(.60),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.outlineVariant.withOpacity(.85)),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: cs.primary.withOpacity(.12),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: cs.primary.withOpacity(.18)),
            ),
            child: Icon(Icons.manage_accounts_rounded, color: cs.primary),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '계정을 추가/수정/활성/비활성할 수 있습니다.\n선택 시 항목이 강조 표시됩니다.',
              style: titleStyle,
            ),
          ),
        ],
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
    required this.onSecondary,
    required this.secondaryLabel,
    required this.secondaryIcon,
    required this.secondaryIsDanger,
  });

  final double bottomGap;
  final double spacing;
  final bool hasSelection;

  final VoidCallback onPrimary;
  final VoidCallback? onSecondary;

  final String secondaryLabel;
  final IconData secondaryIcon;
  final bool secondaryIsDanger;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final ButtonStyle primaryStyle = ElevatedButton.styleFrom(
      backgroundColor: cs.primary,
      foregroundColor: cs.onPrimary,
      elevation: 3,
      shadowColor: cs.primary.withOpacity(0.25),
      shape: const StadiumBorder(),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      textStyle: const TextStyle(fontWeight: FontWeight.w700),
    );

    // ✅ 비활성화는 danger(에러), 활성화는 primary
    final Color secondaryBg = secondaryIsDanger ? cs.error : cs.primary;
    final Color secondaryFg = secondaryIsDanger ? cs.onError : cs.onPrimary;

    final ButtonStyle secondaryStyle = ElevatedButton.styleFrom(
      backgroundColor: secondaryBg,
      foregroundColor: secondaryFg,
      elevation: 3,
      shadowColor: secondaryBg.withOpacity(0.35),
      shape: const StadiumBorder(),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      textStyle: const TextStyle(fontWeight: FontWeight.w700),
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (hasSelection) ...[
          _ElevatedPillButton.icon(
            icon: Icons.edit,
            label: '수정',
            style: primaryStyle,
            onPressed: onPrimary,
          ),
          SizedBox(height: spacing),
          _ElevatedPillButton.icon(
            icon: secondaryIcon,
            label: secondaryLabel,
            style: secondaryStyle,
            onPressed: onSecondary!,
          ),
        ] else ...[
          _ElevatedPillButton.icon(
            icon: Icons.add,
            label: '추가',
            style: primaryStyle,
            onPressed: onPrimary,
          ),
        ],
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
