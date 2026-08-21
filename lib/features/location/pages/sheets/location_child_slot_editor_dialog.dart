import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../app/utils/developer_operation_status_dialog.dart';
import '../../../../design_system/common_ui/common_ui_components.dart';
import '../../../../design_system/common_ui/common_ui_theme.dart';
import '../../../../shared/secondary/widgets/ops_console_widgets.dart';
import '../../domain/models/location_model.dart';
import '../../domain/models/parking_grid_model.dart';
import 'models/location_child_settings_draft.dart';
import 'widgets/parking_grid_preview.dart';

class LocationChildSlotEditorDialog extends StatefulWidget {
  const LocationChildSlotEditorDialog({
    super.key,
    required this.initialDraft,
    required this.parentGrid,
    required this.siblings,
    required this.trace,
    required this.onApply,
  });

  final LocationChildSettingsDraft initialDraft;
  final ParkingGridModel parentGrid;
  final List<LocationChildAllocationSnapshot> siblings;
  final DeveloperOperationTrace trace;
  final ValueChanged<LocationChildSettingsDraft> onApply;

  @override
  State<LocationChildSlotEditorDialog> createState() =>
      _LocationChildSlotEditorDialogState();
}

class _LocationChildSlotEditorDialogState
    extends State<LocationChildSlotEditorDialog> {
  late LocationChildSettingsDraft _draft;
  final Map<String, TextEditingController> _controllers =
      <String, TextEditingController>{};
  final Map<String, FocusNode> _focusNodes = <String, FocusNode>{};
  final Map<String, GlobalKey> _rowKeys = <String, GlobalKey>{};
  final ScrollController _listController = ScrollController();
  bool _submitted = false;
  bool _reduceMotion = false;
  String? _activeAreaId;

  @override
  void initState() {
    super.initState();
    _draft = widget.initialDraft.detached().reconciled(
      parentGrid: widget.parentGrid,
      siblings: widget.siblings,
    );
    _syncEditingResources();
    widget.trace.log(
      '자식구역 슬롯 번호 editor open effective=${_feedback.effectiveCount} assigned=$_assignedCount',
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    for (final node in _focusNodes.values) {
      node.dispose();
    }
    _listController.dispose();
    super.dispose();
  }

  LocationChildAllocationFeedback get _feedback => _draft.feedback(
        parentGrid: widget.parentGrid,
        siblings: widget.siblings,
      );

  List<ParkingArea> get _effectiveAreas {
    final ids = _feedback.effectiveSlotAreaIds;
    final out = widget.parentGrid.parkingAreas
        .where((area) => ids.contains(area.id.trim()))
        .toList();
    out.sort((a, b) {
      final row = a.r0.compareTo(b.r0);
      if (row != 0) return row;
      final col = a.c0.compareTo(b.c0);
      if (col != 0) return col;
      return a.id.compareTo(b.id);
    });
    return out;
  }

  int get _assignedCount {
    final ids = _feedback.effectiveSlotAreaIds;
    return _draft.slotNumbersByAreaId.entries
        .where((entry) => ids.contains(entry.key) && entry.value > 0)
        .length;
  }

  FocusNode _createFocusNode(String areaId) {
    final node = FocusNode();
    node.addListener(() {
      if (!mounted || !node.hasFocus) return;
      _activateArea(
        areaId,
        source: 'slot_input_focus',
        requestFocus: false,
        ensureVisible: true,
      );
    });
    return node;
  }

  void _syncEditingResources() {
    final ids = _feedback.effectiveSlotAreaIds;
    final removeControllers =
        _controllers.keys.where((id) => !ids.contains(id)).toList();
    for (final id in removeControllers) {
      _controllers.remove(id)?.dispose();
      _focusNodes.remove(id)?.dispose();
      _rowKeys.remove(id);
    }
    if (_activeAreaId != null && !ids.contains(_activeAreaId)) {
      _activeAreaId = null;
    }
    for (final area in _effectiveAreas) {
      final id = area.id.trim();
      _controllers.putIfAbsent(
        id,
        () => TextEditingController(
          text: (_draft.slotNumbersByAreaId[id] ?? 0) > 0
              ? _draft.slotNumbersByAreaId[id].toString()
              : '',
        ),
      );
      _focusNodes.putIfAbsent(id, () => _createFocusNode(id));
      _rowKeys.putIfAbsent(id, () => GlobalKey());
    }
  }

  void _ensureRowVisible(String areaId) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final rowContext = _rowKeys[areaId]?.currentContext;
      if (rowContext != null) {
        Scrollable.ensureVisible(
          rowContext,
          duration: _reduceMotion ? Duration.zero : CommonUiMotion.selection,
          curve: CommonUiMotion.standard,
          alignment: .42,
        );
        return;
      }
      if (!_listController.hasClients) return;
      final areas = _effectiveAreas;
      final index = areas.indexWhere((area) => area.id.trim() == areaId);
      if (index < 0) return;
      final target = (index * 78.0)
          .clamp(0.0, _listController.position.maxScrollExtent)
          .toDouble();
      _listController
          .animateTo(
            target,
            duration: _reduceMotion
                ? Duration.zero
                : CommonUiMotion.selection,
            curve: CommonUiMotion.standard,
          )
          .whenComplete(() {
        if (!mounted) return;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          final context = _rowKeys[areaId]?.currentContext;
          if (context == null) return;
          Scrollable.ensureVisible(
            context,
            duration:
                _reduceMotion ? Duration.zero : CommonUiMotion.selection,
            curve: CommonUiMotion.standard,
            alignment: .42,
          );
        });
      });
    });
  }

  void _activateArea(
    String areaId, {
    required String source,
    bool requestFocus = false,
    bool ensureVisible = false,
  }) {
    if (!_feedback.effectiveSlotAreaIds.contains(areaId)) return;
    final changed = _activeAreaId != areaId;
    if (changed && mounted) {
      setState(() => _activeAreaId = areaId);
      widget.trace.log('자식구역 slot_focus_changed areaId=$areaId source=$source');
    }
    if (requestFocus) {
      final node = _focusNodes[areaId];
      if (node != null && !node.hasFocus) node.requestFocus();
    }
    if (ensureVisible) _ensureRowVisible(areaId);
  }

  void _focusAreaFromGrid(String areaId) {
    if (!_feedback.effectiveSlotAreaIds.contains(areaId)) return;
    widget.trace.log('자식구역 slot_grid_tapped areaId=$areaId');
    _activateArea(
      areaId,
      source: 'slot_grid_tapped',
      requestFocus: true,
      ensureVisible: true,
    );
  }

  String get _validationError {
    final ids = _feedback.effectiveSlotAreaIds;
    if (ids.isEmpty) return '번호를 설정할 실제 자식 주차 슬롯이 없습니다.';
    final numbers = <int>{};
    for (final id in ids) {
      final number = _draft.slotNumbersByAreaId[id];
      if (number == null || number <= 0) {
        return '모든 실제 자식 주차 슬롯에 번호를 입력해 주세요.';
      }
      if (!numbers.add(number)) {
        return '같은 자식구역 안에서 슬롯 번호는 중복될 수 없습니다.';
      }
    }
    return '';
  }

  void _setNumber(String areaId, String raw) {
    final value = int.tryParse(raw.trim());
    final next = Map<String, int>.from(_draft.slotNumbersByAreaId);
    if (value == null || value <= 0) {
      next.remove(areaId);
    } else {
      next[areaId] = value;
    }
    setState(() {
      _activeAreaId = areaId;
      _draft = _draft.copyWith(slotNumbersByAreaId: next);
    });
    widget.trace.log(
      '자식구역 slot_number_changed areaId=$areaId number=${value ?? 0} assigned=$_assignedCount total=${_feedback.effectiveCount}',
    );
  }

  void _autoNumber() {
    final next = <String, int>{};
    var number = 1;
    for (final area in _effectiveAreas) {
      final id = area.id.trim();
      next[id] = number;
      _controllers[id]?.text = number.toString();
      number += 1;
    }
    setState(() {
      _draft = _draft.copyWith(slotNumbersByAreaId: next);
      _submitted = false;
    });
    widget.trace.log('자식구역 slot_numbers_auto_assigned count=${next.length}');
  }

  List<ChildSlot> _previewSlots() {
    final byId = <String, ParkingArea>{
      for (final area in widget.parentGrid.parkingAreas) area.id.trim(): area,
    };
    final out = <ChildSlot>[];
    for (final id in _feedback.effectiveSlotAreaIds) {
      final area = byId[id];
      final number = _draft.slotNumbersByAreaId[id];
      if (area == null || number == null || number <= 0) continue;
      out.add(ChildSlot.fromParkingArea(no: number, area: area));
    }
    out.sort((a, b) => a.no.compareTo(b.no));
    return out;
  }

  void _cancel() {
    widget.trace.log('자식구역 슬롯 번호 editor cancel');
    Navigator.of(context, rootNavigator: true).pop(false);
  }

  void _apply() {
    setState(() => _submitted = true);
    final error = _validationError;
    if (error.isNotEmpty) {
      widget.trace.log('자식구역 슬롯 번호 validation fail reason=$error');
      return;
    }
    widget.trace.log(
      '자식구역 슬롯 번호 apply assigned=$_assignedCount total=${_feedback.effectiveCount} activeAreaId=${_activeAreaId ?? ''}',
    );
    widget.onApply(
      _draft.reconciled(
        parentGrid: widget.parentGrid,
        siblings: widget.siblings,
      ),
    );
    Navigator.of(context, rootNavigator: true).pop(true);
  }

  Future<void> _showDeveloperTrace() async {
    widget.trace.log('자식구역 슬롯 번호 developer status requested');
    await widget.trace.showSnapshotStatusDialog(
      context,
      title: '자식구역 슬롯 번호 편집 로그',
      description: '실제 자식 주차구역과 슬롯 번호 변경의 debugPrint 코드를 확인하고 복사할 수 있습니다.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final textTheme = Theme.of(context).textTheme;
    final feedback = _feedback;
    final error = _submitted && _validationError.isNotEmpty
        ? _validationError
        : null;
    final previewSlots = _previewSlots();
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
                Expanded(
                  child: Text(
                    '슬롯 번호 설정',
                    style: textTheme.titleMedium?.copyWith(
                      color: tokens.textPrimary,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                Text(
                  '$_assignedCount / ${feedback.effectiveCount}',
                  style: textTheme.labelLarge?.copyWith(
                    color: _assignedCount == feedback.effectiveCount
                        ? tokens.success
                        : tokens.warning,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(width: 6),
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
            const SizedBox(height: 10),
            Expanded(
              flex: 5,
              child: Center(
                child: AnimatedContainer(
                  duration:
                      _reduceMotion ? Duration.zero : CommonUiMotion.selection,
                  curve: CommonUiMotion.standard,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: tokens.canvas,
                    borderRadius: BorderRadius.circular(CommonUiShapes.control),
                    border: Border.all(
                      color: _activeAreaId == null
                          ? tokens.borderSubtle
                          : tokens.accent.withOpacity(.58),
                      width: _activeAreaId == null ? 1 : 1.5,
                    ),
                  ),
                  child: ParkingGridPreview(
                    grid: widget.parentGrid,
                    maxExtent: 420,
                    showLegend: false,
                    showParkingAreaLabels: false,
                    childRegions: _draft.rect == null
                        ? const <ChildRegionOverlay>[]
                        : <ChildRegionOverlay>[
                            ChildRegionOverlay(
                              id: 'editing-child',
                              rect: _draft.rect!,
                              label: _draft.name.trim().isEmpty
                                  ? '자식구역'
                                  : _draft.name,
                              isSelected: true,
                              useEffectiveShape: true,
                              effectiveParkingAreaIds:
                                  feedback.effectiveSlotAreaIds,
                            ),
                          ],
                    effectiveParkingAreaIds: feedback.effectiveSlotAreaIds,
                    occupiedParkingAreaIds:
                        feedback.occupiedByOtherChildAreaIds,
                    reusableParkingAreaIds: feedback.reusableOverlapAreaIds,
                    excludedParkingAreaIds: feedback.userExcludedAreaIds,
                    showChildSlotNumbers: true,
                    childSlotsToLabel: previewSlots,
                    focusedParkingAreaId: _activeAreaId,
                    onTapParkingArea: _focusAreaFromGrid,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '실제 자식 주차 슬롯 ${feedback.effectiveCount}개',
                    style: textTheme.labelLarge?.copyWith(
                      color: tokens.textPrimary,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                CommonButton(
                  label: '자동 번호',
                  icon: Icons.format_list_numbered_rounded,
                  variant: CommonButtonVariant.secondary,
                  onPressed:
                      feedback.effectiveCount == 0 ? null : _autoNumber,
                  haptic: CommonHaptic.selection,
                  minHeight: 38,
                ),
              ],
            ),
            if (error != null) ...[
              const SizedBox(height: 6),
              Text(
                error,
                style: textTheme.bodySmall?.copyWith(
                  color: tokens.danger,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
            const SizedBox(height: 8),
            Expanded(
              flex: 4,
              child: ListView.separated(
                controller: _listController,
                itemCount: _effectiveAreas.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final area = _effectiveAreas[index];
                  final id = area.id.trim();
                  final controller = _controllers[id]!;
                  final focusNode = _focusNodes[id]!;
                  final active = _activeAreaId == id;
                  return Container(
                    key: _rowKeys[id],
                    child: GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      onTap: () => _activateArea(
                        id,
                        source: 'slot_row_tapped',
                        requestFocus: true,
                      ),
                      child: AnimatedContainer(
                        duration: _reduceMotion
                            ? Duration.zero
                            : CommonUiMotion.selection,
                        curve: CommonUiMotion.standard,
                        padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
                        decoration: BoxDecoration(
                          color: active
                              ? tokens.accentContainer.withOpacity(.42)
                              : Colors.transparent,
                          borderRadius:
                              BorderRadius.circular(CommonUiShapes.control),
                          border: Border.all(
                            color: active
                                ? tokens.accent.withOpacity(.62)
                                : Colors.transparent,
                            width: active ? 1.4 : 1,
                          ),
                        ),
                        child: Row(
                          children: [
                            AnimatedContainer(
                              duration: _reduceMotion
                                  ? Duration.zero
                                  : CommonUiMotion.selection,
                              width: 4,
                              height: active ? 38 : 18,
                              decoration: BoxDecoration(
                                color: active
                                    ? tokens.accent
                                    : tokens.borderSubtle,
                                borderRadius: BorderRadius.circular(999),
                              ),
                            ),
                            const SizedBox(width: 9),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    area.kind.label,
                                    style: textTheme.bodyMedium?.copyWith(
                                      color: tokens.textPrimary,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'r${area.r0}~${area.r1} · c${area.c0}~${area.c1}',
                                    style: textTheme.bodySmall?.copyWith(
                                      color: tokens.textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 10),
                            SizedBox(
                              width: 132,
                              child: TextField(
                                controller: controller,
                                focusNode: focusNode,
                                keyboardType: TextInputType.number,
                                textAlign: TextAlign.center,
                                inputFormatters: <TextInputFormatter>[
                                  FilteringTextInputFormatter.digitsOnly,
                                ],
                                onTap: () => _activateArea(
                                  id,
                                  source: 'slot_input_tapped',
                                ),
                                onChanged: (value) => _setNumber(id, value),
                                decoration: opsInputDecoration(
                                  context,
                                  label: '슬롯 번호',
                                  prefixIcon:
                                      const Icon(Icons.numbers_rounded),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
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
                    onPressed: feedback.effectiveCount == 0 ? null : _apply,
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
