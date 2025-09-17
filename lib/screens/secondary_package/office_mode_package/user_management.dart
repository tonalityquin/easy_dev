// lib/screens/secondary_package/office_mode_package/user_management.dart
//
// 색 반영(UI/UX 리팩터링):
// - '서비스 로그인' 카드 팔레트(#0D47A1 base / #09367D dark / #5472D3 light) 통일 적용
// - 상단 그라디언트 헤더 배너
// - 선택된 항목은 브랜드 톤으로 또렷하게 하이라이트(보더/배경/체크 아이콘)
// - FAB(추가/수정/삭제) 라운드 필 버튼 일관 스타일
// - 스낵바는 snackbar_helper 사용 (변경 없음)
// - 기능/로직은 기존과 동일

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../models/user_model.dart';
import '../../../repositories/user_repo_services/user_repository.dart';
import '../../../utils/snackbar_helper.dart';
import 'user_management_package/user_setting.dart';
import '../../../states/user/user_state.dart';
import '../../../states/area/area_state.dart';

/// 서비스 로그인 카드 팔레트 (일관된 브랜드 톤)
class _SvcColors {
  static const base = Color(0xFF0D47A1); // primary
  static const dark = Color(0xFF09367D); // 강조 텍스트/아이콘
  static const light = Color(0xFF5472D3); // 톤 변형/보더
  static const fg = Color(0xFFFFFFFF);
}

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
  static const double _fabSpacing = 10.0; // 버튼간 간격

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
        )
    onSave,
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

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: Colors.black87,
        title: const Text('계정', style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
        automaticallyImplyLeading: false,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: Colors.black.withOpacity(0.06)),
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
          ? const Center(child: CircularProgressIndicator())
          : filteredUsers.isEmpty
          ? Center(
        child: userState.users.isEmpty
            ? const Text('전체 계정 데이터가 없습니다')
            : const Text('현재 지역/사업소에 해당하는 계정이 없습니다'),
      )
          : ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        itemCount: filteredUsers.length + 1,
        itemBuilder: (context, index) {
          if (index == 0) const _HeaderBanner();
          if (index == 0) {
            return const _HeaderBanner();
          }

          final user = filteredUsers[index - 1];
          final isSelected = userState.selectedUserId == user.id;

          // 선택 시 브랜드 톤 하이라이트
          final bg = isSelected
              ? _SvcColors.light.withOpacity(.10)
              : Colors.white;
          final border = isSelected
              ? Border.all(color: _SvcColors.base, width: 1.25)
              : Border.all(color: Colors.black.withOpacity(.08));

          return Container(
            margin: const EdgeInsets.symmetric(vertical: 6),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(14),
              border: border,
            ),
            child: ListTile(
              key: ValueKey(user.id),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 10,
              ),
              leading: CircleAvatar(
                backgroundColor: _SvcColors.light.withOpacity(.25),
                foregroundColor: _SvcColors.dark,
                child: const Icon(Icons.person_outline),
              ),
              title: Row(
                children: [
                  Expanded(
                    child: Text(
                      user.name,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
                  ),
                  if (isSelected)
                    const Icon(Icons.check_circle,
                        color: _SvcColors.base),
                ],
              ),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('이메일: ${user.email}'),
                    Text(
                        '출근: ${formatTime(user.startTime)} / 퇴근: ${formatTime(user.endTime)}'),
                    Text('역할: ${user.role}'),
                    if (user.position?.isNotEmpty == true)
                      Text('직책: ${user.position!}'),
                  ],
                ),
              ),
              onTap: () => userState.toggleUserCard(user.id),
            ),
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
      ),
    );
  }
}

/// 상단 그라디언트 배너(브랜드 톤)
class _HeaderBanner extends StatelessWidget {
  const _HeaderBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            _SvcColors.light.withOpacity(.95),
            _SvcColors.base.withOpacity(.95),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _SvcColors.dark.withOpacity(.16)),
      ),
      child: Row(
        children: const [
          Icon(Icons.manage_accounts_rounded, color: _SvcColors.fg),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              '계정을 추가/수정/삭제할 수 있습니다.\n선택 시 항목이 강조 표시됩니다.',
              style: TextStyle(
                color: _SvcColors.fg,
                fontWeight: FontWeight.w700,
                height: 1.25,
              ),
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
    required this.onDelete,
  });

  final double bottomGap;
  final double spacing;
  final bool hasSelection;
  final VoidCallback onPrimary; // 선택 없음: 추가 / 선택 있음: 수정
  final VoidCallback? onDelete; // 선택 있음에서만 사용

  @override
  Widget build(BuildContext context) {
    final ButtonStyle primaryStyle = ElevatedButton.styleFrom(
      backgroundColor: _SvcColors.base,
      foregroundColor: _SvcColors.fg,
      elevation: 3,
      shadowColor: _SvcColors.base.withOpacity(0.25),
      shape: const StadiumBorder(),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      textStyle: const TextStyle(fontWeight: FontWeight.w700),
    );

    final ButtonStyle deleteStyle = ElevatedButton.styleFrom(
      backgroundColor: Theme.of(context).colorScheme.error,
      foregroundColor: Theme.of(context).colorScheme.onError,
      elevation: 3,
      shadowColor: Theme.of(context).colorScheme.error.withOpacity(0.35),
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
  const _FabLabel({required this.icon, required this.label, Key? key})
      : super(key: key);
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
