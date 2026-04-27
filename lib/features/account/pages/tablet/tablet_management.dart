import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../dev/application/area_state.dart';
import '../../applications/user_state.dart';
import '../../domain/models/tablet/tablet_model.dart';
import '../../domain/repositories/user_repository.dart';
import 'sheets/tablet_setting.dart';

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
  static const String screenTag = 'tablet management';
  static const double _fabBottomGap = 48.0;
  static const double _fabSpacing = 10.0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<UserState>().loadTabletsOnly();
    });
  }

  void _clearSelection(UserState userState) {
    final id = userState.selectedUserId;
    if (id != null) {
      userState.toggleUserCard(id);
    }
  }

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
              label: 'screen_tag: $screenTag',
              child: Text(screenTag, style: style),
            ),
          ),
        ),
      ),
    );
  }

  void buildUserBottomSheet({
    required BuildContext context,
    required void Function(
      String name,
      String handle,
      String email,
      String role,
      String password,
      String area,
      String division,
    ) onSave,
    TabletModel? initialUser,
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

  Future<void> _handlePrimaryAction(BuildContext context) async {
    final userState = context.read<UserState>();
    final selectedId = userState.selectedUserId;

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

            final newTablet = TabletModel(
              id: '$handle-$area',
              name: name,
              handle: handle,
              email: email,
              role: role,
              password: password,
              position: null,
              areas: [area],
              divisions: [division],
              currentArea: area,
              selectedArea: area,
              englishSelectedAreaName: englishName ?? area,
              isWorking: false,
              isSaved: false,
              fixedHolidays: const <String>[],
            );

            await userState.addTabletCard(
              newTablet,
              onError: (_) {},
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
        userState.tabletUsers.firstWhereOrNull((u) => u.id == selectedId);
    if (selectedUser == null) {
      _clearSelection(userState);
      return;
    }

    buildUserBottomSheet(
      context: context,
      initialUser: selectedUser,
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

          final updatedTablet = selectedUser.copyWith(
            id: '$handle-$area',
            name: name,
            handle: handle,
            email: email,
            role: role,
            password: password,
            areas: [area],
            divisions: [division],
            currentArea: area,
            selectedArea: area,
            englishSelectedAreaName: englishName ?? area,
          );

          await userState.updateTabletCardAsAdmin(
            updatedTablet,
            previousId: selectedUser.id,
            onError: (_) {},
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

  Future<void> _handleDelete(BuildContext context) async {
    final userState = context.read<UserState>();
    final selectedId = userState.selectedUserId;
    if (selectedId == null) {
      return;
    }

    final ok = await _confirmDelete(context);
    if (!ok) return;

    await userState.deleteTabletCard(
      [selectedId],
      onError: (_) {},
    );

    if (!context.mounted) return;
    _clearSelection(userState);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final userState = context.watch<UserState>();
    final areaState = context.watch<AreaState>();
    final currentArea = areaState.currentArea;
    final currentDivision = areaState.currentDivision;

    bool matches(TabletModel u) {
      final areas = u.areas;
      final divisions = u.divisions;
      final areaOk = currentArea.isEmpty || areas.contains(currentArea);
      final divisionOk =
          currentDivision.isEmpty || divisions.contains(currentDivision);
      return areaOk && divisionOk;
    }

    final filteredTablets = userState.tabletUsers.where(matches).toList();
    final bool hasSelection = userState.selectedUserId != null;

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        centerTitle: true,
        backgroundColor: cs.surface,
        foregroundColor: cs.onSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        flexibleSpace: _buildScreenTag(context),
        title: const Text('태블릿 계정 관리',
            style: TextStyle(fontWeight: FontWeight.bold)),
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: '새로고침',
            onPressed: () async {
              try {
                await userState.refreshTabletsBySelectedAreaAndCache();
                if (!context.mounted) return;
                _clearSelection(userState);
              } catch (_) {
                if (!context.mounted) return;
              }
            },
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child:
              Container(height: 1, color: cs.outlineVariant.withOpacity(.75)),
        ),
      ),
      body: userState.isLoading
          ? Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(cs.primary),
              ),
            )
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
                      color: cs.surface,
                      elevation: 1,
                      surfaceTintColor: Colors.transparent,
                      margin: const EdgeInsets.symmetric(vertical: 6),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(
                          color: isSelected
                              ? cs.primary.withOpacity(.25)
                              : cs.outlineVariant.withOpacity(.65),
                        ),
                      ),
                      child: ListTile(
                        key: ValueKey(user.id),
                        leading: CircleAvatar(
                          radius: 18,
                          backgroundColor: cs.primaryContainer.withOpacity(.65),
                          foregroundColor: cs.onPrimaryContainer,
                          child: const Icon(Icons.tablet_mac_rounded, size: 18),
                        ),
                        title: Text(
                          user.name,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: cs.onSurface,
                          ),
                        ),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: DefaultTextStyle(
                            style: TextStyle(
                                color: cs.onSurfaceVariant, height: 1.25),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('이메일: ${user.email}'),
                                Text('역할: ${user.role}'),
                                if (user.position?.isNotEmpty == true)
                                  Text('직책: ${user.position!}'),
                              ],
                            ),
                          ),
                        ),
                        trailing: isSelected
                            ? Icon(Icons.check_circle, color: cs.primary)
                            : null,
                        selected: isSelected,
                        selectedTileColor: cs.primaryContainer.withOpacity(.22),
                        onTap: () => userState.toggleUserCard(user.id),
                      ),
                    );
                  },
                ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      floatingActionButton: _FabStack(
        bottomGap: _fabBottomGap,
        spacing: _fabSpacing,
        hasSelection: hasSelection,
        onPrimary: () => _handlePrimaryAction(context),
        onDelete: hasSelection ? () => _handleDelete(context) : null,
      ),
    );
  }
}

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
  final VoidCallback onPrimary;
  final VoidCallback? onDelete;

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
          _ElevatedPillButton.icon(
            icon: Icons.edit,
            label: '수정',
            style: primaryStyle,
            onPressed: onPrimary,
          ),
          SizedBox(height: spacing),
          _ElevatedPillButton.icon(
            icon: Icons.delete,
            label: '삭제',
            style: deleteStyle,
            onPressed: onDelete!,
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
  const _FabLabel({
    required this.icon,
    required this.label,
  });

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18),
        const SizedBox(width: 8),
        Text(label),
      ],
    );
  }
}
