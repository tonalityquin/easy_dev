import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../../app/utils/developer_operation_status_dialog.dart';
import '../../../../app/utils/status_dialog.dart';
import '../../../../design_system/common_ui/common_ui_components.dart';
import '../../../../design_system/common_ui/common_ui_overlays.dart';
import '../../../../design_system/common_ui/common_ui_theme.dart';
import '../../../../shared/secondary/application/secondary_account_workspace_state.dart';
import '../../../../shared/secondary/widgets/ops_console_dialogs.dart';
import '../../../../shared/secondary/widgets/ops_console_widgets.dart';
import '../../../dev/application/area_state.dart';
import '../../applications/user_state.dart';
import '../../domain/models/tablet/tablet_model.dart';
import '../../domain/repositories/user_repository.dart';
import 'sheets/tablet_setting.dart';

enum _TabletStatusFilter { all, working, offline }

class TabletManagement extends StatefulWidget {
  const TabletManagement({super.key});

  @override
  State<TabletManagement> createState() => _TabletManagementState();
}

class _TabletManagementState extends State<TabletManagement> {
  final TextEditingController _searchController = TextEditingController();
  SecondaryAccountWorkspaceState? _workspaceState;
  String _query = '';
  _TabletStatusFilter _statusFilter = _TabletStatusFilter.all;
  bool _refreshing = false;
  bool _selectionClearScheduled = false;

  void _log(String message) {
    final workspace = _workspaceState;
    if (workspace != null) {
      workspace.log('tablet_$message');
      return;
    }
    debugPrint('[TabletManagement] $message');
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_initialRefresh());
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_workspaceState != null) return;
    _workspaceState = context.read<SecondaryAccountWorkspaceState>();
    _log('management_mounted');
  }

  @override
  void dispose() {
    _log('management_disposed');
    _searchController.dispose();
    super.dispose();
  }

  Future<DeveloperOperationTrace> _startTrace({
    required String title,
    required String initialMessage,
  }) {
    final rootContext = Navigator.of(context, rootNavigator: true).context;
    return DeveloperOperationTrace.start(
      context: rootContext,
      title: title,
      initialMessage: initialMessage,
      useCommonUi: true,
      developerModeMessage:
          '개발자 모드 ON: 태블릿 작업 상태와 debugPrint 코드를 확인하고 복사할 수 있습니다.',
      standardModeMessage:
          '개발자 모드 OFF: 상태 다이얼로그 없이 작업 로그를 콘솔에 기록합니다.',
    );
  }

  Future<void> _showFailure(
    BuildContext context, {
    required String title,
    required String description,
  }) async {
    if (!context.mounted) return;
    await StatusDialog.showFailure(
      context,
      title: title,
      description: description,
      useCommonUi: true,
    );
  }

  Future<void> _initialRefresh() async {
    final userState = context.read<UserState>();
    final areaState = context.read<AreaState>();
    final area = areaState.currentArea.trim();
    final division = areaState.currentDivision.trim();
    _log(
      'initial_refresh_started area=${area.isEmpty ? '-' : area} division=${division.isEmpty ? '-' : division}',
    );
    try {
      await userState.refreshTabletsBySelectedAreaAndCacheStrict();
      if (!mounted) return;
      _clearSelection(userState, reason: 'initial_refresh');
      _log('initial_refresh_completed count=${userState.tabletUsers.length}');
    } catch (error, stackTrace) {
      _log('initial_refresh_failed error=$error');
      debugPrint('[TabletManagement] initial_refresh_stack=$stackTrace');
    }
  }

  Future<void> _manualRefresh() async {
    if (_refreshing) return;
    final userState = context.read<UserState>();
    final areaState = context.read<AreaState>();
    final area = areaState.currentArea.trim();
    final division = areaState.currentDivision.trim();
    setState(() => _refreshing = true);
    _log(
      'refresh_started area=${area.isEmpty ? '-' : area} division=${division.isEmpty ? '-' : division}',
    );
    final trace = await _startTrace(
      title: '태블릿 데이터 새로고침',
      initialMessage: '현재 지역의 태블릿 데이터를 확인하고 있습니다.',
    );

    try {
      if (area.isEmpty) {
        throw StateError('현재 지역 정보가 없습니다.');
      }
      trace.log('현재 지역 확인 완료: area=$area, division=${division.isEmpty ? '-' : division}', progress: .16);
      trace.log('Firestore 태블릿 계정 조회를 시작합니다.', progress: .38);
      await userState.refreshTabletsBySelectedAreaAndCacheStrict();
      if (!mounted) return;
      _clearSelection(userState, reason: 'refresh');
      trace.log('태블릿 목록과 지역별 캐시 반영 완료', progress: .88);
      await trace.succeed('태블릿 데이터 새로고침 완료: ${userState.tabletUsers.length}개');
      if (!mounted) return;
      _log('refresh_completed count=${userState.tabletUsers.length}');
    } catch (error, stackTrace) {
      _log('refresh_failed error=$error');
      await trace.fail(
        '태블릿 데이터 새로고침에 실패했습니다.',
        error: error,
        stackTrace: stackTrace,
      );
      if (!trace.developerMode && mounted) {
        await _showFailure(
          context,
          title: '태블릿 새로고침 실패',
          description: '태블릿 데이터를 새로고침하는 중 문제가 발생했습니다. 현재 지역과 네트워크 상태를 확인한 뒤 다시 시도하세요.\n$error',
        );
      }
    } finally {
      if (mounted) {
        setState(() => _refreshing = false);
      }
    }
  }

  void _clearSelection(
    UserState userState, {
    String reason = 'manual',
  }) {
    final id = userState.selectedUserId;
    if (id == null) return;
    unawaited(userState.toggleUserCard(id));
    _log('selection_cleared reason=$reason id=$id');
  }

  void _setQuery(String value) {
    if (_query == value) return;
    setState(() => _query = value);
    _log('query_changed length=${value.trim().length}');
  }

  void _clearQuery() {
    if (_query.isEmpty && _searchController.text.isEmpty) return;
    _searchController.clear();
    setState(() => _query = '');
    _log('query_cleared');
  }

  void _setStatusFilter(_TabletStatusFilter filter) {
    if (_statusFilter == filter) return;
    HapticFeedback.selectionClick();
    setState(() => _statusFilter = filter);
    _log('status_filter_changed value=${filter.name}');
  }

  void _scheduleSelectionValidation(
    UserState userState,
    List<TabletModel> scopedTablets,
    List<TabletModel> visibleTablets,
  ) {
    final selectedId = userState.selectedUserId;
    if (selectedId == null) return;
    if (visibleTablets.any((tablet) => tablet.id == selectedId)) return;
    if (_selectionClearScheduled) return;
    _selectionClearScheduled = true;
    final inScope = scopedTablets.any((tablet) => tablet.id == selectedId);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _selectionClearScheduled = false;
      if (!mounted) return;
      final current = context.read<UserState>();
      if (current.selectedUserId != selectedId) return;
      _clearSelection(
        current,
        reason: inScope ? 'filtered_out' : 'scope_changed',
      );
    });
  }

  String _maskEmail(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return '';
    final parts = trimmed.split('@');
    if (parts.length != 2) return trimmed;
    final local = parts.first;
    final domain = parts.last;
    if (local.isEmpty) return trimmed;
    final visible = local.substring(0, 1);
    final maskLength = local.length <= 2 ? 2 : local.length - 1;
    return '$visible${List.filled(maskLength, '*').join()}@$domain';
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

  bool _matchesStatus(TabletModel tablet) {
    switch (_statusFilter) {
      case _TabletStatusFilter.all:
        return true;
      case _TabletStatusFilter.working:
        return tablet.isWorking;
      case _TabletStatusFilter.offline:
        return !tablet.isWorking;
    }
  }

  Future<void> _selectTablet(
    UserState userState,
    TabletModel tablet,
    SecondaryAccountMode mode,
  ) async {
    await HapticFeedback.selectionClick();
    final wasSelected = userState.selectedUserId == tablet.id;
    await userState.toggleUserCard(tablet.id);
    _log(
      '${wasSelected ? 'tablet_deselected' : 'tablet_selected'} handle=${tablet.handle} mode=${mode.name}',
    );
  }

  void _openTabletSetting({
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
    TabletModel? initialTablet,
  }) {
    final areaState = context.read<AreaState>();
    final currentArea = areaState.currentArea;
    final currentDivision = areaState.currentDivision;
    _log('form_opened mode=${initialTablet == null ? 'create' : 'edit'}');

    showCommonOverlayBottomSheet<void>(
      context: context,
      useSafeArea: true,
      builder: (sheetContext) => FractionallySizedBox(
        heightFactor: 1,
        child: TabletSettingBottomSheet(
          onSave: onSave,
          areaValue: currentArea,
          division: currentDivision,
          isEditMode: initialTablet != null,
          initialUser: initialTablet,
        ),
      ),
    );
  }

  Future<void> _handleCreate(BuildContext context) async {
    final userState = context.read<UserState>();
    _clearSelection(userState, reason: 'create_opened');
    _openTabletSetting(
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
        final trace = await _startTrace(
          title: '태블릿 등록',
          initialMessage: '태블릿 계정 등록 요청을 시작합니다.',
        );
        try {
          trace.log('입력값 확인 완료: name=$name, handle=$handle, role=$role', progress: .12);
          final englishName = await context.read<UserRepository>().getEnglishNameByArea(area, division);
          trace.log('지역 메타데이터 조회 완료: area=$area, division=$division', progress: .28);
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
          trace.log('태블릿 모델 구성 완료: Firestore 저장을 요청합니다.', progress: .55);
          String? saveError;
          await userState.addTabletCard(
            newTablet,
            onError: (message) {
              saveError = message;
            },
          );
          if (saveError != null) {
            trace.log('태블릿 등록 실패 응답: $saveError', progress: .9);
            await trace.fail('태블릿 등록에 실패했습니다.');
            if (!trace.developerMode && context.mounted) {
              await _showFailure(
                context,
                title: '태블릿 등록 실패',
                description: saveError!,
              );
            }
            return;
          }
          trace.log('Firestore 및 태블릿 캐시 반영 완료', progress: .92);
          await trace.succeed('태블릿 등록이 완료되었습니다.');
          _log('tablet_created handle=$handle');
        } catch (error, stackTrace) {
          _log('tablet_create_failed error=$error');
          await trace.fail(
            '태블릿 등록 중 예외가 발생했습니다.',
            error: error,
            stackTrace: stackTrace,
          );
          if (!trace.developerMode && context.mounted) {
            await _showFailure(
              context,
              title: '태블릿 등록 실패',
              description: '태블릿 계정을 등록하는 중 문제가 발생했습니다. 입력값과 네트워크 상태를 확인한 뒤 다시 시도하세요.\n$error',
            );
          }
        } finally {
          if (context.mounted) {
            _clearSelection(userState, reason: 'create_finished');
          }
        }
      },
    );
  }

  Future<void> _handleEdit(
    BuildContext context,
    TabletModel selectedTablet,
  ) async {
    final userState = context.read<UserState>();
    _openTabletSetting(
      context: context,
      initialTablet: selectedTablet,
      onSave: (
        name,
        handle,
        email,
        role,
        password,
        area,
        division,
      ) async {
        final trace = await _startTrace(
          title: '태블릿 수정',
          initialMessage: '태블릿 계정 수정 요청을 시작합니다.',
        );
        try {
          trace.log('수정 대상 확인: handle=${selectedTablet.handle}, id=${selectedTablet.id}', progress: .12);
          final englishName = await context.read<UserRepository>().getEnglishNameByArea(area, division);
          trace.log('지역 메타데이터 조회 완료: area=$area, division=$division', progress: .28);
          final updatedTablet = selectedTablet.copyWith(
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
          trace.log('수정 모델 구성 완료: Firestore 저장을 요청합니다.', progress: .56);
          String? saveError;
          final saved = await userState.updateTabletCardAsAdmin(
            updatedTablet,
            previousId: selectedTablet.id,
            onError: (message) {
              saveError = message;
            },
          );
          if (!saved) {
            final message = saveError ?? '태블릿 수정에 실패했습니다.';
            trace.log('태블릿 수정 실패 응답: $message', progress: .9);
            await trace.fail('태블릿 수정에 실패했습니다.');
            if (!trace.developerMode && context.mounted) {
              await _showFailure(
                context,
                title: '태블릿 수정 실패',
                description: message,
              );
            }
            return;
          }
          trace.log('Firestore 및 태블릿 캐시 반영 완료', progress: .92);
          await trace.succeed('태블릿 수정이 완료되었습니다.');
          _log('tablet_updated old=${selectedTablet.handle} new=$handle');
        } catch (error, stackTrace) {
          _log('tablet_update_failed error=$error');
          await trace.fail(
            '태블릿 수정 중 예외가 발생했습니다.',
            error: error,
            stackTrace: stackTrace,
          );
          if (!trace.developerMode && context.mounted) {
            await _showFailure(
              context,
              title: '태블릿 수정 실패',
              description: '태블릿 계정을 수정하는 중 문제가 발생했습니다. 입력값과 네트워크 상태를 확인한 뒤 다시 시도하세요.\n$error',
            );
          }
        } finally {
          if (context.mounted) {
            _clearSelection(userState, reason: 'edit_finished');
          }
        }
      },
    );
  }

  Future<bool> _confirmDelete(BuildContext context) {
    return showOpsConfirmDialog(
      context: context,
      title: '태블릿 삭제 확인',
      message: '선택한 태블릿 계정을 삭제하시겠습니까? 삭제 후 복구할 수 없습니다.',
      confirmLabel: '삭제',
      icon: Icons.delete_forever_rounded,
      destructive: true,
    );
  }

  Future<void> _handleDelete(
    BuildContext context,
    TabletModel selectedTablet,
  ) async {
    final userState = context.read<UserState>();
    _log('delete_confirm_opened handle=${selectedTablet.handle}');
    final ok = await _confirmDelete(context);
    if (!ok) {
      _log('delete_cancelled handle=${selectedTablet.handle}');
      return;
    }

    final trace = await _startTrace(
      title: '태블릿 삭제',
      initialMessage: '태블릿 계정 삭제 요청을 시작합니다.',
    );
    try {
      trace.log('삭제 대상 확인: handle=${selectedTablet.handle}, id=${selectedTablet.id}', progress: .2);
      trace.log('태블릿 계정 삭제와 캐시 갱신을 요청합니다.', progress: .5);
      String? deleteError;
      await userState.deleteTabletCard(
        [selectedTablet.id],
        onError: (message) {
          deleteError = message;
        },
      );
      if (deleteError != null) {
        trace.log('태블릿 삭제 실패 응답: $deleteError', progress: .9);
        await trace.fail('태블릿 삭제에 실패했습니다.');
        if (!trace.developerMode && context.mounted) {
          await _showFailure(
            context,
            title: '태블릿 삭제 실패',
            description: deleteError!,
          );
        }
        return;
      }
      trace.log('태블릿 삭제 및 캐시 반영 완료', progress: .92);
      await trace.succeed('태블릿 삭제가 완료되었습니다.');
      _log('delete_completed handle=${selectedTablet.handle}');
    } catch (error, stackTrace) {
      _log('delete_failed error=$error');
      await trace.fail(
        '태블릿 삭제 중 예외가 발생했습니다.',
        error: error,
        stackTrace: stackTrace,
      );
      if (!trace.developerMode && context.mounted) {
        await _showFailure(
          context,
          title: '태블릿 삭제 실패',
          description: '태블릿 계정을 삭제하는 중 문제가 발생했습니다. 네트워크 상태를 확인한 뒤 다시 시도하세요.\n$error',
        );
      }
    } finally {
      if (context.mounted) {
        _clearSelection(userState, reason: 'delete_finished');
      }
    }
  }

  Widget _buildToolbar(
    BuildContext context, {
    required bool refreshing,
    required bool deleteMode,
  }) {
    return Row(
      children: [
        Expanded(
          child: OpsDockSearchField(
            controller: _searchController,
            query: _query,
            semanticLabel: '태블릿 검색',
            onChanged: _setQuery,
            onClear: _clearQuery,
          ),
        ),
        const SizedBox(width: 6),
        CommonIconButton(
          icon: Icons.refresh_rounded,
          tooltip: '새로고침',
          onPressed: refreshing ? null : _manualRefresh,
          loading: refreshing,
          haptic: CommonHaptic.selection,
          size: 40,
          iconSize: 19,
        ),
        const SizedBox(width: 4),
        AnimatedOpacity(
          duration: MediaQuery.maybeOf(context)?.disableAnimations ?? false
              ? Duration.zero
              : CommonUiMotion.selection,
          opacity: deleteMode ? .34 : 1,
          child: CommonIconButton(
            icon: Icons.add_to_queue_rounded,
            tooltip: '태블릿 등록',
            onPressed: deleteMode ? null : () => _handleCreate(context),
            haptic: CommonHaptic.selection,
            size: 40,
            iconSize: 19,
          ),
        ),
      ],
    );
  }

  Widget _buildStatusSegments(
    BuildContext context, {
    required int totalCount,
    required int workingCount,
    required int offlineCount,
  }) {
    final tokens = CommonUiTheme.of(context);
    return OpsDockStatusSegments<_TabletStatusFilter>(
      selected: _statusFilter,
      items: [
        OpsDockStatusSegmentItem<_TabletStatusFilter>(
          value: _TabletStatusFilter.all,
          label: '전체',
          count: totalCount,
          color: tokens.accent,
        ),
        OpsDockStatusSegmentItem<_TabletStatusFilter>(
          value: _TabletStatusFilter.working,
          label: '운영 중',
          count: workingCount,
          color: tokens.statusSynchronized,
        ),
        OpsDockStatusSegmentItem<_TabletStatusFilter>(
          value: _TabletStatusFilter.offline,
          label: '오프라인',
          count: offlineCount,
          color: tokens.statusOffline,
        ),
      ],
      onSelected: _setStatusFilter,
    );
  }

  Widget _buildEmptyState(
    BuildContext context, {
    required bool scopedEmpty,
    required bool deleteMode,
  }) {
    final tokens = CommonUiTheme.of(context);
    final textTheme = Theme.of(context).textTheme;
    final queryActive = _query.trim().isNotEmpty;
    final filtered = _statusFilter != _TabletStatusFilter.all;
    final title = scopedEmpty
        ? '등록된 태블릿이 없습니다'
        : queryActive
            ? '일치하는 태블릿이 없습니다'
            : filtered
                ? '${_statusFilter == _TabletStatusFilter.working ? '운영 중인' : '오프라인'} 태블릿이 없습니다'
                : '표시할 태블릿이 없습니다';

    Widget? action;
    if (scopedEmpty && !deleteMode) {
      action = CommonButton(
        label: '태블릿 등록',
        icon: Icons.add_to_queue_rounded,
        onPressed: () => _handleCreate(context),
        haptic: CommonHaptic.selection,
        minHeight: 42,
      );
    } else if (queryActive) {
      action = CommonButton(
        label: '검색 초기화',
        icon: Icons.search_off_rounded,
        onPressed: _clearQuery,
        variant: CommonButtonVariant.secondary,
        haptic: CommonHaptic.selection,
        minHeight: 42,
      );
    } else if (filtered) {
      action = CommonButton(
        label: '전체 보기',
        icon: Icons.tablet_mac_rounded,
        onPressed: () => _setStatusFilter(_TabletStatusFilter.all),
        variant: CommonButtonVariant.secondary,
        haptic: CommonHaptic.selection,
        minHeight: 42,
      );
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: tokens.surfaceRaised,
                borderRadius: BorderRadius.circular(CommonUiShapes.control),
                border: Border.all(color: tokens.borderSubtle),
              ),
              alignment: Alignment.center,
              child: Icon(
                queryActive
                    ? Icons.tablet_android_rounded
                    : Icons.tablet_mac_rounded,
                color: tokens.iconSecondary,
                size: 22,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              title,
              textAlign: TextAlign.center,
              style: textTheme.bodyMedium?.copyWith(
                color: tokens.textPrimary,
                fontWeight: FontWeight.w800,
              ),
            ),
            if (action != null) ...[
              const SizedBox(height: 12),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 180),
                child: action,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildTabletList(
    BuildContext context, {
    required UserState userState,
    required List<TabletModel> tablets,
    required SecondaryAccountMode mode,
  }) {
    final tokens = CommonUiTheme.of(context);
    return OpsDockListSurface(
      child: ListView.separated(
        padding: EdgeInsets.zero,
        itemCount: tablets.length,
        separatorBuilder: (context, index) => Divider(
          height: 1,
          thickness: 1,
          color: tokens.borderSubtle,
        ),
        itemBuilder: (context, index) {
          final tablet = tablets[index];
          return _TabletDockRow(
            key: ValueKey<String>(tablet.id),
            name: tablet.name.trim().isEmpty ? tablet.handle : tablet.name,
            handle: tablet.handle,
            email: _maskEmail(tablet.email),
            role: tablet.role,
            division: tablet.divisions.join(', '),
            working: tablet.isWorking,
            selected: userState.selectedUserId == tablet.id,
            deleteMode: mode == SecondaryAccountMode.delete,
            onTap: () {
              unawaited(_selectTablet(userState, tablet, mode));
            },
          );
        },
      ),
    );
  }

  Widget _buildContextFooter(
    BuildContext context, {
    required TabletModel? selectedTablet,
    required SecondaryAccountMode mode,
  }) {
    if (selectedTablet == null) {
      return const SizedBox.shrink(key: ValueKey<String>('tablet_footer_none'));
    }

    if (mode == SecondaryAccountMode.delete) {
      return OpsDockContextFooter(
        key: const ValueKey<String>('tablet_footer_delete'),
        children: [
          Expanded(
            child: CommonButton(
              label: '태블릿 삭제',
              icon: Icons.delete_forever_rounded,
              onPressed: () => _handleDelete(context, selectedTablet),
              variant: CommonButtonVariant.destructive,
              haptic: CommonHaptic.medium,
              minHeight: 42,
              expand: true,
            ),
          ),
        ],
      );
    }

    return OpsDockContextFooter(
      key: const ValueKey<String>('tablet_footer_operation'),
      children: [
        Expanded(
          child: CommonButton(
            label: '수정',
            icon: Icons.edit_rounded,
            onPressed: () => _handleEdit(context, selectedTablet),
            variant: CommonButtonVariant.secondary,
            haptic: CommonHaptic.selection,
            minHeight: 42,
            expand: true,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final textTheme = Theme.of(context).textTheme;
    final media = MediaQuery.maybeOf(context);
    final reduceMotion = media?.disableAnimations ?? false;
    final userState = context.watch<UserState>();
    final areaState = context.watch<AreaState>();
    final workspace = context.watch<SecondaryAccountWorkspaceState>();
    final currentArea = areaState.currentArea.trim();
    final currentDivision = areaState.currentDivision.trim();

    bool matchesScope(TabletModel tablet) {
      final areaOk = currentArea.isEmpty || tablet.areas.contains(currentArea);
      final divisionOk =
          currentDivision.isEmpty || tablet.divisions.contains(currentDivision);
      return areaOk && divisionOk;
    }

    final scopedTablets = userState.tabletUsers.where(matchesScope).toList();
    final visibleTablets = scopedTablets
        .where(_matchesStatus)
        .where(_matchesSearch)
        .toList();
    final workingCount = scopedTablets.where((tablet) => tablet.isWorking).length;
    final offlineCount = scopedTablets.length - workingCount;
    final selectedTablet = visibleTablets.firstWhereOrNull(
      (tablet) => tablet.id == userState.selectedUserId,
    );
    final initialLoading = userState.isLoading && scopedTablets.isEmpty;
    final refreshing = _refreshing || (userState.isLoading && !initialLoading);
    final deleteMode = workspace.mode == SecondaryAccountMode.delete;

    _scheduleSelectionValidation(userState, scopedTablets, visibleTablets);

    final listBody = initialLoading
        ? const SizedBox.expand(key: ValueKey<String>('tablet_initial_loading'))
        : visibleTablets.isEmpty
            ? KeyedSubtree(
                key: ValueKey<String>(
                  'tablet_empty_${scopedTablets.isEmpty}_${_query.trim().isNotEmpty}_${_statusFilter.name}',
                ),
                child: _buildEmptyState(
                  context,
                  scopedEmpty: scopedTablets.isEmpty,
                  deleteMode: deleteMode,
                ),
              )
            : KeyedSubtree(
                key: ValueKey<String>(
                  'tablet_list_${_statusFilter.name}_${_query.trim().toLowerCase()}_${visibleTablets.length}',
                ),
                child: _buildTabletList(
                  context,
                  userState: userState,
                  tablets: visibleTablets,
                  mode: workspace.mode,
                ),
              );

    return Material(
      color: tokens.canvas,
      child: Stack(
        children: [
          Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 10, 10, 0),
                child: _buildToolbar(
                  context,
                  refreshing: refreshing,
                  deleteMode: deleteMode,
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 0),
                child: _buildStatusSegments(
                  context,
                  totalCount: scopedTablets.length,
                  workingCount: workingCount,
                  offlineCount: offlineCount,
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 7, 12, 7),
                child: Row(
                  children: [
                    Text(
                      _query.trim().isEmpty && _statusFilter == _TabletStatusFilter.all
                          ? '${visibleTablets.length}개 표시'
                          : '${visibleTablets.length}개 표시 · 전체 ${scopedTablets.length}개',
                      style: textTheme.labelSmall?.copyWith(
                        color: tokens.textSecondary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const Spacer(),
                    AnimatedSwitcher(
                      duration: reduceMotion
                          ? Duration.zero
                          : CommonUiMotion.selection,
                      transitionBuilder: (child, animation) => FadeTransition(
                        opacity: animation,
                        child: ScaleTransition(
                          scale: Tween<double>(begin: .96, end: 1).animate(animation),
                          child: child,
                        ),
                      ),
                      child: Icon(
                        deleteMode
                            ? Icons.delete_sweep_rounded
                            : Icons.tablet_mac_rounded,
                        key: ValueKey<SecondaryAccountMode>(workspace.mode),
                        size: 16,
                        color: deleteMode ? tokens.danger : tokens.success,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(10, 0, 10, 0),
                  child: OpsDockResultSwitcher(child: listBody),
                ),
              ),
              OpsDockContextFooterTransition(
                child: _buildContextFooter(
                  context,
                  selectedTablet: selectedTablet,
                  mode: workspace.mode,
                ),
              ),
            ],
          ),
          OpsDockLoadingOverlay(loading: initialLoading),
        ],
      ),
    );
  }
}

extension _TabletIterableX<T> on Iterable<T> {
  T? firstWhereOrNull(bool Function(T) test) {
    for (final item in this) {
      if (test(item)) return item;
    }
    return null;
  }
}

class _TabletDockRow extends StatelessWidget {
  const _TabletDockRow({
    super.key,
    required this.name,
    required this.handle,
    required this.email,
    required this.role,
    required this.division,
    required this.working,
    required this.selected,
    required this.deleteMode,
    required this.onTap,
  });

  final String name;
  final String handle;
  final String email;
  final String role;
  final String division;
  final bool working;
  final bool selected;
  final bool deleteMode;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final textTheme = Theme.of(context).textTheme;
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final selectionColor = deleteMode ? tokens.danger : tokens.accent;
    final selectedContainer =
        deleteMode ? tokens.dangerContainer : tokens.accentContainer;
    final statusColor =
        working ? tokens.statusSynchronized : tokens.statusOffline;
    final statusLabel = working ? '운영 중' : '오프라인';
    final displayHandle = handle.trim().isEmpty ? '핸들 없음' : handle.trim();
    final displayRole = role.trim().isEmpty ? '역할 없음' : role.trim();

    return OpsDockSelectableRowSurface(
      selected: selected,
      selectionColor: selectionColor,
      selectedContainer: selectedContainer,
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              AnimatedContainer(
                duration:
                    reduceMotion ? Duration.zero : CommonUiMotion.selection,
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: statusColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.bodyMedium?.copyWith(
                    color: tokens.textPrimary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                statusLabel,
                style: textTheme.labelSmall?.copyWith(
                  color: statusColor,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(width: 7),
              AnimatedSwitcher(
                duration:
                    reduceMotion ? Duration.zero : CommonUiMotion.selection,
                transitionBuilder: (child, animation) => FadeTransition(
                  opacity: animation,
                  child: ScaleTransition(
                    scale: Tween<double>(begin: .84, end: 1).animate(animation),
                    child: child,
                  ),
                ),
                child: Icon(
                  selected
                      ? Icons.check_circle_rounded
                      : Icons.chevron_right_rounded,
                  key: ValueKey<bool>(selected),
                  size: 19,
                  color: selected ? selectionColor : tokens.iconSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          Text(
            '$displayHandle · $displayRole',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: textTheme.bodySmall?.copyWith(
              color: tokens.textSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (selected) ...[
            const SizedBox(height: 9),
            Divider(
              height: 1,
              thickness: 1,
              color: tokens.borderSubtle,
            ),
            const SizedBox(height: 8),
            if (email.trim().isNotEmpty)
              Text(
                email,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: textTheme.labelSmall?.copyWith(
                  color: tokens.textSecondary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            if (email.trim().isNotEmpty && division.trim().isNotEmpty)
              const SizedBox(height: 4),
            if (division.trim().isNotEmpty)
              Text(
                division,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: textTheme.labelSmall?.copyWith(
                  color: tokens.textSecondary,
                  fontWeight: FontWeight.w700,
                ),
              ),
          ],
        ],
      ),
    );
  }
}
