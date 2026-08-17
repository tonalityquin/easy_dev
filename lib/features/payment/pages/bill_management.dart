import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
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
import '../applications/bill_state.dart';
import '../domain/models/bill_model.dart';
import '../domain/models/regular_bill_model.dart';
import 'sheets/bill_bottom_sheet.dart';

class BillManagement extends StatefulWidget {
  const BillManagement({super.key});

  @override
  State<BillManagement> createState() => _BillManagementState();
}

class _BillManagementState extends State<BillManagement> {
  final TextEditingController _searchController = TextEditingController();
  final NumberFormat _won = NumberFormat.decimalPattern();
  String _query = '';
  BillType? _typeFilter;
  bool _refreshing = false;
  bool _mutating = false;
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
    debugPrint('[BillManagement] disposed');
    super.dispose();
  }

  void _log(String message) {
    final output = 'bill_workspace $message';
    debugPrint('[BillManagement] $message');
    if (!mounted) return;
    SecondaryDebugScope.maybeOf(context)?.call(output);
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
          '개발자 모드 ON: 정산 작업 상태와 debugPrint 코드를 확인하고 복사할 수 있습니다.',
      standardModeMessage:
          '개발자 모드 OFF: 상태 다이얼로그 없이 작업 로그를 콘솔에 기록합니다.',
    );
  }

  Future<void> _initialRefresh() async {
    final area = context.read<AreaState>().currentArea.trim();
    _log('initial_refresh_started area=${area.isEmpty ? '-' : area}');
    try {
      await context.read<BillState>().manualBillRefreshStrict();
      if (!mounted) return;
      final state = context.read<BillState>();
      _log(
        'initial_refresh_completed general=${state.generalBills.length} regular=${state.regularBills.length}',
      );
    } catch (error, stackTrace) {
      _log('initial_refresh_failed error=$error');
      debugPrint('[BillManagement] initial_refresh_stack=$stackTrace');
    }
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

  void _setTypeFilter(BillType? value) {
    if (_typeFilter == value) return;
    setState(() => _typeFilter = value);
    _log('type_filter_changed value=${value == null ? 'all' : billTypeToString(value)}');
  }

  Future<void> _manualRefresh() async {
    if (_refreshing || _mutating) return;
    final area = context.read<AreaState>().currentArea.trim();
    _log('refresh_started area=${area.isEmpty ? '-' : area}');
    setState(() => _refreshing = true);
    final trace = await _startTrace(
      title: '정산 데이터 새로고침',
      initialMessage: '현재 지역의 정산 데이터를 확인하고 있습니다.',
    );

    try {
      if (area.isEmpty) {
        throw StateError('현재 지역 정보가 없습니다.');
      }
      trace.log('현재 지역 확인 완료: $area', progress: .16);
      trace.log('Firestore 정산 데이터를 조회합니다.', progress: .38);
      await context.read<BillState>().manualBillRefreshStrict();
      if (!mounted) return;
      final state = context.read<BillState>();
      trace.log('지역별 정산 캐시 저장을 확인했습니다.', progress: .82);
      await trace.succeed(
        '정산 데이터 새로고침 완료: 변동 ${state.generalBills.length}개, 정기 ${state.regularBills.length}개',
      );
      if (!mounted) return;
      _log(
        'refresh_completed general=${state.generalBills.length} regular=${state.regularBills.length}',
      );
      showSuccessSnackbar(
        context,
        '정산 데이터를 새로고침했습니다.',
        useCommonUi: true,
      );
    } catch (error, stackTrace) {
      _log('refresh_failed error=$error');
      await trace.fail(
        '정산 데이터 새로고침에 실패했습니다.',
        error: error,
        stackTrace: stackTrace,
      );
      if (!mounted) return;
      showFailedSnackbar(
        context,
        _errorMessage(error, fallback: '정산 데이터 새로고침에 실패했습니다.'),
        useCommonUi: true,
      );
    } finally {
      if (mounted) {
        setState(() => _refreshing = false);
      }
    }
  }

  Future<void> _saveBill(Map<String, dynamic> billData) async {
    if (_mutating) return;
    final area = context.read<AreaState>().currentArea.trim();
    final countType = billData['CountType']?.toString().trim() ?? '';
    final type = billData['type']?.toString().trim() ?? '';
    final trace = await _startTrace(
      title: '정산 유형 등록',
      initialMessage: '새 정산 유형의 등록 요청을 확인하고 있습니다.',
    );
    if (!mounted) return;
    setState(() => _mutating = true);

    try {
      if (area.isEmpty) {
        throw StateError('현재 지역 정보가 없습니다.');
      }
      if (countType.isEmpty) {
        throw ArgumentError('정산 유형명이 없습니다.');
      }
      trace.log('현재 지역 확인 완료: $area', progress: .14);
      trace.log(
        '저장 대상 확인: type=${type.isEmpty ? '-' : type}, CountType=$countType, area=$area',
        progress: .28,
      );
      trace.log('Firestore 정산 문서 저장을 요청합니다.', progress: .52);
      await context.read<BillState>().addBillFromMap(billData);
      if (!mounted) return;
      trace.log('지역별 정산 캐시 저장을 확인했습니다.', progress: .86);
      await trace.succeed('정산 유형 등록 완료: $countType');
      if (!mounted) return;
      _log('bill_created type=${type.isEmpty ? '-' : type} name=$countType');
      showSuccessSnackbar(
        context,
        '정산 유형을 저장했습니다.',
        useCommonUi: true,
      );
    } catch (error, stackTrace) {
      _log('bill_create_failed error=$error');
      await trace.fail(
        '정산 유형 등록에 실패했습니다.',
        error: error,
        stackTrace: stackTrace,
      );
      if (!mounted) return;
      showFailedSnackbar(
        context,
        _errorMessage(error, fallback: '정산 유형 저장에 실패했습니다.'),
        useCommonUi: true,
      );
    } finally {
      if (mounted) {
        setState(() => _mutating = false);
      }
    }
  }

  Future<void> _openBillSetting() async {
    final area = context.read<AreaState>().currentArea.trim();
    if (area.isEmpty) {
      showFailedSnackbar(
        context,
        '현재 지역 정보가 없습니다.',
        useCommonUi: true,
      );
      return;
    }
    _log('form_opened type=general area=$area');
    await showCommonOverlayBottomSheet<void>(
      context: context,
      useSafeArea: true,
      builder: (sheetContext) {
        return FractionallySizedBox(
          heightFactor: 1,
          child: BillSettingBottomSheet(
            onSave: (billData) => _saveBill(billData),
          ),
        );
      },
    );
  }

  Future<void> _deleteSelectedBill(_BillDockItem selected) async {
    _log(
      'delete_confirm_opened id=${selected.id} type=${billTypeToString(selected.type)} name=${selected.title}',
    );
    final confirmed = await showOpsConfirmDialog(
      context: context,
      title: '정산 유형 삭제 확인',
      message: '${selected.title} 정산 유형을 삭제하시겠습니까?',
      confirmLabel: '삭제',
      icon: Icons.delete_forever_rounded,
      destructive: true,
    );
    if (!confirmed || !mounted) {
      _log('delete_cancelled id=${selected.id}');
      return;
    }

    if (_mutating) return;
    final state = context.read<BillState>();
    final trace = await _startTrace(
      title: '정산 유형 삭제',
      initialMessage: '선택한 정산 유형의 삭제 요청을 확인하고 있습니다.',
    );
    if (!mounted) return;
    setState(() => _mutating = true);

    try {
      trace.log(
        '삭제 대상 확인: id=${selected.id}, type=${billTypeToString(selected.type)}, name=${selected.title}',
        progress: .18,
      );
      trace.log('로컬 목록과 캐시에서 삭제 대상을 반영합니다.', progress: .4);
      await state.deleteBillStrict([selected.id]);
      if (!mounted) return;
      trace.log('Firestore 삭제 및 캐시 정합성 확인 완료', progress: .86);
      await trace.succeed('정산 유형 삭제 완료: ${selected.title}');
      if (!mounted) return;
      _log('delete_completed id=${selected.id} name=${selected.title}');
      showSuccessSnackbar(
        context,
        '정산 유형을 삭제했습니다.',
        useCommonUi: true,
      );
    } catch (error, stackTrace) {
      _log('delete_failed id=${selected.id} error=$error');
      await trace.fail(
        '정산 유형 삭제에 실패했습니다.',
        error: error,
        stackTrace: stackTrace,
      );
      if (!mounted) return;
      showFailedSnackbar(
        context,
        _errorMessage(error, fallback: '정산 유형 삭제에 실패했습니다.'),
        useCommonUi: true,
      );
    } finally {
      if (mounted) {
        setState(() => _mutating = false);
      }
    }
  }

  String _errorMessage(Object error, {required String fallback}) {
    if (error is StateError) return error.message;
    if (error is ArgumentError) {
      return error.message?.toString() ?? fallback;
    }
    return fallback;
  }

  _BillDockItem _generalItem(BillModel bill) {
    return _BillDockItem(
      id: bill.id,
      type: BillType.general,
      title: bill.countType.trim().isEmpty ? '이름 없음' : bill.countType.trim(),
      area: bill.area.trim(),
      primaryMetadata:
          '기본 ${bill.basicStandard ?? 0}분 · ₩${_won.format(bill.basicAmount ?? 0)}',
      secondaryMetadata:
          '추가 ${bill.addStandard ?? 0}분 · ₩${_won.format(bill.addAmount ?? 0)}',
    );
  }

  _BillDockItem _regularItem(RegularBillModel bill) {
    final regularType = bill.regularType.trim().isEmpty ? '유형 미지정' : bill.regularType.trim();
    return _BillDockItem(
      id: bill.id,
      type: BillType.regular,
      title: bill.countType.trim().isEmpty ? '이름 없음' : bill.countType.trim(),
      area: bill.area.trim(),
      primaryMetadata: '$regularType · ₩${_won.format(bill.regularAmount)}',
      secondaryMetadata: '기간값 ${bill.regularDurationValue}',
    );
  }

  bool _matchesQuery(_BillDockItem item) {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return true;
    return '${item.title} ${item.area} ${billTypeToString(item.type)} ${item.primaryMetadata} ${item.secondaryMetadata}'
        .toLowerCase()
        .contains(q);
  }

  _BillDockItem? _visibleSelection(
    BillState state,
    List<_BillDockItem> visibleItems,
  ) {
    final selectedId = state.selectedBillId;
    if (selectedId == null) return null;
    for (final item in visibleItems) {
      if (item.id == selectedId) return item;
    }
    return null;
  }

  void _scheduleSelectionValidation(
    BillState state,
    List<_BillDockItem> scopedItems,
    List<_BillDockItem> visibleItems,
  ) {
    final selectedId = state.selectedBillId;
    if (selectedId == null ||
        visibleItems.any((item) => item.id == selectedId) ||
        _selectionValidationScheduled) {
      return;
    }
    final reason = scopedItems.any((item) => item.id == selectedId)
        ? 'filtered_out'
        : 'scope_changed';
    _selectionValidationScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _selectionValidationScheduled = false;
      if (!mounted) return;
      final currentState = context.read<BillState>();
      final currentSelectedId = currentState.selectedBillId;
      if (currentSelectedId == null) return;
      final currentArea = context.read<AreaState>().currentArea.trim();
      final currentScoped = <_BillDockItem>[
        ...currentState.generalBills
            .where((bill) => currentArea.isEmpty || bill.area.trim() == currentArea)
            .map(_generalItem),
        ...currentState.regularBills
            .where((bill) => currentArea.isEmpty || bill.area.trim() == currentArea)
            .map(_regularItem),
      ];
      final currentVisible = currentScoped.where((item) {
        final typeMatches = _typeFilter == null || item.type == _typeFilter;
        return typeMatches && _matchesQuery(item);
      }).any((item) => item.id == currentSelectedId);
      if (currentVisible) return;
      currentState.clearSelection();
      _log('selection_cleared reason=$reason id=$currentSelectedId');
    });
  }

  Future<void> _selectBill(BillState state, _BillDockItem item) async {
    final wasSelected = state.selectedBillId == item.id;
    await HapticFeedback.selectionClick();
    if (!mounted) return;
    state.toggleBillSelection(item.id);
    _log(
      '${wasSelected ? 'bill_deselected' : 'bill_selected'} id=${item.id} type=${billTypeToString(item.type)} name=${item.title}',
    );
  }

  Widget _buildToolbar(
    BuildContext context, {
    required BillState state,
  }) {
    final busy = _refreshing || _mutating || state.isLoading;
    return Row(
      children: [
        Expanded(
          child: OpsDockSearchField(
            controller: _searchController,
            query: _query,
            semanticLabel: '정산 검색',
            onChanged: _setQuery,
            onClear: _clearQuery,
          ),
        ),
        const SizedBox(width: 6),
        CommonIconButton(
          icon: Icons.refresh_rounded,
          tooltip: '정산 새로고침',
          onPressed: busy ? null : _manualRefresh,
          loading: _refreshing || state.isLoading,
          haptic: CommonHaptic.selection,
          size: 40,
          iconSize: 20,
        ),
        const SizedBox(width: 4),
        CommonIconButton(
          icon: Icons.add_card_rounded,
          tooltip: '정산 유형 등록',
          onPressed: busy ? null : _openBillSetting,
          haptic: CommonHaptic.selection,
          size: 40,
          iconSize: 20,
        ),
      ],
    );
  }

  Widget _buildTypeSegments(
    BuildContext context, {
    required int total,
    required int general,
    required int regular,
  }) {
    final tokens = CommonUiTheme.of(context);
    return OpsDockStatusSegments<BillType?>(
      selected: _typeFilter,
      items: [
        OpsDockStatusSegmentItem<BillType?>(
          value: null,
          label: '전체',
          count: total,
          color: tokens.accent,
        ),
        OpsDockStatusSegmentItem<BillType?>(
          value: BillType.general,
          label: '변동',
          count: general,
          color: tokens.info,
        ),
        OpsDockStatusSegmentItem<BillType?>(
          value: BillType.regular,
          label: '정기',
          count: regular,
          color: tokens.warning,
        ),
      ],
      onSelected: _setTypeFilter,
    );
  }

  Widget _buildEmptyState(
    BuildContext context, {
    required int scopedCount,
    required bool busy,
  }) {
    final tokens = CommonUiTheme.of(context);
    final textTheme = Theme.of(context).textTheme;
    final queryActive = _query.trim().isNotEmpty;
    final filteredType = _typeFilter;
    final title = scopedCount == 0
        ? '등록된 정산 유형이 없습니다'
        : queryActive
            ? '일치하는 정산 유형이 없습니다'
            : filteredType == BillType.general
                ? '변동 정산 유형이 없습니다'
                : filteredType == BillType.regular
                    ? '정기 정산 유형이 없습니다'
                    : '표시할 정산 유형이 없습니다';

    Widget? action;
    if (scopedCount == 0) {
      action = CommonButton(
        label: '정산 유형 등록',
        icon: Icons.add_card_rounded,
        onPressed: busy ? null : _openBillSetting,
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
    } else if (filteredType != null) {
      action = CommonButton(
        label: '전체 보기',
        icon: Icons.all_inclusive_rounded,
        onPressed: () => _setTypeFilter(null),
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
                queryActive ? Icons.search_off_rounded : Icons.receipt_long_rounded,
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

  Widget _buildBillList(
    BuildContext context, {
    required BillState state,
    required List<_BillDockItem> visibleItems,
  }) {
    final tokens = CommonUiTheme.of(context);
    final generalItems = visibleItems
        .where((item) => item.type == BillType.general)
        .toList(growable: false);
    final regularItems = visibleItems
        .where((item) => item.type == BillType.regular)
        .toList(growable: false);
    final children = <Widget>[];

    void addDivider() {
      children.add(
        Divider(
          height: 1,
          thickness: 1,
          color: tokens.borderSubtle,
        ),
      );
    }

    void addRows(List<_BillDockItem> items) {
      for (var index = 0; index < items.length; index++) {
        if (index > 0) addDivider();
        final item = items[index];
        children.add(
          _BillDockRow(
            key: ValueKey<String>(item.id),
            item: item,
            selected: state.selectedBillId == item.id,
            onTap: () {
              unawaited(_selectBill(state, item));
            },
          ),
        );
      }
    }

    if (_typeFilter == null) {
      if (generalItems.isNotEmpty) {
        children.add(
          _BillSectionLabel(
            title: '변동 정산',
            count: generalItems.length,
            color: tokens.info,
          ),
        );
        addDivider();
        addRows(generalItems);
      }
      if (regularItems.isNotEmpty) {
        if (children.isNotEmpty) addDivider();
        children.add(
          _BillSectionLabel(
            title: '정기 정산',
            count: regularItems.length,
            color: tokens.warning,
          ),
        );
        addDivider();
        addRows(regularItems);
      }
    } else {
      addRows(visibleItems);
    }

    return OpsDockListSurface(
      child: ListView(
        padding: EdgeInsets.zero,
        children: children,
      ),
    );
  }

  Widget _buildContextFooter(
    BuildContext context, {
    required BillState state,
    required _BillDockItem? selected,
  }) {
    if (selected == null) {
      return const SizedBox.shrink(key: ValueKey<String>('bill_footer_none'));
    }

    return OpsDockContextFooter(
      key: ValueKey<String>('bill_footer_${selected.id}'),
      children: [
        Expanded(
          child: CommonButton(
            label: '삭제',
            icon: Icons.delete_forever_rounded,
            onPressed: state.isLoading || _refreshing || _mutating
                ? null
                : () => _deleteSelectedBill(selected),
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
    final state = context.watch<BillState>();
    final scopedGeneral = state.generalBills
        .where((bill) => currentArea.isEmpty || bill.area.trim() == currentArea)
        .map(_generalItem)
        .toList(growable: false);
    final scopedRegular = state.regularBills
        .where((bill) => currentArea.isEmpty || bill.area.trim() == currentArea)
        .map(_regularItem)
        .toList(growable: false);
    final scopedItems = <_BillDockItem>[
      ...scopedGeneral,
      ...scopedRegular,
    ];
    final visibleItems = scopedItems.where((item) {
      final typeMatches = _typeFilter == null || item.type == _typeFilter;
      return typeMatches && _matchesQuery(item);
    }).toList(growable: false);
    final selected = _visibleSelection(state, visibleItems);
    final initialLoading = state.isLoading && scopedItems.isEmpty;

    _scheduleSelectionValidation(state, scopedItems, visibleItems);

    final listBody = initialLoading
        ? const SizedBox.expand(key: ValueKey<String>('bill_initial_loading'))
        : visibleItems.isEmpty
            ? KeyedSubtree(
                key: ValueKey<String>(
                  'bill_empty_${scopedItems.isEmpty}_${_typeFilter?.name ?? 'all'}_${_query.trim().isNotEmpty}',
                ),
                child: _buildEmptyState(
                  context,
                  scopedCount: scopedItems.length,
                  busy: state.isLoading || _refreshing || _mutating,
                ),
              )
            : KeyedSubtree(
                key: ValueKey<String>(
                  'bill_list_${_typeFilter?.name ?? 'all'}_${_query.trim().toLowerCase()}_${visibleItems.length}',
                ),
                child: _buildBillList(
                  context,
                  state: state,
                  visibleItems: visibleItems,
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
                padding: const EdgeInsets.fromLTRB(10, 7, 10, 0),
                child: _buildTypeSegments(
                  context,
                  total: scopedItems.length,
                  general: scopedGeneral.length,
                  regular: scopedRegular.length,
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 7),
                child: Row(
                  children: [
                    Text(
                      _query.trim().isEmpty &&
                              _typeFilter == null &&
                              visibleItems.length == scopedItems.length
                          ? '${visibleItems.length}개 표시'
                          : '${visibleItems.length}개 표시 · 전체 ${scopedItems.length}개',
                      style: textTheme.labelSmall?.copyWith(
                        color: tokens.textSecondary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const Spacer(),
                    Icon(
                      Icons.receipt_long_rounded,
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

class _BillDockItem {
  const _BillDockItem({
    required this.id,
    required this.type,
    required this.title,
    required this.area,
    required this.primaryMetadata,
    required this.secondaryMetadata,
  });

  final String id;
  final BillType type;
  final String title;
  final String area;
  final String primaryMetadata;
  final String secondaryMetadata;
}

class _BillSectionLabel extends StatelessWidget {
  const _BillSectionLabel({
    required this.title,
    required this.count,
    required this.color,
  });

  final String title;
  final int count;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final textTheme = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(11, 7, 11, 7),
      color: tokens.surface.withOpacity(.62),
      child: Row(
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              title,
              style: textTheme.labelSmall?.copyWith(
                color: tokens.textPrimary,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          Text(
            '$count',
            style: textTheme.labelSmall?.copyWith(
              color: tokens.textSecondary,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _BillDockRow extends StatelessWidget {
  const _BillDockRow({
    super.key,
    required this.item,
    required this.selected,
    required this.onTap,
  });

  final _BillDockItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final textTheme = Theme.of(context).textTheme;
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final typeColor = item.type == BillType.general ? tokens.info : tokens.warning;

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
                  item.title,
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
              Text(
                billTypeToString(item.type),
                style: textTheme.labelSmall?.copyWith(
                  color: typeColor,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(width: 7),
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
            item.primaryMetadata,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: textTheme.labelSmall?.copyWith(
              color: tokens.textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            item.secondaryMetadata,
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
