import 'package:flutter/material.dart';

import '../../../../app/utils/developer_operation_status_dialog.dart';
import '../../../../design_system/common_ui/common_ui_components.dart';
import '../../../../design_system/common_ui/common_ui_theme.dart';
import '../../domain/models/parking_grid_model.dart';
import 'models/location_child_settings_draft.dart';
import 'widgets/parking_grid_child_rect_selector.dart';

class LocationChildExclusionEditorDialog extends StatefulWidget {
  const LocationChildExclusionEditorDialog({
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
  State<LocationChildExclusionEditorDialog> createState() =>
      _LocationChildExclusionEditorDialogState();
}

class _LocationChildExclusionEditorDialogState
    extends State<LocationChildExclusionEditorDialog> {
  late LocationChildSettingsDraft _draft;
  bool _reduceMotion = false;

  @override
  void initState() {
    super.initState();
    _draft = widget.initialDraft.detached().reconciled(
      parentGrid: widget.parentGrid,
      siblings: widget.siblings,
    );
    final feedback = _feedback;
    widget.trace.log(
      '자식구역 제외 editor open candidate=${feedback.candidateCount} occupied=${feedback.occupiedCount} reusable=${feedback.reusableOverlapCount} userExcluded=${feedback.userExcludedCount} effective=${feedback.effectiveCount}',
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
  }

  LocationChildAllocationFeedback get _feedback => _draft.feedback(
        parentGrid: widget.parentGrid,
        siblings: widget.siblings,
      );

  void _updateSelected(Set<String> selected) {
    final feedback = _feedback;
    final available = feedback.candidateSlotAreaIds
        .where((id) => !feedback.occupiedByOtherChildAreaIds.contains(id))
        .toSet();
    final excluded = available.where((id) => !selected.contains(id)).toSet();
    setState(() {
      _draft = _draft.copyWith(userExcludedSlotAreaIds: excluded);
    });
    final next = _feedback;
    widget.trace.log(
      '자식구역 제외 selection_changed userExcluded=${next.userExcludedCount} occupied=${next.occupiedCount} effective=${next.effectiveCount}',
    );
  }

  void _selectAllAvailable() {
    final feedback = _feedback;
    final available = feedback.candidateSlotAreaIds
        .where((id) => !feedback.occupiedByOtherChildAreaIds.contains(id))
        .toSet();
    _updateSelected(available);
  }

  void _excludeAllAvailable() {
    _updateSelected(<String>{});
  }

  void _cancel() {
    widget.trace.log('자식구역 제외 editor cancel');
    Navigator.of(context, rootNavigator: true).pop(false);
  }

  void _apply() {
    final feedback = _feedback;
    if (feedback.effectiveCount <= 0) {
      widget.trace.log('자식구역 제외 apply blocked reason=no_effective_slot');
      return;
    }
    widget.trace.log(
      '자식구역 제외 apply candidate=${feedback.candidateCount} occupied=${feedback.occupiedCount} reusable=${feedback.reusableOverlapCount} userExcluded=${feedback.userExcludedCount} effective=${feedback.effectiveCount}',
    );
    widget.onApply(_draft.reconciled(
      parentGrid: widget.parentGrid,
      siblings: widget.siblings,
    ));
    Navigator.of(context, rootNavigator: true).pop(true);
  }

  Future<void> _showDeveloperTrace() async {
    widget.trace.log('자식구역 제외 developer status requested');
    await widget.trace.showSnapshotStatusDialog(
      context,
      title: '자식구역 제외 영역 편집 로그',
      description: '자동 제외와 사용자 제외의 debugPrint 코드를 확인하고 복사할 수 있습니다.',
    );
  }

  Widget _statusLine(
    BuildContext context,
    String label,
    String value,
    Color color,
  ) {
    final tokens = CommonUiTheme.of(context);
    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 7),
        Expanded(
          child: Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: tokens.textSecondary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        AnimatedSwitcher(
          duration: _reduceMotion ? Duration.zero : CommonUiMotion.selection,
          child: Text(
            value,
            key: ValueKey<String>('$label-$value'),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w900,
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
    final feedback = _feedback;
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
                    '제외 영역 설정',
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
            const SizedBox(height: 8),
            Text(
              '직사각형 안에서 현재 자식구역이 실제 사용할 주차 슬롯을 선택합니다. 다른 자식구역이 실제 사용하는 슬롯은 선택할 수 없고, 기존 자식구역에서 제외된 슬롯은 다시 사용할 수 있습니다.',
              style: textTheme.bodySmall?.copyWith(
                color: tokens.textSecondary,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: ParkingGridChildRectSelector(
                grid: widget.parentGrid,
                value: _draft.rect,
                onChanged: (_) {},
                selectedParkingAreaIds: feedback.effectiveSlotAreaIds,
                disabledParkingAreaIds: feedback.occupiedByOtherChildAreaIds,
                occupiedParkingAreaIds: feedback.occupiedByOtherChildAreaIds,
                reusableParkingAreaIds: feedback.reusableOverlapAreaIds,
                excludedParkingAreaIds: feedback.userExcludedAreaIds,
                onChangedSelectedParkingAreaIds: _updateSelected,
                parkingAreaPickMode: true,
                squareLock: false,
                showHint: false,
                showParkingAreaCountHint: false,
                showAxisIndex: true,
              ),
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.fromLTRB(10, 9, 10, 9),
              decoration: BoxDecoration(
                color: tokens.surface,
                borderRadius: BorderRadius.circular(CommonUiShapes.control),
                border: Border.all(color: tokens.borderSubtle),
              ),
              child: Column(
                children: [
                  _statusLine(context, '직사각형 후보', '${feedback.candidateCount}개', tokens.accent),
                  const SizedBox(height: 5),
                  _statusLine(context, '다른 자식 실제 점유 자동 제외', '${feedback.occupiedCount}개', tokens.warning),
                  const SizedBox(height: 5),
                  _statusLine(context, '기존 자식 제외 슬롯 재사용 가능', '${feedback.reusableOverlapCount}개', tokens.success),
                  const SizedBox(height: 5),
                  _statusLine(context, '현재 자식 사용자 제외', '${feedback.userExcludedCount}개', tokens.danger),
                  const SizedBox(height: 5),
                  _statusLine(context, '실제 자식 주차 슬롯', '${feedback.effectiveCount}개', tokens.accent),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: CommonButton(
                    label: '사용 가능 전체 포함',
                    icon: Icons.select_all_rounded,
                    variant: CommonButtonVariant.secondary,
                    onPressed: _selectAllAvailable,
                    haptic: CommonHaptic.selection,
                    minHeight: 40,
                    expand: true,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: CommonButton(
                    label: '사용 가능 전체 제외',
                    icon: Icons.deselect_rounded,
                    variant: CommonButtonVariant.secondary,
                    onPressed: _excludeAllAvailable,
                    haptic: CommonHaptic.selection,
                    minHeight: 40,
                    expand: true,
                  ),
                ),
              ],
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
                    onPressed: feedback.effectiveCount <= 0 ? null : _apply,
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
