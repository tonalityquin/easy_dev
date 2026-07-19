import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../app/utils/status_dialog.dart';
import '../../../../design_system/prompt_ui/prompt_ui_components.dart';
import '../../../../design_system/prompt_ui/prompt_ui_overlays.dart';
import '../../../../shared/secondary/widgets/ops_console_dialogs.dart';
import '../../../../shared/secondary/widgets/ops_console_widgets.dart';
import '../../../dev/application/area_state.dart';
import '../../applications/user_state.dart';
import '../../domain/models/user/user_model.dart';
import '../../domain/repositories/user_repository.dart';
import 'sheets/user_setting.dart';

extension IterableX<T> on Iterable<T> {
  T? firstWhereOrNull(bool Function(T) test) {
    for (final e in this) {
      if (test(e)) return e;
    }
    return null;
  }
}

enum _UserStatusFilter { all, active, inactive }

class UserManagement extends StatefulWidget {
  const UserManagement({super.key});

  @override
  State<UserManagement> createState() => _UserManagementState();
}

class _UserManagementState extends State<UserManagement> {
  bool _isAccountManagementMode = false;
  String _query = '';
  _UserStatusFilter _statusFilter = _UserStatusFilter.all;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<UserState>().refreshUsersBySelectedAreaAndCache();
    });
  }

  Future<void> _refreshUsersForCurrentArea(BuildContext context) async {
    try {
      final userState = context.read<UserState>();
      await userState.refreshUsersBySelectedAreaAndCache();
      if (!context.mounted) return;
      _clearSelection(userState);
    } catch (_) {}
  }

  void _clearSelection(UserState userState) {
    final id = userState.selectedUserId;
    if (id != null) {
      userState.toggleUserCard(id);
    }
  }

  Future<void> _toggleAccountManagementMode(BuildContext context) async {
    final userState = context.read<UserState>();
    _clearSelection(userState);
    if (!mounted) return;
    setState(() {
      _isAccountManagementMode = !_isAccountManagementMode;
    });
  }

  String? _limitNumberFromMessage(String message) {
    final match = RegExp(r'최대\s*(\d+)').firstMatch(message);
    return match?.group(1);
  }

  Future<void> _showAccountFailureDialog(
    BuildContext context, {
    required String title,
    required String message,
    required String fallbackDescription,
  }) async {
    if (!context.mounted) return;

    final limit = _limitNumberFromMessage(message);
    String description = fallbackDescription;

    if (message.contains('활성화 제한')) {
      description = limit == null
          ? '선택한 지역의 활성 계정 한도에 도달했습니다. 기존 활성 계정을 비활성화하거나 리밋 설정에서 활성 한도를 늘린 뒤 다시 시도하세요.'
          : '선택한 지역의 활성 계정 한도에 도달했습니다. 활성 계정은 최대 ${limit}개까지만 사용할 수 있습니다. 기존 활성 계정을 비활성화하거나 리밋 설정에서 활성 한도를 늘린 뒤 다시 시도하세요.';
    } else if (message.contains('전체 계정 제한')) {
      description = limit == null
          ? '선택한 지역의 전체 계정 생성 한도에 도달했습니다. 기존 계정을 삭제하거나 리밋 설정에서 전체 한도를 늘린 뒤 다시 시도하세요.'
          : '선택한 지역의 전체 계정 생성 한도에 도달했습니다. 활성 계정과 비활성 계정을 합쳐 최대 ${limit}개까지만 생성할 수 있습니다. 기존 계정을 삭제하거나 리밋 설정에서 전체 한도를 늘린 뒤 다시 시도하세요.';
    }

    await StatusDialog.showFailure(
      context,
      title: title,
      description: description,
      usePromptUi: true,
    );
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

  Map<String, TimeOfDay?> _stringWeekMapToTimeMap(Map<String, String?> raw) {
    final out = <String, TimeOfDay?>{};
    for (final day in UserModel.weekdays) {
      out[day] = _stringToTimeOfDay(raw[day]);
    }
    return out;
  }

  TimeOfDay? _pickRepresentativeFromMap(Map<String, TimeOfDay?> map) {
    final todayIndex = DateTime.now().weekday - 1;
    if (todayIndex >= 0 && todayIndex < UserModel.weekdays.length) {
      final today = UserModel.weekdays[todayIndex];
      final todayValue = map[today];
      if (todayValue != null) {
        return todayValue;
      }
    }
    for (final day in UserModel.weekdays) {
      final value = map[day];
      if (value != null) {
        return value;
      }
    }
    return null;
  }


  List<String> _normalizeDayList(Iterable<String> raw) {
    final set = raw.map((value) => value.trim()).where((value) => value.isNotEmpty).toSet();
    return <String>[
      for (final day in UserModel.weekdays)
        if (set.contains(day)) day,
      for (final value in set)
        if (!UserModel.weekdays.contains(value)) value,
    ];
  }

  List<String> _normalizeBreakDaysForWorkingMap({
    required Iterable<String> breakDays,
    required Map<String, TimeOfDay?> startByWeekday,
    required Map<String, TimeOfDay?> endByWeekday,
  }) {
    final breakSet = _normalizeDayList(breakDays).toSet();
    return <String>[
      for (final day in UserModel.weekdays)
        if (breakSet.contains(day) && startByWeekday[day] != null && endByWeekday[day] != null) day,
    ];
  }

  String _maskName(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return '';
    final runes = trimmed.runes.toList();
    if (runes.length <= 1) return trimmed;
    final mask = List.filled(runes.length - 1, '*').join();
    return '${String.fromCharCode(runes.first)}$mask';
  }

  String _maskPhone(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return '';

    final digitMatches = RegExp(r'\d').allMatches(trimmed).toList();
    if (digitMatches.isEmpty) return trimmed;

    final maskIndexes = <int>{};
    if (digitMatches.length >= 8) {
      final start = ((digitMatches.length - 4) / 2).floor();
      for (var i = start; i < start + 4 && i < digitMatches.length; i++) {
        maskIndexes.add(digitMatches[i].start);
      }
    } else if (digitMatches.length <= 2) {
      for (final match in digitMatches) {
        maskIndexes.add(match.start);
      }
    } else {
      for (var i = 1; i < digitMatches.length - 1; i++) {
        maskIndexes.add(digitMatches[i].start);
      }
    }

    final buffer = StringBuffer();
    for (var i = 0; i < trimmed.length; i++) {
      buffer.write(maskIndexes.contains(i) ? '*' : trimmed[i]);
    }
    return buffer.toString();
  }

  void buildUserBottomSheet({
    required BuildContext context,
    required void Function(
      String name,
      String phone,
      String email,
      String role,
      List<String> modes,
      String password,
      String area,
      String division,
      bool isWorking,
      bool isSaved,
      String selectedArea,
      Map<String, String?> startTimeByWeekday,
      Map<String, String?> endTimeByWeekday,
      List<String> fixedHolidays,
      List<String> breakDays,
      String position,
    ) onSave,
    UserModel? initialUser,
  }) {
    final areaState = context.read<AreaState>();
    final currentArea = areaState.currentArea;
    final currentDivision = areaState.currentDivision;

    showPromptOverlayBottomSheet<void>(
      context: context,
      useSafeArea: true,
      builder: (sheetContext) => FractionallySizedBox(
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

  Future<bool> _confirmToggleActive(
    BuildContext context, {
    required bool toActive,
  }) {
    return showOpsConfirmDialog(
      context: context,
      title: toActive ? '활성화 확인' : '비활성화 확인',
      message: toActive
          ? '선택한 계정을 활성화하시겠습니까?'
          : '선택한 계정을 비활성화하시겠습니까?',
      confirmLabel: toActive ? '활성화' : '비활성화',
      icon: toActive
          ? Icons.play_circle_fill_rounded
          : Icons.pause_circle_filled_rounded,
      destructive: !toActive,
    );
  }

  Future<bool> _confirmDeleteUser(BuildContext context) {
    return showOpsConfirmDialog(
      context: context,
      title: '계정 삭제 확인',
      message: '선택한 계정을 삭제하시겠습니까? 삭제 후 복구할 수 없습니다.',
      confirmLabel: '삭제',
      icon: Icons.delete_forever_rounded,
      destructive: true,
    );
  }

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
          modes,
          password,
          area,
          division,
          isWorking,
          isSaved,
          selectedArea,
          startTimeByWeekday,
          endTimeByWeekday,
          fixedHolidays,
          breakDays,
          position,
        ) async {
          try {
            final englishName = await context.read<UserRepository>().getEnglishNameByArea(selectedArea, division);
            final parsedStartMap = _stringWeekMapToTimeMap(startTimeByWeekday);
            final parsedEndMap = _stringWeekMapToTimeMap(endTimeByWeekday);

            final newUser = UserModel(
              id: '$phone-$area',
              name: name,
              phone: phone,
              email: email,
              role: role,
              modes: modes,
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
              startTime: _pickRepresentativeFromMap(parsedStartMap),
              endTime: _pickRepresentativeFromMap(parsedEndMap),
              fixedHolidays: _normalizeDayList(fixedHolidays),
              breakDays: _normalizeBreakDaysForWorkingMap(
                breakDays: breakDays,
                startByWeekday: parsedStartMap,
                endByWeekday: parsedEndMap,
              ),
              startTimeByWeekday: parsedStartMap,
              endTimeByWeekday: parsedEndMap,
            );

            await userState.addUserCard(
              newUser,
              onError: (message) {
                _showAccountFailureDialog(
                  context,
                  title: '계정 생성 불가',
                  message: message,
                  fallbackDescription: '계정을 생성하는 중 문제가 발생했습니다. 입력값과 네트워크 상태를 확인한 뒤 다시 시도하세요.',
                );
              },
            );

            if (!context.mounted) return;
            _clearSelection(userState);
          } catch (_) {
            if (!context.mounted) return;
            _clearSelection(userState);
          }
        },
      );
      return;
    }

    final selectedUser = userState.users.firstWhereOrNull((u) => u.id == selectedId);
    if (selectedUser == null) {
      _clearSelection(userState);
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
        modes,
        password,
        area,
        division,
        isWorking,
        isSaved,
        selectedArea,
        startTimeByWeekday,
        endTimeByWeekday,
        fixedHolidays,
        breakDays,
        position,
      ) async {
        try {
          final englishName = await context.read<UserRepository>().getEnglishNameByArea(selectedArea, division);
          final parsedStartMap = _stringWeekMapToTimeMap(startTimeByWeekday);
          final parsedEndMap = _stringWeekMapToTimeMap(endTimeByWeekday);

          final updatedUser = selectedUser.copyWith(
            name: name,
            phone: phone,
            email: email,
            role: role,
            modes: modes,
            password: password,
            position: position,
            areas: [area],
            divisions: [division],
            currentArea: area,
            selectedArea: selectedArea,
            englishSelectedAreaName: englishName ?? area,
            isWorking: isWorking,
            isSaved: isSaved,
            startTime: _pickRepresentativeFromMap(parsedStartMap),
            endTime: _pickRepresentativeFromMap(parsedEndMap),
            fixedHolidays: _normalizeDayList(fixedHolidays),
            breakDays: _normalizeBreakDaysForWorkingMap(
              breakDays: breakDays,
              startByWeekday: parsedStartMap,
              endByWeekday: parsedEndMap,
            ),
            startTimeByWeekday: parsedStartMap,
            endTimeByWeekday: parsedEndMap,
          );

          await userState.updateUserCardAsAdmin(
            updatedUser,
            onError: (message) {
              _showAccountFailureDialog(
                context,
                title: '계정 저장 불가',
                message: message,
                fallbackDescription: '계정 정보를 저장하는 중 문제가 발생했습니다. 입력값과 네트워크 상태를 확인한 뒤 다시 시도하세요.',
              );
            },
          );

          if (!context.mounted) return;
        } catch (_) {
          if (!context.mounted) return;
        } finally {
          _clearSelection(userState);
        }
      },
    );
  }

  Future<void> _handleToggleActive(BuildContext context) async {
    final userState = context.read<UserState>();
    final selectedId = userState.selectedUserId;
    if (selectedId == null) return;

    final selectedUser = userState.users.firstWhereOrNull((u) => u.id == selectedId);
    if (selectedUser == null) {
      _clearSelection(userState);
      return;
    }

    final toActive = !selectedUser.isActive;
    final ok = await _confirmToggleActive(context, toActive: toActive);
    if (!ok) return;

    await userState.setSelectedUserActiveStatus(
      toActive,
      onError: (message) {
        _showAccountFailureDialog(
          context,
          title: toActive ? '계정 활성화 불가' : '계정 비활성화 불가',
          message: message,
          fallbackDescription: toActive
              ? '계정을 활성화하는 중 문제가 발생했습니다. 선택한 지역의 계정 제한과 네트워크 상태를 확인한 뒤 다시 시도하세요.'
              : '계정을 비활성화하는 중 문제가 발생했습니다. 네트워크 상태를 확인한 뒤 다시 시도하세요.',
        );
      },
    );

    if (!context.mounted) return;
    _clearSelection(userState);
  }

  Future<void> _handleDeleteSelectedUser(BuildContext context) async {
    final userState = context.read<UserState>();
    final selectedId = userState.selectedUserId;
    if (selectedId == null) return;

    final selectedUser = userState.users.firstWhereOrNull((u) => u.id == selectedId);
    if (selectedUser == null) {
      _clearSelection(userState);
      return;
    }

    final ok = await _confirmDeleteUser(context);
    if (!ok) return;

    await userState.deleteUserCard(
      [selectedId],
      onError: (_) {},
    );

    if (!context.mounted) return;
    _clearSelection(userState);
  }

  bool _matchesSearch(UserModel user) {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return true;
    final haystack = <String>[
      user.name,
      user.phone,
      user.email,
      user.role,
      user.position ?? '',
      user.modes.join(' '),
      user.areas.join(' '),
      user.divisions.join(' '),
    ].join(' ').toLowerCase();
    return haystack.contains(q);
  }

  bool _matchesStatus(UserModel user) {
    switch (_statusFilter) {
      case _UserStatusFilter.all:
        return true;
      case _UserStatusFilter.active:
        return user.isActive;
      case _UserStatusFilter.inactive:
        return !user.isActive;
    }
  }

  Widget _buildUserRow(BuildContext context, UserState userState, UserModel user) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final isSelected = userState.selectedUserId == user.id;
    final statusColor = user.isActive ? cs.primary : cs.error;
    final modesText = user.modes.isNotEmpty ? user.modes.join(', ') : '모드 없음';
    final titleStyle = (tt.titleMedium ?? const TextStyle(fontSize: 16)).copyWith(
      fontWeight: FontWeight.w900,
      color: cs.onSurface,
      letterSpacing: -.15,
    );

    return InkWell(
      onTap: () => userState.toggleUserCard(user.id),
      borderRadius: BorderRadius.circular(16),
      child: OpsPanel(
        selected: isSelected,
        accentColor: statusColor,
        padding: EdgeInsets.zero,
        child: Row(
          children: [
            Container(
              width: 6,
              height: 128,
              decoration: BoxDecoration(
                color: statusColor,
                borderRadius: const BorderRadius.horizontal(left: Radius.circular(16)),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: Text(_maskName(user.name), style: titleStyle, maxLines: 1, overflow: TextOverflow.ellipsis)),
                        const SizedBox(width: 8),
                        OpsStatusBadge(
                          label: user.isActive ? '활성' : '비활성',
                          color: statusColor,
                          icon: user.isActive ? Icons.check_circle_rounded : Icons.pause_circle_filled_rounded,
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      user.email.isEmpty ? '이메일 미등록' : user.email,
                      style: (tt.bodySmall ?? const TextStyle(fontSize: 12)).copyWith(
                        color: cs.onSurfaceVariant,
                        fontWeight: FontWeight.w800,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        OpsInfoPill(text: _maskPhone(user.phone).isEmpty ? '전화 미등록' : _maskPhone(user.phone), icon: Icons.phone_rounded),
                        OpsInfoPill(text: user.role.isEmpty ? '역할 없음' : user.role, icon: Icons.verified_user_rounded),
                        if (user.position?.isNotEmpty == true) OpsInfoPill(text: user.position!, icon: Icons.badge_rounded),
                        OpsInfoPill(text: modesText, icon: Icons.widgets_rounded),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Icon(
                isSelected ? Icons.check_circle_rounded : Icons.chevron_right_rounded,
                color: isSelected ? statusColor : cs.onSurfaceVariant.withOpacity(.7),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCommandBar(BuildContext context, int visible, int total) {
    return OpsCommandPanel(
      children: [
        OpsSearchField(
          hint: '이름 · 전화번호 · 이메일 · 역할 검색',
          onChanged: (value) => setState(() => _query = value),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            OpsFilterChip(
              label: '전체',
              selected: _statusFilter == _UserStatusFilter.all,
              icon: Icons.groups_rounded,
              onSelected: () => setState(() => _statusFilter = _UserStatusFilter.all),
            ),
            OpsFilterChip(
              label: '활성',
              selected: _statusFilter == _UserStatusFilter.active,
              icon: Icons.check_circle_rounded,
              onSelected: () => setState(() => _statusFilter = _UserStatusFilter.active),
            ),
            OpsFilterChip(
              label: '비활성',
              selected: _statusFilter == _UserStatusFilter.inactive,
              icon: Icons.pause_circle_rounded,
              onSelected: () => setState(() => _statusFilter = _UserStatusFilter.inactive),
            ),
            OpsFilterChip(
              label: _isAccountManagementMode ? '삭제 모드' : '운영 모드',
              selected: _isAccountManagementMode,
              icon: _isAccountManagementMode ? Icons.delete_sweep_rounded : Icons.admin_panel_settings_rounded,
              onSelected: () => _toggleAccountManagementMode(context),
            ),
            OpsFilterChip(
              label: '$visible/$total',
              selected: false,
              icon: Icons.filter_alt_rounded,
              onSelected: () {},
            ),
            PromptIconButton(
              icon: Icons.refresh_rounded,
              tooltip: '새로고침',
              onPressed: () => _refreshUsersForCurrentArea(context),
              haptic: PromptHaptic.selection,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildBottomBar(BuildContext context, bool hasSelection, bool selectedIsActive) {
    if (_isAccountManagementMode) {
      return OpsBottomActionBar(
        children: [
          Expanded(
            child: OpsActionButton(
              label: hasSelection ? '계정 삭제' : '삭제할 계정 선택',
              icon: Icons.delete_forever_rounded,
              onPressed: hasSelection ? () => _handleDeleteSelectedUser(context) : null,
              danger: true,
            ),
          ),
        ],
      );
    }

    if (!hasSelection) {
      return OpsBottomActionBar(
        children: [
          Expanded(
            child: OpsActionButton(
              label: '신규 계정 등록',
              icon: Icons.person_add_alt_1_rounded,
              onPressed: () => _handlePrimaryAction(context),
            ),
          ),
        ],
      );
    }

    return OpsBottomActionBar(
      children: [
        Expanded(
          child: OpsActionButton(
            label: '수정',
            icon: Icons.edit_rounded,
            onPressed: () => _handlePrimaryAction(context),
            tonal: true,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: OpsActionButton(
            label: selectedIsActive ? '비활성화' : '활성화',
            icon: selectedIsActive ? Icons.pause_circle_filled_rounded : Icons.play_circle_fill_rounded,
            onPressed: () => _handleToggleActive(context),
            danger: selectedIsActive,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final userState = context.watch<UserState>();
    final areaState = context.watch<AreaState>();
    final currentArea = areaState.currentArea.trim();
    final currentDivision = areaState.currentDivision.trim();

    bool inCurrentScope(UserModel u) {
      final areaOk = currentArea.isEmpty || u.areas.contains(currentArea);
      final divisionOk = currentDivision.isEmpty || u.divisions.contains(currentDivision);
      return areaOk && divisionOk;
    }

    final scopedUsers = userState.users.where(inCurrentScope).toList();
    final visibleUsers = scopedUsers.where(_matchesStatus).where(_matchesSearch).toList();
    final activeCount = scopedUsers.where((u) => u.isActive).length;
    final inactiveCount = scopedUsers.length - activeCount;
    final hasSelection = userState.selectedUserId != null;
    final selectedUser = hasSelection ? userState.users.firstWhereOrNull((u) => u.id == userState.selectedUserId) : null;
    final selectedIsActive = selectedUser?.isActive ?? true;
    final areaLabel = currentArea.isEmpty ? '지역 전체' : currentArea;

    return OpsConsoleScaffold(
      title: '유저 관리',
      icon: Icons.manage_accounts_rounded,
      areaLabel: areaLabel,
      loading: userState.isLoading,
      metrics: [
        OpsMetric(label: '전체', value: '${scopedUsers.length}', icon: Icons.groups_rounded, color: cs.onInverseSurface),
        OpsMetric(label: '활성', value: '$activeCount', icon: Icons.check_circle_rounded, color: cs.primary),
        OpsMetric(label: '비활성', value: '$inactiveCount', icon: Icons.pause_circle_rounded, color: cs.error),
        OpsMetric(label: '선택', value: hasSelection ? '1' : '0', icon: Icons.touch_app_rounded, color: hasSelection ? cs.primary : cs.onInverseSurface),
      ],
      commandBar: _buildCommandBar(context, visibleUsers.length, scopedUsers.length),
      bottomBar: _buildBottomBar(context, hasSelection, selectedIsActive),
      body: userState.isLoading
          ? const SizedBox.shrink()
          : visibleUsers.isEmpty
              ? OpsEmptyState(
                  icon: Icons.person_search_rounded,
                  title: scopedUsers.isEmpty ? '현재 범위에 계정이 없습니다' : '검색 결과가 없습니다',
                  message: scopedUsers.isEmpty ? '신규 계정을 등록하거나 지점/사업소 범위를 확인하세요.' : '검색어와 활성 상태 필터를 조정하세요.',
                  action: PromptButton(
                    label: '신규 계정 등록',
                    icon: Icons.person_add_alt_1_rounded,
                    onPressed: () => _handlePrimaryAction(context),
                    haptic: PromptHaptic.selection,
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
                  itemCount: visibleUsers.length,
                  itemBuilder: (context, index) => _buildUserRow(context, userState, visibleUsers[index]),
                ),
    );
  }
}
