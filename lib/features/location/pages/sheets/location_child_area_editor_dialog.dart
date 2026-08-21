import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../app/utils/developer_operation_status_dialog.dart';
import '../../../../design_system/common_ui/common_ui_components.dart';
import '../../../../design_system/common_ui/common_ui_theme.dart';
import '../../../../shared/secondary/widgets/ops_console_widgets.dart';
import '../../domain/models/grid_rect.dart';
import '../../domain/models/parking_grid_model.dart';
import 'models/location_child_settings_draft.dart';
import 'widgets/parking_grid_child_rect_selector.dart';

class LocationChildAreaEditorDialog extends StatefulWidget {
  const LocationChildAreaEditorDialog({
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
  State<LocationChildAreaEditorDialog> createState() =>
      _LocationChildAreaEditorDialogState();
}

class _LocationChildAreaEditorDialogState
    extends State<LocationChildAreaEditorDialog> {
  static const double _statusPanelHeight = 128;

  late LocationChildSettingsDraft _draft;
  late final TextEditingController _capacityController;
  bool _submitted = false;
  bool _reduceMotion = false;

  @override
  void initState() {
    super.initState();
    _draft = widget.initialDraft.detached().reconciled(
      parentGrid: widget.parentGrid,
      siblings: widget.siblings,
    );
    _capacityController = TextEditingController(
      text: _draft.towerCapacity > 0 ? _draft.towerCapacity.toString() : '',
    );
    final feedback = _feedback;
    widget.trace.log(
      '자식구역 영역 editor open mode=${_draft.isTower ? 'tower' : 'normal'} rect=${_draft.rect?.normalized()} candidate=${feedback.candidateCount} occupied=${feedback.occupiedCount} reusable=${feedback.reusableOverlapCount} effective=${feedback.effectiveCount}',
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
  }

  @override
  void dispose() {
    _capacityController.dispose();
    super.dispose();
  }

  LocationChildAllocationFeedback get _feedback => _draft.feedback(
        parentGrid: widget.parentGrid,
        siblings: widget.siblings,
      );

  String get _areaError {
    final rect = _draft.rect;
    if (rect == null) {
      return _draft.isTower
          ? '주차 타워 영역을 선택해 주세요.'
          : '자식구역 직사각형을 선택해 주세요.';
    }
    final normalized = rect.normalized();
    if (normalized.r0 < 0 ||
        normalized.c0 < 0 ||
        normalized.r1 >= widget.parentGrid.rows ||
        normalized.c1 >= widget.parentGrid.cols) {
      return '자식구역이 부모 도면 범위를 벗어납니다.';
    }
    if (_draft.isTower) {
      final registered = widget.parentGrid.towerRects
          .map((value) => value.normalized())
          .any((value) => value == normalized);
      if (!registered) {
        return '부모 도면에 등록된 주차 타워 영역을 선택해 주세요.';
      }
      final overlapsSibling = widget.siblings
          .map((sibling) => sibling.rect?.normalized())
          .whereType<GridRect>()
          .any((value) => value.overlaps(normalized));
      if (overlapsSibling) {
        return '선택한 주차 타워 영역이 기존 자식구역과 겹칩니다.';
      }
      final capacity = int.tryParse(_capacityController.text.trim());
      if (capacity == null || capacity <= 0) {
        return '타워 수용 대수는 1 이상이어야 합니다.';
      }
      return '';
    }
    if (_feedback.effectiveCount <= 0) {
      return '실제로 사용할 수 있는 주차 슬롯이 1개 이상 필요합니다.';
    }
    return '';
  }

  void _setMode(bool tower) {
    if (_draft.isTower == tower) return;
    setState(() {
      _draft = _draft.copyWith(
        isTower: tower,
        userExcludedSlotAreaIds: <String>{},
        slotNumbersByAreaId: <String, int>{},
        clearRect: true,
      );
      _submitted = false;
    });
    widget.trace.log(
      '자식구역 영역 mode_changed mode=${tower ? 'tower' : 'normal'}',
    );
  }

  void _setRect(GridRect? value) {
    final normalized = value?.normalized();
    if (_draft.rect?.normalized() == normalized) return;
    setState(() {
      _draft = _draft.copyWith(
        rect: normalized,
        clearRect: normalized == null,
      );
    });
    final feedback = _feedback;
    widget.trace.log(
      '자식구역 raw_rect_changed rect=$normalized candidate=${feedback.candidateCount} occupied=${feedback.occupiedCount} reusable=${feedback.reusableOverlapCount} userExcluded=${feedback.userExcludedCount} effective=${feedback.effectiveCount}',
    );
  }

  void _cancel() {
    widget.trace.log('자식구역 영역 editor cancel');
    Navigator.of(context, rootNavigator: true).pop(false);
  }

  void _apply() {
    setState(() => _submitted = true);
    final error = _areaError;
    if (error.isNotEmpty) {
      widget.trace.log('자식구역 영역 validation fail reason=$error');
      return;
    }
    final capacity = int.tryParse(_capacityController.text.trim()) ?? 0;
    var next = _draft.copyWith(
      towerCapacity: _draft.isTower ? capacity : _feedback.effectiveCount,
    );
    next = next.reconciled(
      parentGrid: widget.parentGrid,
      siblings: widget.siblings,
    );
    final feedback = next.feedback(
      parentGrid: widget.parentGrid,
      siblings: widget.siblings,
    );
    widget.trace.log(
      '자식구역 영역 apply mode=${next.isTower ? 'tower' : 'normal'} rect=${next.rect?.normalized()} candidate=${feedback.candidateCount} occupied=${feedback.occupiedCount} reusable=${feedback.reusableOverlapCount} userExcluded=${feedback.userExcludedCount} effective=${feedback.effectiveCount} capacity=${next.isTower ? next.towerCapacity : feedback.effectiveCount}',
    );
    widget.onApply(next);
    Navigator.of(context, rootNavigator: true).pop(true);
  }

  Future<void> _showDeveloperTrace() async {
    widget.trace.log('자식구역 영역 developer status requested');
    await widget.trace.showSnapshotStatusDialog(
      context,
      title: '자식구역 영역 편집 로그',
      description: '직사각형과 실제 slot ownership 계산의 debugPrint 코드를 확인하고 복사할 수 있습니다.',
    );
  }

  Widget _metric(
    BuildContext context, {
    required String label,
    required int value,
    required Color color,
  }) {
    final tokens = CommonUiTheme.of(context);
    return Expanded(
      child: AnimatedContainer(
        duration: _reduceMotion ? Duration.zero : CommonUiMotion.selection,
        curve: CommonUiMotion.standard,
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 8),
        decoration: BoxDecoration(
          color: color.withOpacity(.09),
          borderRadius: BorderRadius.circular(CommonUiShapes.control),
          border: Border.all(color: color.withOpacity(.42)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedSwitcher(
              duration: _reduceMotion ? Duration.zero : CommonUiMotion.selection,
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: ScaleTransition(
                  scale: Tween<double>(begin: .94, end: 1).animate(animation),
                  child: child,
                ),
              ),
              child: Text(
                '$value',
                key: ValueKey<int>(value),
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: color,
                      fontWeight: FontWeight.w900,
                    ),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: tokens.textSecondary,
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ],
        ),
      ),
    );
  }

  String _normalStatusText(LocationChildAllocationFeedback feedback) {
    if (feedback.occupiedCount > 0 && feedback.reusableOverlapCount > 0) {
      return '자동 제외 ${feedback.occupiedCount} · 재사용 가능 ${feedback.reusableOverlapCount} · 실제 ${feedback.effectiveCount}';
    }
    if (feedback.occupiedCount > 0) {
      return '다른 자식구역 실제 점유 ${feedback.occupiedCount}개 자동 제외 · 실제 ${feedback.effectiveCount}';
    }
    if (feedback.reusableOverlapCount > 0) {
      return '기존 자식구역 미소유 ${feedback.reusableOverlapCount}개 재사용 가능 · 실제 ${feedback.effectiveCount}';
    }
    return '현재 직사각형에서 사용할 수 있는 실제 슬롯 ${feedback.effectiveCount}개';
  }

  Widget _animatedStatusText(
    BuildContext context, {
    required String text,
    required Color color,
    required Key key,
  }) {
    return SizedBox(
      height: 24,
      child: AnimatedSwitcher(
        duration: _reduceMotion ? Duration.zero : CommonUiMotion.selection,
        switchInCurve: CommonUiMotion.standard,
        switchOutCurve: CommonUiMotion.standard,
        transitionBuilder: (child, animation) {
          if (_reduceMotion) return child;
          final offset = Tween<Offset>(
            begin: const Offset(0, .18),
            end: Offset.zero,
          ).animate(animation);
          return FadeTransition(
            opacity: animation,
            child: SlideTransition(position: offset, child: child),
          );
        },
        child: Align(
          key: key,
          alignment: Alignment.centerLeft,
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w700,
                ),
          ),
        ),
      ),
    );
  }

  Widget _buildNormalStatusPanel(
    BuildContext context, {
    required LocationChildAllocationFeedback feedback,
    required String? error,
  }) {
    final tokens = CommonUiTheme.of(context);
    return SizedBox(
      height: _statusPanelHeight,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              _metric(
                context,
                label: '후보',
                value: feedback.candidateCount,
                color: tokens.accent,
              ),
              const SizedBox(width: 6),
              _metric(
                context,
                label: '자동 제외',
                value: feedback.occupiedCount,
                color: tokens.warning,
              ),
              const SizedBox(width: 6),
              _metric(
                context,
                label: '재사용 가능',
                value: feedback.reusableOverlapCount,
                color: tokens.success,
              ),
              const SizedBox(width: 6),
              _metric(
                context,
                label: '실제 슬롯',
                value: feedback.effectiveCount,
                color: tokens.accent,
              ),
            ],
          ),
          const SizedBox(height: 7),
          _animatedStatusText(
            context,
            text: _normalStatusText(feedback),
            color: tokens.textSecondary,
            key: ValueKey<String>(
              '${feedback.occupiedCount}:${feedback.reusableOverlapCount}:${feedback.effectiveCount}',
            ),
          ),
          const SizedBox(height: 5),
          _animatedStatusText(
            context,
            text: error ?? '',
            color: tokens.danger,
            key: ValueKey<String>(error ?? ''),
          ),
        ],
      ),
    );
  }

  Widget _buildTowerStatusPanel(
    BuildContext context, {
    required String? error,
  }) {
    final tokens = CommonUiTheme.of(context);
    return SizedBox(
      height: _statusPanelHeight,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 64,
            child: TextField(
              controller: _capacityController,
              keyboardType: TextInputType.number,
              inputFormatters: <TextInputFormatter>[
                FilteringTextInputFormatter.digitsOnly,
              ],
              onChanged: (_) {
                if (_submitted) setState(() {});
                widget.trace.log(
                  '자식구역 타워 capacity input value=${_capacityController.text.trim()}',
                );
              },
              decoration: opsInputDecoration(
                context,
                label: '타워 수용 대수',
                prefixIcon: const Icon(Icons.directions_car_filled_rounded),
              ),
            ),
          ),
          const SizedBox(height: 8),
          _animatedStatusText(
            context,
            text: error ?? '부모 도면에 등록된 주차 타워 영역을 선택합니다.',
            color: error == null ? tokens.textSecondary : tokens.danger,
            key: ValueKey<String>(error ?? 'tower-ready'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final textTheme = Theme.of(context).textTheme;
    final feedback = _feedback;
    final rawError = _areaError;
    final error = _submitted && rawError.isNotEmpty ? rawError : null;
    final gridBorderColor = error != null
        ? tokens.danger.withOpacity(.68)
        : _draft.rect == null
            ? tokens.borderSubtle
            : tokens.accent.withOpacity(.48);

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
                    '자식구역 크기 및 영역',
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
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: CommonButton(
                    label: '일반 자식구역',
                    icon: Icons.crop_landscape_rounded,
                    onPressed: () => _setMode(false),
                    variant: CommonButtonVariant.secondary,
                    selected: !_draft.isTower,
                    haptic: CommonHaptic.selection,
                    minHeight: 40,
                    expand: true,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: CommonButton(
                    label: '주차 타워',
                    icon: Icons.apartment_rounded,
                    onPressed: () => _setMode(true),
                    variant: CommonButtonVariant.secondary,
                    selected: _draft.isTower,
                    haptic: CommonHaptic.selection,
                    minHeight: 40,
                    expand: true,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: AnimatedContainer(
                duration: _reduceMotion ? Duration.zero : CommonUiMotion.selection,
                curve: CommonUiMotion.standard,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: tokens.surface,
                  borderRadius: BorderRadius.circular(CommonUiShapes.control),
                  border: Border.all(
                    color: gridBorderColor,
                    width: 1.5,
                  ),
                ),
                child: ParkingGridChildRectSelector(
                  grid: widget.parentGrid,
                  value: _draft.rect,
                  onChanged: _setRect,
                  selectedParkingAreaIds: feedback.effectiveSlotAreaIds,
                  disabledParkingAreaIds: feedback.occupiedByOtherChildAreaIds,
                  occupiedParkingAreaIds: feedback.occupiedByOtherChildAreaIds,
                  reusableParkingAreaIds: feedback.reusableOverlapAreaIds,
                  excludedParkingAreaIds: feedback.userExcludedAreaIds,
                  squareLock: false,
                  showHint: false,
                  showParkingAreaCountHint: false,
                  showAxisIndex: true,
                  towerRects: widget.parentGrid.towerRects,
                  towerSelectMode: _draft.isTower,
                ),
              ),
            ),
            const SizedBox(height: 10),
            AnimatedSwitcher(
              duration: _reduceMotion ? Duration.zero : CommonUiMotion.selection,
              switchInCurve: CommonUiMotion.standard,
              switchOutCurve: CommonUiMotion.standard,
              transitionBuilder: (child, animation) {
                if (_reduceMotion) return child;
                return FadeTransition(opacity: animation, child: child);
              },
              child: KeyedSubtree(
                key: ValueKey<bool>(_draft.isTower),
                child: _draft.isTower
                    ? _buildTowerStatusPanel(context, error: error)
                    : _buildNormalStatusPanel(
                        context,
                        feedback: feedback,
                        error: error,
                      ),
              ),
            ),
            const SizedBox(height: 12),
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
