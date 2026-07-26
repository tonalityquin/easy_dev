import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/utils/developer_operation_status_dialog.dart';
import '../../../app/utils/snackbar_helper.dart';
import '../../../design_system/prompt_ui/prompt_ui_components.dart';
import '../../../design_system/prompt_ui/prompt_ui_overlays.dart';
import '../../../design_system/prompt_ui/prompt_ui_theme.dart';
import '../../../shared/secondary/widgets/ops_console_dialogs.dart';
import '../../../shared/secondary/widgets/ops_console_widgets.dart';
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
  String _query = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<SectorState>().manualSectorRefresh();
    });
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
      usePromptUi: true,
      developerModeMessage:
          '개발자 모드 ON: 상태와 디버그 출력을 확인하고 복사할 수 있습니다.',
      standardModeMessage:
          '개발자 모드 OFF: 상태 다이얼로그 없이 작업을 실행합니다.',
    );
  }

  Future<void> _manualRefresh() async {
    final area = context.read<AreaState>().currentArea.trim();
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
      showSuccessSnackbar(
        context,
        '섹터 데이터를 새로고침했습니다.',
        usePromptUi: true,
      );
    } catch (error, stackTrace) {
      await trace.fail(
        '섹터 데이터 새로고침에 실패했습니다.',
        error: error,
        stackTrace: stackTrace,
      );
      if (!mounted) return;
      showFailedSnackbar(
        context,
        _errorMessage(error, fallback: '섹터 데이터 새로고침에 실패했습니다.'),
        usePromptUi: true,
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
      showSuccessSnackbar(
        context,
        editing ? '섹터를 수정했습니다.' : '섹터를 등록했습니다.',
        usePromptUi: true,
      );
      return true;
    } catch (error, stackTrace) {
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
          usePromptUi: true,
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
        usePromptUi: true,
      );
      return;
    }

    await showPromptOverlayBottomSheet<void>(
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

  Future<void> _deleteSelected() async {
    final state = context.read<SectorState>();
    final selected = state.selectedSector;
    if (selected == null) return;

    final confirmed = await showOpsConfirmDialog(
      context: context,
      title: '섹터 삭제 확인',
      message: '${selected.name} 섹터를 삭제하시겠습니까?',
      confirmLabel: '삭제',
      icon: Icons.delete_forever_rounded,
      destructive: true,
    );
    if (!confirmed || !mounted) return;

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
      showSuccessSnackbar(
        context,
        '섹터를 삭제했습니다.',
        usePromptUi: true,
      );
    } catch (error, stackTrace) {
      await trace.fail(
        '섹터 삭제에 실패했습니다.',
        error: error,
        stackTrace: stackTrace,
      );
      if (!mounted) return;
      showFailedSnackbar(
        context,
        _errorMessage(error, fallback: '섹터 삭제에 실패했습니다.'),
        usePromptUi: true,
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

  Widget _buildCommandBar(
    int visibleCount,
    int totalCount,
    bool busy,
  ) {
    return OpsCommandPanel(
      children: <Widget>[
        OpsSearchField(
          hint: '섹터명 검색',
          onChanged: (value) => setState(() => _query = value),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: <Widget>[
            OpsFilterChip(
              label: '$visibleCount/$totalCount',
              selected: false,
              icon: Icons.filter_alt_rounded,
              onSelected: () {},
            ),
            PromptIconButton(
              icon: Icons.refresh_rounded,
              tooltip: '새로고침',
              onPressed: busy ? null : _manualRefresh,
              haptic: PromptHaptic.selection,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildBottomBar(SectorState state) {
    final selected = state.selectedSector;
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    return OpsBottomActionBar(
      children: <Widget>[
        Expanded(
          child: AnimatedSwitcher(
            duration:
                reduceMotion ? Duration.zero : PromptUiMotion.component,
            switchInCurve: PromptUiMotion.enter,
            switchOutCurve: PromptUiMotion.exit,
            transitionBuilder: (child, animation) {
              final curved = CurvedAnimation(
                parent: animation,
                curve: PromptUiMotion.enter,
                reverseCurve: PromptUiMotion.exit,
              );
              return FadeTransition(
                opacity: curved,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0, .08),
                    end: Offset.zero,
                  ).animate(curved),
                  child: child,
                ),
              );
            },
            child: Row(
              key: ValueKey<String>(selected?.id ?? 'sector_add_only'),
              children: <Widget>[
                Expanded(
                  child: OpsActionButton(
                    label: '섹터 등록',
                    icon: Icons.add_location_alt_rounded,
                    onPressed: state.isBusy ? null : () => _openSetting(),
                  ),
                ),
                if (selected != null) ...<Widget>[
                  const SizedBox(width: 8),
                  Expanded(
                    child: OpsActionButton(
                      label: '수정',
                      icon: Icons.edit_location_alt_rounded,
                      tonal: true,
                      onPressed: state.isBusy
                          ? null
                          : () => _openSetting(sector: selected),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OpsActionButton(
                      label: '삭제',
                      icon: Icons.delete_forever_rounded,
                      danger: true,
                      onPressed: state.isBusy ? null : _deleteSelected,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSectorRow(
    SectorState state,
    SectorModel sector,
    int index,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final selected = state.selectedSectorId == sector.id;
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;

    final row = InkWell(
      onTap: () => state.toggleSectorSelection(sector.id),
      borderRadius: BorderRadius.circular(16),
      child: OpsPanel(
        selected: selected,
        padding: EdgeInsets.zero,
        child: Row(
          children: <Widget>[
            AnimatedContainer(
              duration:
                  reduceMotion ? Duration.zero : PromptUiMotion.selection,
              width: 6,
              height: 108,
              decoration: BoxDecoration(
                color: selected
                    ? colorScheme.primary
                    : colorScheme.secondary.withOpacity(.72),
                borderRadius: const BorderRadius.horizontal(
                  left: Radius.circular(16),
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(13, 12, 12, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: Text(
                            sector.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: textTheme.titleMedium?.copyWith(
                              color: colorScheme.onSurface,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        OpsStatusBadge(
                          label: '방문처',
                          color: colorScheme.secondary,
                          icon: Icons.pin_drop_rounded,
                        ),
                      ],
                    ),
                    const SizedBox(height: 9),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: <Widget>[
                        OpsInfoPill(
                          text: sector.area,
                          icon: Icons.business_rounded,
                        ),
                        OpsInfoPill(
                          text: _formatUpdatedAt(sector.updatedAt),
                          icon: Icons.update_rounded,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: AnimatedSwitcher(
                duration:
                    reduceMotion ? Duration.zero : PromptUiMotion.selection,
                child: Icon(
                  selected
                      ? Icons.check_circle_rounded
                      : Icons.chevron_right_rounded,
                  key: ValueKey<bool>(selected),
                  color: selected
                      ? colorScheme.primary
                      : colorScheme.onSurfaceVariant.withOpacity(.7),
                ),
              ),
            ),
          ],
        ),
      ),
    );

    return PromptAnimatedReveal(
      delay: reduceMotion
          ? Duration.zero
          : Duration(milliseconds: index.clamp(0, 8).toInt() * 35),
      offset: const Offset(.025, 0),
      child: row,
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentArea = context.watch<AreaState>().currentArea.trim();
    final areaLabel = currentArea.isEmpty ? '지역 미설정' : currentArea;
    final colorScheme = Theme.of(context).colorScheme;

    return Consumer<SectorState>(
      builder: (context, state, child) {
        final areaSectors = state.sectors
            .where((sector) => sector.area == currentArea)
            .toList(growable: false);
        final normalizedQuery = _query.trim().toLowerCase();
        final visibleSectors = normalizedQuery.isEmpty
            ? areaSectors
            : areaSectors
                .where(
                  (sector) =>
                      sector.name.toLowerCase().contains(normalizedQuery) ||
                      sector.normalizedName.contains(
                        normalizeSectorName(normalizedQuery),
                      ),
                )
                .toList(growable: false);
        final hasSelection = state.selectedSector != null;

        return OpsConsoleScaffold(
          title: '섹터 관리',
          subtitle: '차량이 현재 지역에서 방문한 목적지를 관리합니다.',
          icon: Icons.hub_rounded,
          areaLabel: areaLabel,
          loading: state.isLoading || state.isSaving,
          metrics: <OpsMetric>[
            OpsMetric(
              label: '등록',
              value: '${areaSectors.length}',
              icon: Icons.pin_drop_rounded,
              color: colorScheme.primary,
            ),
            OpsMetric(
              label: '검색',
              value: '${visibleSectors.length}',
              icon: Icons.search_rounded,
              color: colorScheme.secondary,
            ),
            OpsMetric(
              label: '선택',
              value: hasSelection ? '1' : '0',
              icon: Icons.touch_app_rounded,
              color: hasSelection
                  ? colorScheme.primary
                  : colorScheme.onSurfaceVariant,
            ),
            OpsMetric(
              label: '지역',
              value: currentArea.isEmpty ? '-' : currentArea,
              icon: Icons.business_rounded,
              color: colorScheme.tertiary,
            ),
          ],
          commandBar: _buildCommandBar(
            visibleSectors.length,
            areaSectors.length,
            state.isBusy,
          ),
          bottomBar: _buildBottomBar(state),
          body: state.isLoading
              ? const SizedBox.shrink()
              : visibleSectors.isEmpty
                  ? OpsEmptyState(
                      icon: Icons.hub_rounded,
                      title: areaSectors.isEmpty
                          ? '등록된 섹터가 없습니다'
                          : '검색 결과가 없습니다',
                      message: areaSectors.isEmpty
                          ? '현재 지역에서 차량이 방문할 목적지를 등록하세요.'
                          : '검색어를 조정하세요.',
                      action: currentArea.isEmpty
                          ? null
                          : PromptButton(
                              label: '섹터 등록',
                              icon: Icons.add_location_alt_rounded,
                              onPressed: () => _openSetting(),
                              haptic: PromptHaptic.selection,
                            ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
                      itemCount: visibleSectors.length,
                      itemBuilder: (context, index) => _buildSectorRow(
                        state,
                        visibleSectors[index],
                        index,
                      ),
                    ),
        );
      },
    );
  }
}
