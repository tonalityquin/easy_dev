import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../app/utils/status_dialog.dart';
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

class _AccountSummary {
  const _AccountSummary({
    required this.activeCount,
    required this.inactiveCount,
    required this.totalLimit,
  });

  final int activeCount;
  final int inactiveCount;
  final int? totalLimit;

  int get totalCount => activeCount + inactiveCount;

  String get maxLabel => totalLimit == null ? '∞' : totalLimit.toString();

  String get compactLabel => '활성 $activeCount · 비활성 $inactiveCount · 전체 $totalCount · 최대 $maxLabel';
}

enum _UserMenuAction {
  refresh,
  accountManagement,
}

class UserManagement extends StatefulWidget {
  const UserManagement({super.key});

  @override
  State<UserManagement> createState() => _UserManagementState();
}

class _UserManagementState extends State<UserManagement> {
  static const double _fabBottomGap = 48.0;
  static const double _fabSpacing = 10.0;

  bool _isAccountManagementMode = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<UserState>().refreshUsersBySelectedAreaAndCache();
    });
  }

  Widget _buildScreenTag(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final base = Theme.of(context).textTheme.labelSmall;

    final style =
    (base ?? const TextStyle(fontSize: 11, fontWeight: FontWeight.w600))
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

  Future<bool> _confirmToggleActive(BuildContext context,
      {required bool toActive}) async {
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

  Future<bool> _confirmDeleteUser(BuildContext context) async {
    return await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('계정 삭제 확인'),
        content: const Text(
          '선택한 계정을 삭제하시겠습니까?\n삭제 후에는 user_accounts와 user_accounts_show의 해당 계정 문서가 제거됩니다.',
        ),
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
            position,
            ) async {
          try {
            final englishName = await context
                .read<UserRepository>()
                .getEnglishNameByArea(selectedArea, division);

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
              fixedHolidays: const <String>[],
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
                  fallbackDescription:
                      '계정을 생성하는 중 문제가 발생했습니다. 입력값과 네트워크 상태를 확인한 뒤 다시 시도하세요.',
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

    final selectedUser =
    userState.users.firstWhereOrNull((u) => u.id == selectedId);
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
          position,
          ) async {
        try {
          final englishName = await context
              .read<UserRepository>()
              .getEnglishNameByArea(selectedArea, division);

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
            fixedHolidays: const <String>[],
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
                fallbackDescription:
                    '계정 정보를 저장하는 중 문제가 발생했습니다. 입력값과 네트워크 상태를 확인한 뒤 다시 시도하세요.',
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
    if (selectedId == null) {
      return;
    }

    final selectedUser =
    userState.users.firstWhereOrNull((u) => u.id == selectedId);
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
    if (selectedId == null) {
      return;
    }

    final selectedUser =
    userState.users.firstWhereOrNull((u) => u.id == selectedId);
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

  Widget _buildUserTile(
      BuildContext context, UserState userState, UserModel user) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    final isSelected = userState.selectedUserId == user.id;
    final double inactiveOpacity = user.isActive ? 1.0 : 0.55;
    final bg = isSelected ? cs.primaryContainer.withOpacity(.35) : cs.surface;
    final border = isSelected
        ? Border.all(color: cs.primary, width: 1.25)
        : Border.all(color: cs.outlineVariant.withOpacity(.85));

    final modesText = (user.modes.isNotEmpty) ? user.modes.join(', ') : '-';

    final titleStyle =
    (tt.titleMedium ?? const TextStyle(fontSize: 16)).copyWith(
      fontWeight: FontWeight.w800,
      color: cs.onSurface,
    );

    final subtitleStyle =
    (tt.bodySmall ?? const TextStyle(fontSize: 12.5)).copyWith(
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
          contentPadding:
          const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          leading: CircleAvatar(
            backgroundColor: cs.primaryContainer.withOpacity(.55),
            foregroundColor: cs.onPrimaryContainer,
            child: const Icon(Icons.person_outline),
          ),
          title: Row(
            children: [
              Expanded(child: Text(_maskName(user.name), style: titleStyle)),
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
                  Text('전화번호: ${_maskPhone(user.phone)}'),
                  if (user.position?.isNotEmpty == true)
                    Text('직책: ${user.position!}'),
                  Text('허용 모드: $modesText'),
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
      final divisionOk =
          currentDivision.isEmpty || divisions.contains(currentDivision);
      return areaOk && divisionOk;
    }

    final filteredUsers = userState.users.where(matches).toList();
    final activeUsers = filteredUsers.where((u) => u.isActive).toList();
    final inactiveUsers = filteredUsers.where((u) => !u.isActive).toList();
    final bool needDivider = activeUsers.isNotEmpty && inactiveUsers.isNotEmpty;

    final bool hasSelection = userState.selectedUserId != null;

    final selectedUser = hasSelection
        ? userState.users
        .firstWhereOrNull((u) => u.id == userState.selectedUserId)
        : null;
    final bool selectedIsActive = selectedUser?.isActive ?? true;
    final String toggleLabel = selectedIsActive ? '비활성화' : '활성화';
    final IconData toggleIcon =
    selectedIsActive ? Icons.pause_circle : Icons.play_circle;

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
          child:
          Container(height: 1, color: cs.outlineVariant.withOpacity(.75)),
        ),
        actions: [
          PopupMenuButton<_UserMenuAction>(
            tooltip: '더보기',
            icon: const Icon(Icons.more_vert),
            onSelected: (value) async {
              switch (value) {
                case _UserMenuAction.refresh:
                  await _refreshUsersForCurrentArea(context);
                  break;
                case _UserMenuAction.accountManagement:
                  await _toggleAccountManagementMode(context);
                  break;
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem<_UserMenuAction>(
                value: _UserMenuAction.refresh,
                child: _MenuItemLabel(
                  icon: Icons.refresh,
                  label: '새로고침',
                ),
              ),
              PopupMenuItem<_UserMenuAction>(
                value: _UserMenuAction.accountManagement,
                child: _MenuItemLabel(
                  icon: _isAccountManagementMode
                      ? Icons.check_circle
                      : Icons.manage_accounts,
                  label: _isAccountManagementMode
                      ? '계정 관리 종료'
                      : '계정 관리',
                ),
              ),
            ],
          ),
        ],
      ),
      body: userState.isLoading
          ? Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(cs.primary),
        ),
      )
          : ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        itemCount: filteredUsers.isEmpty
            ? 2
            : 1 +
            activeUsers.length +
            (needDivider ? 1 : 0) +
            inactiveUsers.length,
        itemBuilder: (context, index) {
          if (index == 0) {
            return _HeaderBanner(
              currentDivision: currentDivision,
              currentArea: currentArea,
              fallbackActiveCount: activeUsers.length,
              fallbackInactiveCount: inactiveUsers.length,
              isAccountManagementMode: _isAccountManagementMode,
            );
          }

          if (filteredUsers.isEmpty) {
            return Padding(
              padding: const EdgeInsets.only(top: 96),
              child: Center(
                child: userState.users.isEmpty
                    ? const Text('전체 계정 데이터가 없습니다')
                    : const Text('현재 지역/사업소에 해당하는 계정이 없습니다'),
              ),
            );
          }

          var cursor = index - 1;

          if (cursor < activeUsers.length) {
            final user = activeUsers[cursor];
            return _buildUserTile(context, userState, user);
          }

          cursor -= activeUsers.length;

          if (needDivider) {
            if (cursor == 0) {
              return _buildActiveInactiveDivider(context);
            }
            cursor -= 1;
          }

          final user = inactiveUsers[cursor];
          return _buildUserTile(context, userState, user);
        },
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      floatingActionButton: _isAccountManagementMode
          ? (hasSelection
          ? _DeleteFab(
        bottomGap: _fabBottomGap,
        onDelete: () => _handleDeleteSelectedUser(context),
      )
          : null)
          : _FabStack(
        bottomGap: _fabBottomGap,
        spacing: _fabSpacing,
        hasSelection: hasSelection,
        onPrimary: () => _handlePrimaryAction(context),
        onSecondary:
        hasSelection ? () => _handleToggleActive(context) : null,
        secondaryLabel: toggleLabel,
        secondaryIcon: toggleIcon,
        secondaryIsDanger: selectedIsActive,
      ),
    );
  }
}

class _HeaderBanner extends StatelessWidget {
  const _HeaderBanner({
    required this.currentDivision,
    required this.currentArea,
    required this.fallbackActiveCount,
    required this.fallbackInactiveCount,
    required this.isAccountManagementMode,
  });

  final String currentDivision;
  final String currentArea;
  final int fallbackActiveCount;
  final int fallbackInactiveCount;
  final bool isAccountManagementMode;

  String _showDocId(String division, String area) {
    final d = division.trim().isEmpty ? 'unknownDivision' : division.trim();
    final a = area.trim().isEmpty ? 'unknownArea' : area.trim();
    return '$d-$a';
  }

  int? _asNonNegativeInt(dynamic value) {
    if (value is int && value >= 0) return value;
    if (value is num && value >= 0) return value.toInt();
    return null;
  }

  int? _asLimit(dynamic value) {
    if (value is int && value >= 0) return value;
    if (value is num && value >= 0) return value.toInt();
    return null;
  }

  Future<_AccountSummary> _loadSummary() async {
    if (currentDivision.trim().isEmpty || currentArea.trim().isEmpty) {
      return _AccountSummary(
        activeCount: fallbackActiveCount,
        inactiveCount: fallbackInactiveCount,
        totalLimit: null,
      );
    }

    try {
      final snap = await FirebaseFirestore.instance
          .collection('user_accounts_show')
          .doc(_showDocId(currentDivision, currentArea))
          .get(const GetOptions(source: Source.server));
      final data = snap.data();
      return _AccountSummary(
        activeCount: _asNonNegativeInt(data?['activeCount']) ?? fallbackActiveCount,
        inactiveCount: _asNonNegativeInt(data?['inactiveCount']) ?? fallbackInactiveCount,
        totalLimit: _asLimit(data?['totalLimit']),
      );
    } catch (_) {
      return _AccountSummary(
        activeCount: fallbackActiveCount,
        inactiveCount: fallbackInactiveCount,
        totalLimit: null,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    final titleStyle =
        (tt.titleSmall ?? const TextStyle(fontSize: 14)).copyWith(
      color: cs.onPrimaryContainer,
      fontWeight: FontWeight.w800,
      height: 1.25,
    );

    return FutureBuilder<_AccountSummary>(
      future: _loadSummary(),
      initialData: _AccountSummary(
        activeCount: fallbackActiveCount,
        inactiveCount: fallbackInactiveCount,
        totalLimit: null,
      ),
      builder: (context, snapshot) {
        final summary = snapshot.data ??
            _AccountSummary(
              activeCount: fallbackActiveCount,
              inactiveCount: fallbackInactiveCount,
              totalLimit: null,
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
                child: Icon(
                  isAccountManagementMode
                      ? Icons.delete_sweep_rounded
                      : Icons.manage_accounts_rounded,
                  color: cs.primary,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  summary.compactLabel,
                  style: titleStyle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _MenuItemLabel extends StatelessWidget {
  const _MenuItemLabel({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 20),
        const SizedBox(width: 12),
        Text(label),
      ],
    );
  }
}

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

class _DeleteFab extends StatelessWidget {
  const _DeleteFab({
    required this.bottomGap,
    required this.onDelete,
  });

  final double bottomGap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

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
        _ElevatedPillButton.icon(
          icon: Icons.delete_forever,
          label: '계정 삭제',
          style: deleteStyle,
          onPressed: onDelete,
        ),
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
