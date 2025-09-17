// lib/screens/secondary_package/office_mode_package/tablet_management.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../models/user_model.dart';
import '../../../models/tablet_model.dart';
import '../../../repositories/user_repo_services/user_repository.dart';
import '../../../utils/snackbar_helper.dart';
// import '../../../widgets/navigation/secondary_mini_navigation.dart'; // ❌ 미사용
import 'tablet_management_package/tablet_setting.dart';
import '../../../states/user/user_state.dart';
import '../../../states/area/area_state.dart';

/// 서비스 로그인 카드와 동일 톤의 팔레트
class _SvcColors {
  static const base = Color(0xFF0D47A1);  // primary
  static const dark = Color(0xFF09367D);  // 텍스트/아이콘 진한 톤
  static const light = Color(0xFF5472D3); // 라이트 톤/수면 강조
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

class TabletManagement extends StatefulWidget {
  const TabletManagement({super.key});

  @override
  State<TabletManagement> createState() => _TabletManagementState();
}

class _TabletManagementState extends State<TabletManagement> {
  // ▼ 버튼 하단 여백(화면 하단으로부터 띄우는 높이) & 버튼 간격
  static const double _fabBottomGap = 48.0;
  static const double _fabSpacing = 10.0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // ✅ 태블릿 전용 초기 로드 (캐시 우선)
      context.read<UserState>().loadTabletsOnly();
    });
  }

  String formatTime(TimeOfDay? time) {
    if (time == null) return '--:--';
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  // UserModel ↔ TabletModel 변환 헬퍼 (UI는 Tablet*, 저장은 기존 UserState/UserModel 사용)
  TabletModel _toTabletModel(UserModel u) {
    return TabletModel(
      id: u.id,
      areas: List<String>.from(u.areas),
      currentArea: u.currentArea,
      divisions: List<String>.from(u.divisions),
      email: u.email,
      endTime: u.endTime,
      englishSelectedAreaName: u.englishSelectedAreaName,
      fixedHolidays: List<String>.from(u.fixedHolidays),
      isSaved: u.isSaved,
      isSelected: u.isSelected,
      isWorking: u.isWorking,
      name: u.name,
      password: u.password,
      handle: u.phone, // 기존 phone 값을 handle로 매핑
      position: u.position,
      role: u.role,
      selectedArea: u.selectedArea,
      startTime: u.startTime,
    );
  }

  void buildUserBottomSheet({
    required BuildContext context,
    required void Function(
        String name,
        String handle, // phone → handle
        String email,
        String role,
        String password,
        String area,
        String division,
        ) onSave,
    TabletModel? initialUser, // 하단시트는 TabletModel 사용
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
        child: TabletSettingBottomSheet(
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
            handle,
            email,
            role,
            password,
            area,
            division,
            ) async {
          try {
            final englishName = await context
                .read<UserRepository>()
                .getEnglishNameByArea(area, division);

            // 🔁 UserModel → TabletModel 로 생성
            final newTablet = TabletModel(
              id: '$handle-$area', // 문서 ID 관례: handle-한글지역
              name: name,
              handle: handle,
              email: email,
              role: role,
              password: password,
              position: null, // 축소안: 직책 미사용
              areas: [area],
              divisions: [division],
              currentArea: area,
              selectedArea: area, // 축소안: selectedArea = area
              englishSelectedAreaName: englishName ?? area,
              isSelected: false,
              isWorking: false, // 기본값
              isSaved: false, // 기본값
              startTime: null, // 축소안
              endTime: null, // 축소안
              fixedHolidays: const [], // 축소안
            );

            await userState.addTabletCard(
              newTablet,
              onError: (msg) => showFailedSnackbar(context, msg),
            );
            if (!context.mounted) return;
            showSuccessSnackbar(context, '태블릿 계정이 추가되었습니다.');
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
    userState.tabletUsers.firstWhereOrNull((u) => u.id == selectedId);
    if (selectedUser == null) {
      showFailedSnackbar(context, '선택된 계정을 찾지 못했습니다.');
      return;
    }

    // 하단시트는 TabletModel을 사용하므로 변환하여 전달
    final tabletInitial = _toTabletModel(selectedUser);

    buildUserBottomSheet(
      context: context,
      initialUser: tabletInitial,
      onSave: (
          name,
          handle,
          email,
          role,
          password,
          area,
          division,
          ) async {
        try {
          final englishName = await context
              .read<UserRepository>()
              .getEnglishNameByArea(area, division);

          final updatedUser = selectedUser.copyWith(
            name: name,
            phone: handle, // handle을 phone 필드에 저장(호환)
            email: email,
            role: role,
            password: password,
            areas: [area],
            divisions: [division],
            currentArea: area,
            selectedArea: area,
            englishSelectedAreaName: englishName ?? area,
          );

          await userState.updateLoginTablet(updatedUser);
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

    await userState.deleteTabletCard(
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
    final currentArea = areaState.currentArea;
    final currentDivision = areaState.currentDivision;

    bool matches(UserModel u) {
      final areas = u.areas;
      final divisions = u.divisions;
      final areaOk = currentArea.isEmpty || areas.contains(currentArea);
      final divisionOk = currentDivision.isEmpty || divisions.contains(currentDivision);
      return areaOk && divisionOk;
    }

    // ✅ 태블릿 전용 리스트 사용 (캐시 우선)
    final filteredTablets = userState.tabletUsers.where(matches).toList();
    final bool hasSelection = userState.selectedUserId != null;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: Colors.black87,
        title: const Text('태블릿 계정 관리', style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: '새로고침',
            onPressed: () async {
              try {
                // ✅ tablet_accounts 기준 새로고침 (네트워크 호출은 이때만)
                await userState.refreshTabletsBySelectedAreaAndCache();
                if (!context.mounted) return;
                showSuccessSnackbar(context, '목록이 새로고침되었습니다.');
              } catch (e) {
                if (!context.mounted) return;
                showFailedSnackbar(context, '새로고침 실패: $e');
              }
            },
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: Colors.black.withOpacity(0.06)),
        ),
      ),
      body: userState.isLoading
          ? const Center(child: CircularProgressIndicator())
          : filteredTablets.isEmpty
          ? Center(
        child: userState.tabletUsers.isEmpty
            ? const Text('전체 계정 데이터가 없습니다')
            : const Text('현재 지역/사업소에 해당하는 계정이 없습니다'),
      )
          : ListView.builder(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
        itemCount: filteredTablets.length,
        itemBuilder: (context, index) {
          final user = filteredTablets[index];
          final isSelected = userState.selectedUserId == user.id;

          return Card(
            color: Colors.white,
            elevation: 1,
            surfaceTintColor: _SvcColors.light,
            margin: const EdgeInsets.symmetric(vertical: 6),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(
                color: isSelected
                    ? _SvcColors.base.withOpacity(.25)
                    : Colors.black.withOpacity(.06),
              ),
            ),
            child: ListTile(
              key: ValueKey(user.id),
              leading: CircleAvatar(
                radius: 18,
                backgroundColor: _SvcColors.base,
                child: const Icon(Icons.tablet_mac_rounded,
                    size: 18, color: Colors.white),
              ),
              title: Text(
                user.name,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: _SvcColors.dark,
                ),
              ),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 4),
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
              trailing: isSelected
                  ? const Icon(Icons.check_circle,
                  color: _SvcColors.base)
                  : null,
              selected: isSelected,
              selectedTileColor:
              _SvcColors.light.withOpacity(.06), // 토널 하이라이트
              onTap: () => userState.toggleUserCard(user.id),
            ),
          );
        },
      ),

      // ▼ 현대적인 FAB 세트(알약형 ElevatedButton + 하단 여백으로 위치 조절)
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
    final cs = Theme.of(context).colorScheme;

    final ButtonStyle primaryStyle = ElevatedButton.styleFrom(
      backgroundColor: _SvcColors.base,     // 서비스 톤
      foregroundColor: Colors.white,        // 가독성 확보
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

        // ▼ 하단 여백: 버튼을 위로 띄우는 역할
        SizedBox(height: bottomGap),
      ],
    );
  }
}

/// 둥근 알약 형태의 현대적 버튼 래퍼 (ElevatedButton 기반)
class _ElevatedPillButton extends StatelessWidget {
  const _ElevatedPillButton({
    required this.child,
    required this.onPressed,
    required this.style,
    Key? key,
  }) : super(key: key);

  // ✅ const 생성자 대신 factory로 위임하여 상수 제약/에러 회피
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

/// 아이콘 + 라벨(간격/정렬 최적화)
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
