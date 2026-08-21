import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../app/utils/developer_operation_status_dialog.dart';
import '../../../../design_system/common_ui/common_ui_components.dart';
import '../../../../design_system/common_ui/common_ui_theme.dart';
import '../../../../shared/secondary/application/secondary_location_workspace_state.dart';
import '../../../../shared/secondary/widgets/ops_console_widgets.dart';
import '../../domain/models/grid_rect.dart';
import '../../domain/models/parking_grid_model.dart';
import 'models/location_parent_settings_draft.dart';
import 'widgets/parking_grid_preview.dart';

class LocationParentSectionEditorDialog extends StatefulWidget {
  const LocationParentSectionEditorDialog({
    super.key,
    required this.section,
    required this.initialDraft,
    required this.editMode,
    required this.trace,
    required this.onApply,
  });

  final LocationParentSettingsSection section;
  final LocationParentSettingsDraft initialDraft;
  final bool editMode;
  final DeveloperOperationTrace trace;
  final ValueChanged<LocationParentSettingsDraft> onApply;

  @override
  State<LocationParentSectionEditorDialog> createState() =>
      _LocationParentSectionEditorDialogState();
}

class _LocationParentSectionEditorDialogState
    extends State<LocationParentSectionEditorDialog> {
  static const int _minGridSize = 2;
  static const int _maxGridSize = 20;

  late final TextEditingController _nameController;
  late final TextEditingController _sizeController;
  late ParkingGridModel _localGrid;
  bool _submitted = false;
  bool _reduceMotion = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.initialDraft.name);
    _localGrid = LocationParentSettingsDraft.detachedParkingGrid(
      widget.initialDraft.parkingGrid,
    );
    final initialSize = _localGrid.rows > _localGrid.cols
        ? _localGrid.rows
        : _localGrid.cols;
    _sizeController = TextEditingController(text: initialSize.toString());
    widget.trace.log(
      '부모구역 section editor open section=${widget.section.name} editMode=${widget.editMode} rows=${_localGrid.rows} cols=${_localGrid.cols}',
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _sizeController.dispose();
    super.dispose();
  }

  String get _title {
    switch (widget.section) {
      case LocationParentSettingsSection.identity:
        return '부모구역 기본 정보';
      case LocationParentSettingsSection.size:
        return '부모구역 크기';
      case LocationParentSettingsSection.layout:
        return '도면 작업';
    }
  }

  String get _nameError {
    final name = _nameController.text.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (name.isEmpty) return '부모구역명을 입력해 주세요.';
    if (name.length > 40) return '부모구역명은 40자 이하로 입력해 주세요.';
    return '';
  }

  int? get _size => int.tryParse(_sizeController.text.trim());

  String get _sizeError {
    final value = _size;
    if (value == null) return '그리드 크기를 입력해 주세요.';
    if (value < _minGridSize || value > _maxGridSize) {
      return '그리드 크기는 $_minGridSize~$_maxGridSize 범위여야 합니다.';
    }
    return '';
  }

  List<GridRect> _filterRectsWithin(
    List<GridRect> values,
    int rows,
    int cols,
  ) {
    return values.where((raw) {
      final rect = raw.normalized();
      return rect.r0 >= 0 &&
          rect.c0 >= 0 &&
          rect.r1 < rows &&
          rect.c1 < cols;
    }).toList(growable: false);
  }

  ParkingGridModel _resizeGrid(
    ParkingGridModel source, {
    required int rows,
    required int cols,
  }) {
    final cells = List<ParkingGridCellType>.filled(
      rows * cols,
      ParkingGridCellType.empty,
      growable: false,
    );
    final copyRows = source.rows < rows ? source.rows : rows;
    final copyCols = source.cols < cols ? source.cols : cols;
    for (var r = 0; r < copyRows; r++) {
      for (var c = 0; c < copyCols; c++) {
        final oldIndex = r * source.cols + c;
        final newIndex = r * cols + c;
        if (oldIndex >= 0 && oldIndex < source.cells.length) {
          cells[newIndex] = source.cells[oldIndex];
        }
      }
    }

    final road2 = <int>[];
    for (final oldIndex in source.road2Cells) {
      if (oldIndex < 0 || oldIndex >= source.cells.length) continue;
      final r = oldIndex ~/ source.cols;
      final c = oldIndex % source.cols;
      if (r >= rows || c >= cols) continue;
      final newIndex = r * cols + c;
      if (cells[newIndex] == ParkingGridCellType.road) road2.add(newIndex);
    }

    final parkingAreas = source.parkingAreas.where((area) {
      return area.r0 >= 0 &&
          area.c0 >= 0 &&
          area.r1 < rows &&
          area.c1 < cols;
    }).toList(growable: false);

    return ParkingGridModel.fromEnumCells(
      rows: rows,
      cols: cols,
      cells: cells,
      parkingAreas: parkingAreas,
      entranceRects: _filterRectsWithin(source.entranceRects, rows, cols),
      exitRects: _filterRectsWithin(source.exitRects, rows, cols),
      towerRects: _filterRectsWithin(source.towerRects, rows, cols),
      road2Cells: road2..sort(),
    );
  }

  void _apply() {
    setState(() => _submitted = true);
    switch (widget.section) {
      case LocationParentSettingsSection.identity:
        if (_nameError.isNotEmpty) {
          widget.trace.log('부모구역 기본 정보 validation fail reason=$_nameError');
          return;
        }
        final name = _nameController.text.trim().replaceAll(RegExp(r'\s+'), ' ');
        widget.trace.log('부모구역 기본 정보 apply nameLength=${name.length}');
        widget.onApply(widget.initialDraft.copyWith(name: name));
        Navigator.of(context, rootNavigator: true).pop(true);
        return;
      case LocationParentSettingsSection.size:
        if (_sizeError.isNotEmpty) {
          widget.trace.log('부모구역 크기 validation fail reason=$_sizeError');
          return;
        }
        final nextSize = _size!;
        final next = _resizeGrid(
          _localGrid,
          rows: nextSize,
          cols: nextSize,
        );
        widget.trace.log(
          '부모구역 크기 apply from=${_localGrid.rows}x${_localGrid.cols} to=${next.rows}x${next.cols} parkingRemoved=${_localGrid.parkingAreas.length - next.parkingAreas.length} entranceRemoved=${_localGrid.entranceRects.length - next.entranceRects.length} exitRemoved=${_localGrid.exitRects.length - next.exitRects.length} towerRemoved=${_localGrid.towerRects.length - next.towerRects.length}',
        );
        widget.onApply(widget.initialDraft.copyWith(parkingGrid: next));
        Navigator.of(context, rootNavigator: true).pop(true);
        return;
      case LocationParentSettingsSection.layout:
        Navigator.of(context, rootNavigator: true).pop(false);
        return;
    }
  }

  void _cancel() {
    widget.trace.log('부모구역 section editor cancel section=${widget.section.name}');
    Navigator.of(context, rootNavigator: true).pop(false);
  }

  Future<void> _showDeveloperTrace() async {
    widget.trace.log('부모구역 section developer status requested section=${widget.section.name}');
    await widget.trace.showSnapshotStatusDialog(
      context,
      title: '$_title 편집 로그',
      description: '현재 편집 동작의 debugPrint 코드를 확인하고 복사할 수 있습니다.',
    );
  }

  Widget _buildIdentity(BuildContext context) {
    final error = _submitted && _nameError.isNotEmpty ? _nameError : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _nameController,
          autofocus: !widget.editMode,
          readOnly: widget.editMode,
          maxLength: 40,
          textInputAction: TextInputAction.done,
          inputFormatters: <TextInputFormatter>[
            FilteringTextInputFormatter.deny(RegExp(r'[\n\r]')),
          ],
          onChanged: (_) {
            if (_submitted) setState(() {});
          },
          onSubmitted: (_) => _apply(),
          decoration: opsInputDecoration(
            context,
            label: '부모구역명',
            prefixIcon: const Icon(Icons.location_on_rounded),
            errorText: error,
          ),
        ),
        if (widget.editMode)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Text(
              '기존 부모구역의 이름은 변경하지 않고 도면 설정만 수정합니다.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: CommonUiTheme.of(context).textSecondary,
                    height: 1.35,
                  ),
            ),
          ),
      ],
    );
  }

  Widget _buildSize(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final error = _submitted && _sizeError.isNotEmpty ? _sizeError : null;
    final nextSize = _size;
    ParkingGridModel? preview;
    if (nextSize != null &&
        nextSize >= _minGridSize &&
        nextSize <= _maxGridSize) {
      preview = _resizeGrid(
        _localGrid,
        rows: nextSize,
        cols: nextSize,
      );
    }
    final displayGrid = preview ?? _localGrid;

    int structureCount(ParkingGridModel grid) {
      return grid.cells
          .where((cell) => cell != ParkingGridCellType.empty)
          .length;
    }

    final structureRemoved = preview == null
        ? 0
        : structureCount(_localGrid) - structureCount(preview);
    final parkingRemoved = preview == null
        ? 0
        : _localGrid.parkingAreas.length - preview.parkingAreas.length;
    final entranceRemoved = preview == null
        ? 0
        : _localGrid.entranceRects.length - preview.entranceRects.length;
    final exitRemoved = preview == null
        ? 0
        : _localGrid.exitRects.length - preview.exitRects.length;
    final towerRemoved = preview == null
        ? 0
        : _localGrid.towerRects.length - preview.towerRects.length;
    final affected = structureRemoved +
        parkingRemoved +
        entranceRemoved +
        exitRemoved +
        towerRemoved;

    void adjust(int delta) {
      final current = nextSize ??
          (_localGrid.rows > _localGrid.cols
              ? _localGrid.rows
              : _localGrid.cols);
      final value = (current + delta).clamp(_minGridSize, _maxGridSize);
      _sizeController.text = value.toString();
      setState(() {});
      widget.trace.log(
        '부모구역 크기 조절 localSize=$value preview=${value}x$value',
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: Center(
            child: SingleChildScrollView(
              child: AnimatedSwitcher(
                duration:
                    _reduceMotion ? Duration.zero : CommonUiMotion.selection,
                switchInCurve: CommonUiMotion.enter,
                switchOutCurve: CommonUiMotion.exit,
                transitionBuilder: (child, animation) => FadeTransition(
                  opacity: animation,
                  child: ScaleTransition(
                    scale:
                        Tween<double>(begin: .985, end: 1).animate(animation),
                    child: child,
                  ),
                ),
                child: Container(
                  key: ValueKey<String>(displayGrid.toJson().toString()),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: tokens.canvas,
                    border: Border.all(color: tokens.borderSubtle),
                    borderRadius:
                        BorderRadius.circular(CommonUiShapes.control),
                  ),
                  child: ParkingGridPreview(
                    grid: displayGrid,
                    maxExtent: 360,
                    showLegend: false,
                    showParkingAreaLabels: false,
                    showChildRegions: false,
                    showChildRegionLabels: false,
                    showAllChildRegionLabels: false,
                    showChildSlotNumbers: false,
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            CommonIconButton(
              icon: Icons.remove_rounded,
              tooltip: '크기 줄이기',
              onPressed: nextSize != null && nextSize <= _minGridSize
                  ? null
                  : () => adjust(-1),
              haptic: CommonHaptic.selection,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: _sizeController,
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                inputFormatters: <TextInputFormatter>[
                  FilteringTextInputFormatter.digitsOnly,
                ],
                onChanged: (value) {
                  setState(() {});
                  widget.trace.log(
                    '부모구역 크기 입력 localSize=${value.trim().isEmpty ? 'empty' : value.trim()}',
                  );
                },
                decoration: opsInputDecoration(
                  context,
                  label: '그리드 크기',
                  prefixIcon: const Icon(Icons.aspect_ratio_rounded),
                  errorText: error,
                  suffixText: '× 동일 크기',
                ),
              ),
            ),
            const SizedBox(width: 10),
            CommonIconButton(
              icon: Icons.add_rounded,
              tooltip: '크기 늘리기',
              onPressed: nextSize != null && nextSize >= _maxGridSize
                  ? null
                  : () => adjust(1),
              haptic: CommonHaptic.selection,
            ),
          ],
        ),
        const SizedBox(height: 12),
        AnimatedContainer(
          duration:
              _reduceMotion ? Duration.zero : CommonUiMotion.selection,
          curve: CommonUiMotion.standard,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: affected > 0
                ? tokens.warningContainer.withOpacity(.5)
                : tokens.surface,
            border: Border.all(
              color: affected > 0 ? tokens.warning : tokens.borderSubtle,
            ),
            borderRadius: BorderRadius.circular(CommonUiShapes.control),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                preview == null
                    ? '크기 값을 확인해 주세요.'
                    : '${_localGrid.rows}×${_localGrid.cols} → ${preview.rows}×${preview.cols}',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: tokens.textPrimary,
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: 5),
              Text(
                affected == 0
                    ? '현재 구조와 주차 구역, 시설 영역은 모두 유지됩니다.'
                    : '범위를 벗어나는 항목: 구조 셀 $structureRemoved · 주차면 $parkingRemoved · 입구 $entranceRemoved · 출구 $exitRemoved · 타워 $towerRemoved',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color:
                          affected > 0 ? tokens.warning : tokens.textSecondary,
                      height: 1.35,
                    ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final textTheme = Theme.of(context).textTheme;
    return Material(
      color: Colors.transparent,
      child: Container(
        decoration: BoxDecoration(
          color: tokens.surfaceRaised,
          borderRadius: BorderRadius.circular(CommonUiShapes.dialog),
          border: Border.all(color: tokens.borderSubtle),
        ),
        padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    _title,
                    style: textTheme.titleMedium?.copyWith(
                      color: tokens.textPrimary,
                      fontWeight: FontWeight.w900,
                    ),
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
            const SizedBox(height: 18),
            Expanded(
              child: AnimatedSwitcher(
                duration: _reduceMotion ? Duration.zero : CommonUiMotion.component,
                switchInCurve: CommonUiMotion.enter,
                switchOutCurve: CommonUiMotion.exit,
                child: widget.section == LocationParentSettingsSection.identity
                    ? _buildIdentity(context)
                    : _buildSize(context),
              ),
            ),
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
