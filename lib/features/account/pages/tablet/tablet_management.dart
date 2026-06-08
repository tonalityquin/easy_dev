import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../shared/secondary/widgets/ops_console_widgets.dart';
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
  String _query = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<UserState>().loadTabletsOnly();
    });
  }

  void _clearSelection(UserState userState) {
    final id = userState.selectedUserId;
    if (id != null) {
      userState.toggleUserCard(id);
    }
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
            title: const Text('태블릿 삭제 확인'),
            content: const Text('선택한 태블릿 계정을 삭제하시겠습니까?'),
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
            final englishName = await context.read<UserRepository>().getEnglishNameByArea(area, division);
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

            await userState.addTabletCard(newTablet, onError: (_) {});
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

    final selectedUser = userState.tabletUsers.firstWhereOrNull((u) => u.id == selectedId);
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
          final englishName = await context.read<UserRepository>().getEnglishNameByArea(area, division);
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
    if (selectedId == null) return;

    final ok = await _confirmDelete(context);
    if (!ok) return;

    await userState.deleteTabletCard([selectedId], onError: (_) {});
    if (!context.mounted) return;
    _clearSelection(userState);
  }

  Future<void> _refresh(BuildContext context) async {
    final userState = context.read<UserState>();
    try {
      await userState.refreshTabletsBySelectedAreaAndCache();
      if (!context.mounted) return;
      _clearSelection(userState);
    } catch (_) {}
  }

  bool _matchesSearch(TabletModel tablet) {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return true;
    final haystack = <String>[
      tablet.name,
      tablet.handle,
      tablet.email,
      tablet.role,
      tablet.position ?? '',
      tablet.areas.join(' '),
      tablet.divisions.join(' '),
    ].join(' ').toLowerCase();
    return haystack.contains(q);
  }

  Widget _buildTabletRow(BuildContext context, UserState userState, TabletModel tablet) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final isSelected = userState.selectedUserId == tablet.id;
    final titleStyle = (tt.titleMedium ?? const TextStyle(fontSize: 16)).copyWith(
      color: cs.onSurface,
      fontWeight: FontWeight.w900,
      letterSpacing: -.15,
    );

    return InkWell(
      onTap: () => userState.toggleUserCard(tablet.id),
      borderRadius: BorderRadius.circular(16),
      child: OpsPanel(
        selected: isSelected,
        padding: EdgeInsets.zero,
        child: Row(
          children: [
            Container(
              width: 6,
              height: 118,
              decoration: BoxDecoration(
                color: cs.primary,
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
                      children: [
                        Expanded(child: Text(tablet.name.isEmpty ? tablet.handle : tablet.name, style: titleStyle, maxLines: 1, overflow: TextOverflow.ellipsis)),
                        const SizedBox(width: 8),
                        OpsStatusBadge(label: '태블릿', color: cs.primary, icon: Icons.tablet_mac_rounded),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      tablet.email.isEmpty ? '이메일 미등록' : tablet.email,
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
                        OpsInfoPill(text: tablet.handle.isEmpty ? '핸들 미등록' : tablet.handle, icon: Icons.alternate_email_rounded),
                        OpsInfoPill(text: tablet.role.isEmpty ? '역할 없음' : tablet.role, icon: Icons.verified_user_rounded),
                        if (tablet.divisions.isNotEmpty) OpsInfoPill(text: tablet.divisions.join(', '), icon: Icons.business_rounded),
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
                color: isSelected ? cs.primary : cs.onSurfaceVariant.withOpacity(.7),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCommandBar(BuildContext context, int visible, int total) {
    final cs = Theme.of(context).colorScheme;
    return OpsCommandPanel(
      children: [
        OpsSearchField(
          hint: '태블릿명 · 핸들 · 이메일 · 역할 검색',
          onChanged: (value) => setState(() => _query = value),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            OpsFilterChip(label: '$visible/$total', selected: false, icon: Icons.filter_alt_rounded, onSelected: () {}),
            IconButton.filledTonal(
              tooltip: '새로고침',
              onPressed: () => _refresh(context),
              icon: Icon(Icons.refresh_rounded, color: cs.primary),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildBottomBar(BuildContext context, bool hasSelection) {
    if (!hasSelection) {
      return OpsBottomActionBar(
        children: [
          Expanded(
            child: OpsActionButton(
              label: '태블릿 등록',
              icon: Icons.add_to_queue_rounded,
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
            label: '삭제',
            icon: Icons.delete_forever_rounded,
            onPressed: () => _handleDelete(context),
            danger: true,
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

    bool matchesScope(TabletModel tablet) {
      final areaOk = currentArea.isEmpty || tablet.areas.contains(currentArea);
      final divisionOk = currentDivision.isEmpty || tablet.divisions.contains(currentDivision);
      return areaOk && divisionOk;
    }

    final scopedTablets = userState.tabletUsers.where(matchesScope).toList();
    final visibleTablets = scopedTablets.where(_matchesSearch).toList();
    final hasSelection = userState.selectedUserId != null;
    final areaLabel = currentArea.isEmpty ? '지역 전체' : currentArea;

    return OpsConsoleScaffold(
      title: '태블릿 관리',
      icon: Icons.tablet_mac_rounded,
      areaLabel: areaLabel,
      loading: userState.isLoading,
      metrics: [
        OpsMetric(label: '전체', value: '${scopedTablets.length}', icon: Icons.tablet_mac_rounded, color: cs.onInverseSurface),
        OpsMetric(label: '표시', value: '${visibleTablets.length}', icon: Icons.visibility_rounded, color: cs.primary),
        OpsMetric(label: '선택', value: hasSelection ? '1' : '0', icon: Icons.touch_app_rounded, color: hasSelection ? cs.primary : cs.onInverseSurface),
        OpsMetric(label: '사업소', value: currentDivision.isEmpty ? '-' : currentDivision, icon: Icons.business_rounded, color: cs.primary),
      ],
      commandBar: _buildCommandBar(context, visibleTablets.length, scopedTablets.length),
      bottomBar: _buildBottomBar(context, hasSelection),
      body: userState.isLoading
          ? const SizedBox.shrink()
          : visibleTablets.isEmpty
              ? OpsEmptyState(
                  icon: Icons.tablet_mac_rounded,
                  title: scopedTablets.isEmpty ? '등록된 태블릿이 없습니다' : '검색 결과가 없습니다',
                  message: scopedTablets.isEmpty ? '현장 태블릿 계정을 등록해 구역별 운영 단말을 배정하세요.' : '검색어를 조정하세요.',
                  action: FilledButton.icon(
                    onPressed: () => _handlePrimaryAction(context),
                    icon: const Icon(Icons.add_to_queue_rounded),
                    label: const Text('태블릿 등록'),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
                  itemCount: visibleTablets.length,
                  itemBuilder: (context, index) => _buildTabletRow(context, userState, visibleTablets[index]),
                ),
    );
  }
}
