import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../app/utils/developer_operation_status_dialog.dart';
import '../../../app/utils/snackbar_helper.dart';
import '../../../design_system/common_ui/common_ui_components.dart';
import '../../../design_system/common_ui/common_ui_overlays.dart';
import '../../../design_system/common_ui/common_ui_theme.dart';
import '../../../shared/secondary/widgets/ops_console_dialogs.dart';
import '../../../shared/secondary/widgets/ops_console_widgets.dart';
import '../../../shared/secondary/widgets/secondary_debug_scope.dart';
import '../../dev/application/area_state.dart';
import '../applications/sector_state.dart';
import '../domain/models/sector_model.dart';
import 'sheets/sector_setting.dart';

class SectorManagement extends StatefulWidget {
  const SectorManagement({super.key});

  @override
  State<SectorManagement> createState() => _SectorManagementState();
}

class _SectorManagementState extends State<SectorManagement> {
  final TextEditingController _searchController = TextEditingController();
  String _query = '';
  bool _selectionValidationScheduled = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _log('mounted');
      unawaited(_initialRefresh());
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    debugPrint('[SectorManagement] disposed');
    super.dispose();
  }

  void _log(String message) {
    final output = 'sector_workspace $message';
    debugPrint('[SectorManagement] $message');
    if (!mounted) return;
    SecondaryDebugScope.maybeOf(context)?.call(output);
  }

  Future<void> _initialRefresh() async {
    final area = context.read<AreaState>().currentArea.trim();
    _log('initial_refresh_started area=${area.isEmpty ? '-' : area}');
    try {
      await context.read<SectorState>().manualSectorRefresh();
      if (!mounted) return;
      final count = context.read<SectorState>().sectors.length;
      _log('initial_refresh_completed count=$count');
    } catch (error, stackTrace) {
      _log('initial_refresh_failed error=$error');
      debugPrint('[SectorManagement] stackTrace=$stackTrace');
    }
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
          '개발자 모드 ON: 상태와 디버그 출력을 확인하고 복사할 수 있습니다.',
      standardModeMessage:
          '개발자 모드 OFF: 상태 다이얼로그 없이 작업을 실행합니다.',
    );
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

  Future<void> _manualRefresh() async {
    final area = context.read<AreaState>().currentArea.trim();
    _log('refresh_started area=${area.isEmpty ? '-' : area}');
    final trace = await _startTrace(
      title: '섹터 데이터 새로고침',
      initialMessage: '현재 지역의 섹터 데이터를 확인하고 있습니다.',
    );

    try {
      if (area.isEmpty) {
        throw StateError('현재 지역 정보가 없습니다.');
      }
      trace.log('현재 지역 확인 완료: $area', progress: .16);
      trace.log('Firestore sector 컬렉션을 조회합니다.', progress: .38);
      await context.read<SectorState>().manualSectorRefreshStrict();
      if (!mounted) return;
      final count = context.read<SectorState>().sectors.length;
      trace.log('지역별 섹터 캐시 저장을 확인했습니다.', progress: .82);
      await trace.succeed('섹터 데이터 새로고침 완료: $count개');
      if (!mounted) return;
      _log('refresh_completed count=$count');
      showSuccessSnackbar(
        context,
        '섹터 데이터를 새로고침했습니다.',
        useCommonUi: true,
      );
    } catch (error, stackTrace) {
      _log('refresh_failed error=$error');
      await trace.fail(
        '섹터 데이터 새로고침에 실패했습니다.',
        error: error,
        stackTrace: stackTrace,
      );
      if (!mounted) return;
      showFailedSnackbar(
        context,
        _errorMessage(error, fallback: '섹터 데이터 새로고침에 실패했습니다.'),
        useCommonUi: true,
      );
    }
  }

  Future<bool> _saveSector({
    required String name,
    SectorModel? existing,
  }) async {
    final state = context.read<SectorState>();
    final area = context.read<AreaState>().currentArea.trim();
    final editing = existing != null;
    final trace = await _startTrace(
      title: editing ? '섹터 수정' : '섹터 등록',
      initialMessage: editing
          ? '선택한 섹터의 수정 요청을 확인하고 있습니다.'
          : '새 섹터 등록 요청을 확인하고 있습니다.',
    );

    try {
      if (area.isEmpty) {
        throw StateError('현재 지역 정보가 없습니다.');
      }
      trace.log('현재 지역 확인 완료: $area', progress: .14);
      final targetDocumentId = buildSectorDocumentId(
        name: name,
        area: area,
      );
      trace.log(
        '저장 대상: collection=sector, sourceId=${existing?.id ?? '-'}, targetId=$targetDocumentId, area=$area, name=${name.trim()}, normalizedName=${normalizeSectorName(name)}',
        progress: .28,
      );
      trace.log('섹터명 정규화 및 중복 여부를 확인합니다.', progress: .4);
      final result = existing != null
          ? await state.updateSector(id: existing.id, name: name)
          : await state.createSector(name);
      trace.log(
        'Firestore sector 문서 저장 완료: ${result.id}',
        progress: .72,
      );
      trace.log('지역별 섹터 캐시 저장을 확인했습니다.', progress: .9);
      await trace.succeed(
        editing
            ? '섹터 수정 완료: ${result.name}'
            : '섹터 등록 완료: ${result.name}',
      );
      if (!mounted) return true;
      _log(
        '${editing ? 'sector_updated' : 'sector_created'} id=${result.id} name=${result.name}',
      );
      showSuccessSnackbar(
        context,
        editing ? '섹터를 수정했습니다.' : '섹터를 등록했습니다.',
        useCommonUi: true,
      );
      return true;
    } catch (error, stackTrace) {
      _log('${editing ? 'sector_update' : 'sector_create'}_failed error=$error');
      await trace.fail(
        editing ? '섹터 수정에 실패했습니다.' : '섹터 등록에 실패했습니다.',
        error: error,
        stackTrace: stackTrace,
      );
      if (mounted) {
        showFailedSnackbar(
          context,
          _errorMessage(
            error,
            fallback: editing ? '섹터 수정에 실패했습니다.' : '섹터 등록에 실패했습니다.',
          ),
          useCommonUi: true,
        );
      }
      rethrow;
    }
  }

  Future<void> _openSetting({SectorModel? sector}) async {
    final area = context.read<AreaState>().currentArea.trim();
    if (area.isEmpty) {
      showFailedSnackbar(
        context,
        '현재 지역 정보가 없습니다.',
        useCommonUi: true,
      );
      return;
    }

    _log('form_opened mode=${sector == null ? 'create' : 'edit'} id=${sector?.id ?? '-'}');
    await showCommonOverlayBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isDismissible: true,
      enableDrag: true,
      builder: (sheetContext) {
        return SectorSetting(
          currentArea: area,
          initialSector: sector,
          onSave: (name) => _saveSector(name: name, existing: sector),
        );
      },
    );
  }

  Future<void> _deleteSelected(SectorModel selected) async {
    _log('delete_confirm_opened id=${selected.id} name=${selected.name}');
    final confirmed = await showOpsConfirmDialog(
      context: context,
      title: '섹터 삭제 확인',
      message: '${selected.name} 섹터를 삭제하시겠습니까?',
      confirmLabel: '삭제',
      icon: Icons.delete_forever_rounded,
      destructive: true,
    );
    if (!confirmed || !mounted) {
      _log('delete_cancelled id=${selected.id}');
      return;
    }

    final state = context.read<SectorState>();
    final trace = await _startTrace(
      title: '섹터 삭제',
      initialMessage: '선택한 섹터의 삭제 요청을 확인하고 있습니다.',
    );

    try {
      trace.log('삭제 대상 확인 완료: ${selected.name}', progress: .2);
      trace.log(
        '삭제 대상: collection=sector, id=${selected.id}, area=${selected.area}',
        progress: .34,
      );
      trace.log('현재 지역 소유권을 확인합니다.', progress: .46);
      await state.deleteSector(selected.id);
      trace.log('Firestore sector 문서 삭제를 완료했습니다.', progress: .76);
      trace.log('지역별 섹터 캐시를 갱신했습니다.', progress: .9);
      await trace.succeed('섹터 삭제 완료: ${selected.name}');
      if (!mounted) return;
      _log('delete_completed id=${selected.id} name=${selected.name}');
      showSuccessSnackbar(
        context,
        '섹터를 삭제했습니다.',
        useCommonUi: true,
      );
    } catch (error, stackTrace) {
      _log('delete_failed id=${selected.id} error=$error');
      await trace.fail(
        '섹터 삭제에 실패했습니다.',
        error: error,
        stackTrace: stackTrace,
      );
      if (!mounted) return;
      showFailedSnackbar(
        context,
        _errorMessage(error, fallback: '섹터 삭제에 실패했습니다.'),
        useCommonUi: true,
      );
    }
  }

  String _errorMessage(Object error, {required String fallback}) {
    if (error is SectorDuplicateNameException ||
        error is SectorAreaMismatchException ||
        error is SectorNotFoundException) {
      return error.toString();
    }
    if (error is StateError) return error.message;
    if (error is ArgumentError) {
      return error.message?.toString() ?? fallback;
    }
    return fallback;
  }

  String _formatUpdatedAt(DateTime? value) {
    if (value == null) return '시간 정보 없음';
    final local = value.toLocal();
    String two(int number) => number.toString().padLeft(2, '0');
    return '${local.year}.${two(local.month)}.${two(local.day)} ${two(local.hour)}:${two(local.minute)}';
  }

  bool _matchesSearch(SectorModel sector) {
    final normalizedQuery = _query.trim().toLowerCase();
    if (normalizedQuery.isEmpty) return true;
    return sector.name.toLowerCase().contains(normalizedQuery) ||
        sector.normalizedName.contains(normalizeSectorName(normalizedQuery));
  }

  SectorModel? _visibleSelection(
    SectorState state,
    List<SectorModel> visibleSectors,
  ) {
    final selectedId = state.selectedSectorId;
    if (selectedId == null) return null;
    for (final sector in visibleSectors) {
      if (sector.id == selectedId) return sector;
    }
    return null;
  }

  void _scheduleSelectionValidation(
    SectorState state,
    List<SectorModel> visibleSectors,
  ) {
    final selectedId = state.selectedSectorId;
    if (selectedId == null ||
        visibleSectors.any((sector) => sector.id == selectedId) ||
        _selectionValidationScheduled) {
      return;
    }
    _selectionValidationScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _selectionValidationScheduled = false;
      if (!mounted) return;
      final currentState = context.read<SectorState>();
      final currentSelectedId = currentState.selectedSectorId;
      if (currentSelectedId == null) return;
      final currentArea = context.read<AreaState>().currentArea.trim();
      final currentlyVisible = currentState.sectors
          .where((sector) => sector.area == currentArea)
          .where(_matchesSearch)
          .any((sector) => sector.id == currentSelectedId);
      if (currentlyVisible) return;
      currentState.clearSelection();
      _log('selection_cleared reason=filtered_out id=$currentSelectedId');
    });
  }

  Future<void> _selectSector(
    SectorState state,
    SectorModel sector,
  ) async {
    final wasSelected = state.selectedSectorId == sector.id;
    await HapticFeedback.selectionClick();
    if (!mounted) return;
    state.toggleSectorSelection(sector.id);
    _log(
      '${wasSelected ? 'sector_deselected' : 'sector_selected'} id=${sector.id} name=${sector.name}',
    );
  }

  Widget _buildToolbar(
    BuildContext context, {
    required SectorState state,
  }) {
    final refreshing = state.isRefreshing;
    return Row(
      children: [
        Expanded(
          child: OpsDockSearchField(
            controller: _searchController,
            query: _query,
            semanticLabel: '섹터 검색',
            onChanged: _setQuery,
            onClear: _clearQuery,
          ),
        ),
        const SizedBox(width: 6),
        CommonIconButton(
          icon: Icons.refresh_rounded,
          tooltip: '새로고침',
          onPressed: state.isBusy ? null : _manualRefresh,
          loading: refreshing,
          haptic: CommonHaptic.selection,
          size: 40,
          iconSize: 19,
        ),
        const SizedBox(width: 4),
        CommonIconButton(
          icon: Icons.add_location_alt_rounded,
          tooltip: '섹터 등록',
          onPressed: state.isBusy ? null : () => _openSetting(),
          haptic: CommonHaptic.selection,
          size: 40,
          iconSize: 19,
        ),
      ],
    );
  }

  Widget _buildEmptyState(
    BuildContext context, {
    required bool scopedEmpty,
    required bool busy,
  }) {
    final tokens = CommonUiTheme.of(context);
    final textTheme = Theme.of(context).textTheme;
    final queryActive = _query.trim().isNotEmpty;
    final title = scopedEmpty
        ? '등록된 섹터가 없습니다'
        : queryActive
            ? '일치하는 섹터가 없습니다'
            : '표시할 섹터가 없습니다';

    Widget? action;
    if (scopedEmpty) {
      action = CommonButton(
        label: '섹터 등록',
        icon: Icons.add_location_alt_rounded,
        onPressed: busy ? null : () => _openSetting(),
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
                queryActive ? Icons.search_off_rounded : Icons.hub_rounded,
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

  Widget _buildSectorList(
    BuildContext context, {
    required SectorState state,
    required List<SectorModel> sectors,
  }) {
    final tokens = CommonUiTheme.of(context);
    return OpsDockListSurface(
      child: ListView.separated(
        padding: EdgeInsets.zero,
        itemCount: sectors.length,
        separatorBuilder: (context, index) => Divider(
          height: 1,
          thickness: 1,
          color: tokens.borderSubtle,
        ),
        itemBuilder: (context, index) {
          final sector = sectors[index];
          return _SectorDockRow(
            key: ValueKey<String>(sector.id),
            name: sector.name,
            updatedAt: _formatUpdatedAt(sector.updatedAt),
            selected: state.selectedSectorId == sector.id,
            onTap: () {
              unawaited(_selectSector(state, sector));
            },
          );
        },
      ),
    );
  }

  Widget _buildContextFooter(
    BuildContext context, {
    required SectorState state,
    required SectorModel? selected,
  }) {
    if (selected == null) {
      return const SizedBox.shrink(key: ValueKey<String>('sector_footer_none'));
    }

    return OpsDockContextFooter(
      key: ValueKey<String>('sector_footer_${selected.id}'),
      children: [
        Expanded(
          child: CommonButton(
            label: '수정',
            icon: Icons.edit_location_alt_rounded,
            onPressed: state.isBusy ? null : () => _openSetting(sector: selected),
            variant: CommonButtonVariant.secondary,
            haptic: CommonHaptic.selection,
            minHeight: 42,
            expand: true,
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: CommonButton(
            label: '삭제',
            icon: Icons.delete_forever_rounded,
            onPressed: state.isBusy ? null : () => _deleteSelected(selected),
            variant: CommonButtonVariant.destructive,
            haptic: CommonHaptic.medium,
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
    final currentArea = context.watch<AreaState>().currentArea.trim();
    final state = context.watch<SectorState>();
    final areaSectors = state.sectors
        .where((sector) => sector.area == currentArea)
        .toList(growable: false);
    final visibleSectors = areaSectors.where(_matchesSearch).toList(growable: false);
    final selected = _visibleSelection(state, visibleSectors);
    final initialLoading = state.isLoading && areaSectors.isEmpty;

    _scheduleSelectionValidation(state, visibleSectors);

    final listBody = initialLoading
        ? const SizedBox.expand(key: ValueKey<String>('sector_initial_loading'))
        : visibleSectors.isEmpty
            ? KeyedSubtree(
                key: ValueKey<String>(
                  'sector_empty_${areaSectors.isEmpty}_${_query.trim().isNotEmpty}',
                ),
                child: _buildEmptyState(
                  context,
                  scopedEmpty: areaSectors.isEmpty,
                  busy: state.isBusy,
                ),
              )
            : KeyedSubtree(
                key: ValueKey<String>(
                  'sector_list_${_query.trim().toLowerCase()}_${visibleSectors.length}',
                ),
                child: _buildSectorList(
                  context,
                  state: state,
                  sectors: visibleSectors,
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
                child: _buildToolbar(context, state: state),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 7),
                child: Row(
                  children: [
                    Text(
                      _query.trim().isEmpty || visibleSectors.length == areaSectors.length
                          ? '${visibleSectors.length}개 표시'
                          : '${visibleSectors.length}개 표시 · 전체 ${areaSectors.length}개',
                      style: textTheme.labelSmall?.copyWith(
                        color: tokens.textSecondary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const Spacer(),
                    Icon(
                      Icons.hub_rounded,
                      size: 16,
                      color: tokens.iconSecondary,
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
                  state: state,
                  selected: selected,
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

class _SectorDockRow extends StatelessWidget {
  const _SectorDockRow({
    super.key,
    required this.name,
    required this.updatedAt,
    required this.selected,
    required this.onTap,
  });

  final String name;
  final String updatedAt;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final textTheme = Theme.of(context).textTheme;
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;

    return OpsDockSelectableRowSurface(
      selected: selected,
      selectionColor: tokens.accent,
      selectedContainer: tokens.accentContainer,
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  name.trim().isEmpty ? '이름 없음' : name.trim(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.bodyMedium?.copyWith(
                    color: tokens.textPrimary,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -.1,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              AnimatedSwitcher(
                duration:
                    reduceMotion ? Duration.zero : CommonUiMotion.selection,
                transitionBuilder: (child, animation) => ScaleTransition(
                  scale: animation,
                  child: FadeTransition(
                    opacity: animation,
                    child: child,
                  ),
                ),
                child: Icon(
                  selected
                      ? Icons.check_circle_rounded
                      : Icons.chevron_right_rounded,
                  key: ValueKey<bool>(selected),
                  size: 18,
                  color: selected ? tokens.accent : tokens.iconSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          Text(
            updatedAt,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: textTheme.labelSmall?.copyWith(
              color: tokens.textSecondary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
