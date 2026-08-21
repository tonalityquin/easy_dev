import 'package:flutter/material.dart';

import '../../../../app/utils/developer_operation_status_dialog.dart';
import '../../../../design_system/common_ui/common_ui_components.dart';
import '../../../../design_system/common_ui/common_ui_theme.dart';
import '../../domain/models/grid_rect.dart';
import '../../domain/models/parking_grid_model.dart';
import 'location_parent_tool_spec.dart';
import 'models/location_parent_settings_draft.dart';
import 'widgets/parking_grid_2d_editor.dart';

class LocationParentToolEditorDialog extends StatefulWidget {
  const LocationParentToolEditorDialog({
    super.key,
    required this.category,
    required this.initialDraft,
    required this.trace,
    required this.onApply,
  });

  final LocationParentToolCategory category;
  final LocationParentSettingsDraft initialDraft;
  final DeveloperOperationTrace trace;
  final ValueChanged<LocationParentSettingsDraft> onApply;

  @override
  State<LocationParentToolEditorDialog> createState() =>
      _LocationParentToolEditorDialogState();
}

class _LocationParentToolEditorDialogState
    extends State<LocationParentToolEditorDialog> {
  late List<ParkingGridCellType> _cells;
  late Set<int> _road2Cells;
  late List<ParkingArea> _parkingAreas;
  late List<GridRect> _entranceRects;
  late List<GridRect> _exitRects;
  late List<GridRect> _towerRects;
  late GridEditTool _selectedTool;
  bool _reduceMotion = false;

  ParkingGridModel get _initialGrid => widget.initialDraft.parkingGrid;

  List<LocationParentToolSpec> get _categorySpecs => locationParentToolSpecs
      .where((spec) => spec.category == widget.category)
      .toList(growable: false);

  LocationParentToolSpec get _selectedSpec =>
      locationParentToolSpec(_selectedTool);

  @override
  void initState() {
    super.initState();
    final grid = widget.initialDraft.parkingGrid;
    final specs = locationParentToolSpecs
        .where((spec) => spec.category == widget.category)
        .toList(growable: false);
    _selectedTool = specs.first.tool;
    _cells = List<ParkingGridCellType>.from(grid.cells);
    _road2Cells = Set<int>.from(grid.road2Cells);
    _parkingAreas = List<ParkingArea>.from(grid.parkingAreas);
    _entranceRects = List<GridRect>.from(grid.entranceRects);
    _exitRects = List<GridRect>.from(grid.exitRects);
    _towerRects = List<GridRect>.from(grid.towerRects);
    widget.trace.log(
      '부모구역 category work open category=${widget.category.name} selectedTool=${_selectedTool.name} rows=${grid.rows} cols=${grid.cols}',
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
  }

  ParkingGridModel _currentGrid() {
    final cleanedRoad2 = _road2Cells
        .where((index) => index >= 0 && index < _cells.length)
        .where((index) => _cells[index] == ParkingGridCellType.road)
        .toList()
      ..sort();
    return ParkingGridModel.fromEnumCells(
      rows: _initialGrid.rows,
      cols: _initialGrid.cols,
      cells: _cells,
      parkingAreas: _parkingAreas,
      entranceRects: _entranceRects,
      exitRects: _exitRects,
      towerRects: _towerRects,
      road2Cells: cleanedRoad2,
    );
  }

  void _selectTool(LocationParentToolSpec spec) {
    if (_selectedTool == spec.tool) return;
    setState(() => _selectedTool = spec.tool);
    widget.trace.log(
      '부모구역 category tool selected category=${widget.category.name} tool=${spec.tool.name}',
    );
  }

  void _logDraftChanged(String field) {
    widget.trace.log(
      '부모구역 category draft changed category=${widget.category.name} tool=${_selectedTool.name} field=$field cells=${_cells.length} parking=${_parkingAreas.length} entrance=${_entranceRects.length} exit=${_exitRects.length} tower=${_towerRects.length}',
    );
  }

  void _apply() {
    final grid = _currentGrid();
    final result = widget.initialDraft.copyWith(parkingGrid: grid);
    widget.trace.log(
      '부모구역 category work apply category=${widget.category.name} selectedTool=${_selectedTool.name} parking=${grid.parkingAreas.length} entrance=${grid.entranceRects.length} exit=${grid.exitRects.length} tower=${grid.towerRects.length}',
    );
    widget.onApply(result);
    Navigator.of(context, rootNavigator: true).pop(true);
  }

  void _cancel() {
    widget.trace.log(
      '부모구역 category work cancel category=${widget.category.name} selectedTool=${_selectedTool.name}',
    );
    Navigator.of(context, rootNavigator: true).pop(false);
  }

  Future<void> _showDeveloperTrace() async {
    widget.trace.log(
      '부모구역 category developer status requested category=${widget.category.name} selectedTool=${_selectedTool.name}',
    );
    await widget.trace.showSnapshotStatusDialog(
      context,
      title: '${locationParentToolCategoryLabel(widget.category)} 작업 로그',
      description: '현재 도면 작업의 debugPrint 코드를 확인하고 복사할 수 있습니다.',
    );
  }

  Widget _buildToolPalette(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final specs = _categorySpecs;
    final maxHeight = widget.category == LocationParentToolCategory.parking
        ? 190.0
        : 118.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(
              Icons.touch_app_rounded,
              size: 17,
              color: tokens.iconSecondary,
            ),
            const SizedBox(width: 7),
            Text(
              '작업 도구',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: tokens.textPrimary,
                    fontWeight: FontWeight.w900,
                  ),
            ),
            const Spacer(),
            AnimatedSwitcher(
              duration:
                  _reduceMotion ? Duration.zero : CommonUiMotion.selection,
              child: Text(
                _selectedSpec.label,
                key: ValueKey<GridEditTool>(_selectedTool),
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: tokens.accent,
                      fontWeight: FontWeight.w900,
                    ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 7),
        AnimatedSwitcher(
          duration: _reduceMotion ? Duration.zero : CommonUiMotion.selection,
          switchInCurve: CommonUiMotion.enter,
          switchOutCurve: CommonUiMotion.exit,
          child: Text(
            _selectedSpec.detail,
            key: ValueKey<String>(_selectedSpec.detail),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: tokens.textSecondary,
                  height: 1.3,
                ),
          ),
        ),
        const SizedBox(height: 8),
        ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxHeight),
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final columns = constraints.maxWidth >= 700 ? 3 : 2;
                final gaps = 8.0 * (columns - 1);
                final width = (constraints.maxWidth - gaps) / columns;
                return Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final spec in specs)
                      SizedBox(
                        width: width,
                        child: CommonButton(
                          label: spec.label,
                          icon: spec.icon,
                          onPressed: () => _selectTool(spec),
                          variant: CommonButtonVariant.secondary,
                          selected: _selectedTool == spec.tool,
                          tooltip: spec.detail,
                          haptic: CommonHaptic.selection,
                          minHeight: 40,
                          expand: true,
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final textTheme = Theme.of(context).textTheme;
    final categoryLabel = locationParentToolCategoryLabel(widget.category);
    final categoryIcon = locationParentToolCategoryIcon(widget.category);
    return Material(
      color: Colors.transparent,
      child: Container(
        decoration: BoxDecoration(
          color: tokens.surfaceRaised,
          borderRadius: BorderRadius.circular(CommonUiShapes.dialog),
          border: Border.all(color: tokens.borderSubtle),
        ),
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: tokens.accentContainer.withOpacity(.7),
                    borderRadius:
                        BorderRadius.circular(CommonUiShapes.control),
                  ),
                  child: Icon(categoryIcon, color: tokens.accent, size: 20),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '$categoryLabel 작업',
                        style: textTheme.titleMedium?.copyWith(
                          color: tokens.textPrimary,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${_initialGrid.rows}×${_initialGrid.cols} 전체 도면을 보면서 하단 도구를 선택해 작업합니다.',
                        style: textTheme.bodySmall?.copyWith(
                          color: tokens.textSecondary,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
                if (widget.trace.developerMode)
                  CommonIconButton(
                    icon: Icons.bug_report_outlined,
                    tooltip: '개발자 로그',
                    onPressed: _showDeveloperTrace,
                    haptic: CommonHaptic.selection,
                  ),
                CommonIconButton(
                  icon: Icons.close_rounded,
                  tooltip: '닫기',
                  onPressed: _cancel,
                  haptic: CommonHaptic.selection,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: AnimatedContainer(
                duration:
                    _reduceMotion ? Duration.zero : CommonUiMotion.component,
                curve: CommonUiMotion.standard,
                decoration: BoxDecoration(
                  color: tokens.canvas,
                  border: Border.all(color: tokens.borderSubtle),
                  borderRadius:
                      BorderRadius.circular(CommonUiShapes.control),
                ),
                clipBehavior: Clip.antiAlias,
                child: ParkingGrid2DEditor(
                  rows: _initialGrid.rows,
                  cols: _initialGrid.cols,
                  cells: _cells,
                  tool: _selectedTool,
                  road2Cells: _road2Cells,
                  onChangedRoad2Cells: (next) {
                    setState(() => _road2Cells = Set<int>.from(next));
                    _logDraftChanged('road2');
                  },
                  entranceRects: _entranceRects,
                  exitRects: _exitRects,
                  towerRects: _towerRects,
                  onChangedEntranceRects: (next) {
                    setState(
                      () => _entranceRects = List<GridRect>.from(next),
                    );
                    _logDraftChanged('entrance');
                  },
                  onChangedExitRects: (next) {
                    setState(() => _exitRects = List<GridRect>.from(next));
                    _logDraftChanged('exit');
                  },
                  onChangedTowerRects: (next) {
                    setState(() => _towerRects = List<GridRect>.from(next));
                    _logDraftChanged('tower');
                  },
                  parkingAreas: _parkingAreas,
                  onChangedParkingAreas: (next) {
                    setState(
                      () => _parkingAreas = List<ParkingArea>.from(next),
                    );
                    _logDraftChanged('parking');
                  },
                  onChangedCells: (next) {
                    setState(
                      () => _cells = List<ParkingGridCellType>.from(next),
                    );
                    _logDraftChanged('cells');
                  },
                ),
              ),
            ),
            const SizedBox(height: 10),
            _buildToolPalette(context),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: CommonButton(
                    label: '취소',
                    icon: Icons.close_rounded,
                    variant: CommonButtonVariant.secondary,
                    onPressed: _cancel,
                    haptic: CommonHaptic.selection,
                    minHeight: 42,
                    expand: true,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: CommonButton(
                    label: '적용',
                    icon: Icons.check_rounded,
                    onPressed: _apply,
                    haptic: CommonHaptic.medium,
                    minHeight: 42,
                    expand: true,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
