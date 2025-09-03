import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../models/user_model.dart';
import '../../../models/tablet_model.dart';
import '../../../repositories/user/user_repository.dart';
import '../../../utils/snackbar_helper.dart';
import '../../../widgets/navigation/secondary_mini_navigation.dart';
import 'tablet_management_pages/tablet_setting.dart';
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

class TabletManagement extends StatefulWidget {
  const TabletManagement({super.key});

  @override
  State<TabletManagement> createState() => _TabletManagementState();
}

class _TabletManagementState extends State<TabletManagement> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // ✅ 태블릿 전용 초기 로드
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
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetCtx) => Padding(
        padding: MediaQuery.of(sheetCtx).viewInsets, // ✅ sheetCtx 사용
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
            handle,
            email,
            role,
            password,
            area,
            division,
            ) async {
          try {
            final englishName = await context.read<UserRepository>().getEnglishNameByArea(area, division);

            // 🔁 UserModel → TabletModel 로 생성
            final newTablet = TabletModel(
              id: '$handle-$area', // 문서 ID 관례: handle-한글지역
              name: name,
              handle: handle,
              email: email,
              role: role,
              password: password,
              position: null,      // 축소안: 직책 미사용
              areas: [area],
              divisions: [division],
              currentArea: area,
              selectedArea: area,  // 축소안: selectedArea = area
              englishSelectedAreaName: englishName ?? area,
              isSelected: false,
              isWorking: false,    // 기본값
              isSaved: false,      // 기본값
              startTime: null,     // 축소안
              endTime: null,       // 축소안
              fixedHolidays: const [], // 축소안
            );

            // ✅ tablet_accounts에 추가
            await userState.addTabletCard(
              newTablet,
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
            final englishName = await context.read<UserRepository>().getEnglishNameByArea(area, division);

            // ⚠️ 현재 예제에서는 UserModel로 업데이트(기존 로직 유지).
            // tablet_accounts 쪽으로도 업데이트하려면 userState에 updateTabletCard 추가 후 호출 권장.
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

      // ✅ tablet_accounts에서 삭제
      await userState.deleteTabletCard(
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
      final areas = u.areas;
      final divisions = u.divisions;
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
        title: const Text('태블릿 계정 관리', style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: '새로고침',
            onPressed: () async {
              try {
                // ✅ tablet_accounts 기준 새로고침
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
