import 'package:flutter/material.dart';

import '../../../../design_system/common_ui/common_ui_theme.dart';
import '../../application/commute_pre_clock_in_gate.dart';

class CommutePreClockInChecklist extends StatelessWidget {
  const CommutePreClockInChecklist({
    super.key,
    required this.contextLabel,
    required this.items,
    required this.checkedIds,
    required this.onToggle,
    required this.onCheckAll,
    required this.onConfirm,
    required this.confirming,
    this.embedded = false,
  });

  final String contextLabel;
  final List<CommutePreClockInItem> items;
  final Set<String> checkedIds;
  final ValueChanged<String> onToggle;
  final VoidCallback onCheckAll;
  final Future<void> Function() onConfirm;
  final bool confirming;
  final bool embedded;

  bool get _allChecked =>
      items.isNotEmpty && items.every((item) => checkedIds.contains(item.id));

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final normalizedContext = contextLabel.trim();

    return LayoutBuilder(
      builder: (context, constraints) {
        final reportHeight = constraints.hasBoundedHeight
            ? constraints.maxHeight
            : MediaQuery.sizeOf(context).height;
        final reportBody = Padding(
          padding: EdgeInsets.fromLTRB(
            embedded ? 20 : 22,
            embedded ? 18 : 22,
            embedded ? 20 : 22,
            14,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.max,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: EdgeInsets.only(right: embedded ? 0 : 52),
                child: Text(
                  '출근 전 업무 확인',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: tokens.textPrimary,
                        fontWeight: FontWeight.w700,
                        height: 1.35,
                      ),
                ),
              ),
              const SizedBox(height: 18),
              if (normalizedContext.isNotEmpty) ...[
                _ReportMetadataRow(
                  label: '근무 위치',
                  value: Text(
                    normalizedContext,
                    textAlign: TextAlign.right,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: tokens.textPrimary,
                          fontWeight: FontWeight.w600,
                          height: 1.4,
                        ),
                  ),
                ),
                const SizedBox(height: 8),
              ],
              _ReportMetadataRow(
                label: '확인 항목',
                value: Text(
                  '${items.length}건',
                  textAlign: TextAlign.right,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: tokens.textPrimary,
                        fontWeight: FontWeight.w600,
                        height: 1.4,
                      ),
                ),
              ),
              const SizedBox(height: 8),
              _ReportMetadataRow(
                label: '상태',
                value: AnimatedSwitcher(
                  duration: reduceMotion
                      ? Duration.zero
                      : CommonUiMotion.selection,
                  switchInCurve: CommonUiMotion.enter,
                  switchOutCurve: CommonUiMotion.exit,
                  child: Text(
                    _allChecked ? '확인 완료' : '확인 진행 중',
                    key: ValueKey<bool>(_allChecked),
                    textAlign: TextAlign.right,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: _allChecked
                              ? tokens.success
                              : tokens.textSecondary,
                          fontWeight: FontWeight.w700,
                          height: 1.4,
                        ),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Divider(height: 1, color: tokens.borderStrong),
              const SizedBox(height: 4),
              Expanded(
                child: ListView.separated(
                  primary: false,
                  physics: const ClampingScrollPhysics(),
                  padding: EdgeInsets.zero,
                  itemCount: items.length,
                  separatorBuilder: (_, __) =>
                      Divider(height: 1, color: tokens.borderSubtle),
                  itemBuilder: (context, index) {
                    final item = items[index];
                    return _ChecklistItem(
                      index: index,
                      item: item,
                      checked: checkedIds.contains(item.id),
                      onPressed: confirming
                          ? null
                          : () => onToggle(item.id),
                    );
                  },
                ),
              ),
              const SizedBox(height: 4),
              Divider(height: 1, color: tokens.borderStrong),
              const SizedBox(height: 14),
              _ReportMetadataRow(
                label: '확인 현황',
                value: AnimatedSwitcher(
                  duration: reduceMotion
                      ? Duration.zero
                      : CommonUiMotion.selection,
                  switchInCurve: CommonUiMotion.enter,
                  switchOutCurve: CommonUiMotion.exit,
                  child: Text(
                    '${checkedIds.length} / ${items.length}',
                    key: ValueKey<String>(
                      '${checkedIds.length}_${items.length}',
                    ),
                    textAlign: TextAlign.right,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: _allChecked
                              ? tokens.success
                              : tokens.textPrimary,
                          fontWeight: FontWeight.w700,
                          height: 1.4,
                        ),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              _ReportApprovalSection(
                allChecked: _allChecked,
                confirming: confirming,
                onCheckAll: onCheckAll,
                onConfirm: onConfirm,
              ),
            ],
          ),
        );

        if (embedded) {
          return SizedBox(
            width: double.infinity,
            height: reportHeight,
            child: reportBody,
          );
        }

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 540),
              child: SizedBox(
                width: double.infinity,
                height: reportHeight,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: tokens.surfaceRaised,
                    borderRadius: BorderRadius.circular(CommonUiShapes.card),
                    border: Border.all(color: tokens.borderSubtle),
                  ),
                  child: reportBody,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _ReportMetadataRow extends StatelessWidget {
  const _ReportMetadataRow({
    required this.label,
    required this.value,
  });

  final String label;
  final Widget value;

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 82,
          child: Text(
            label,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: tokens.textSecondary,
                  fontWeight: FontWeight.w600,
                  height: 1.4,
                ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(child: value),
      ],
    );
  }
}

class _ReportApprovalSection extends StatelessWidget {
  const _ReportApprovalSection({
    required this.allChecked,
    required this.confirming,
    required this.onCheckAll,
    required this.onConfirm,
  });

  final bool allChecked;
  final bool confirming;
  final VoidCallback onCheckAll;
  final Future<void> Function() onConfirm;

  String _formatDate(DateTime value) {
    final year = value.year.toString().padLeft(4, '0');
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    return '$year.$month.$day';
  }

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final duration = reduceMotion ? Duration.zero : CommonUiMotion.selection;
    final reportDate = _formatDate(DateTime.now());
    final canCheckAll = !confirming && !allChecked;
    final canConfirm = !confirming && allChecked;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Divider(height: 1, color: tokens.borderStrong),
        Semantics(
          button: true,
          checked: allChecked,
          enabled: canCheckAll,
          label: '전체 체크',
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: canCheckAll ? onCheckAll : null,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 13),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    AnimatedContainer(
                      duration: duration,
                      curve: CommonUiMotion.enter,
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        color: allChecked ? tokens.accent : Colors.transparent,
                        borderRadius: BorderRadius.circular(3),
                        border: Border.all(
                          color: allChecked
                              ? tokens.accent
                              : tokens.borderStrong,
                          width: 1.3,
                        ),
                      ),
                      child: AnimatedSwitcher(
                        duration: duration,
                        switchInCurve: CommonUiMotion.enter,
                        switchOutCurve: CommonUiMotion.exit,
                        child: allChecked
                            ? Icon(
                                Icons.check_rounded,
                                key: const ValueKey<String>('all_checked'),
                                size: 16,
                                color: tokens.onAccent,
                              )
                            : const SizedBox.shrink(
                                key: ValueKey<String>('all_unchecked'),
                              ),
                      ),
                    ),
                    const SizedBox(width: 9),
                    AnimatedDefaultTextStyle(
                      duration: duration,
                      curve: CommonUiMotion.enter,
                      style: (Theme.of(context).textTheme.bodyMedium ??
                              const TextStyle())
                          .copyWith(
                        color: allChecked
                            ? tokens.textPrimary
                            : tokens.textSecondary,
                        fontWeight: FontWeight.w700,
                        height: 1.4,
                      ),
                      child: const Text('전체 체크'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        Divider(height: 1, color: tokens.borderSubtle),
        SizedBox(
          height: 58,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Align(
                alignment: Alignment.center,
                child: Text(
                  reportDate,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: tokens.textSecondary,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.5,
                        height: 1.4,
                      ),
                ),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: SizedBox(
                  width: 96,
                  height: 58,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      border: Border(
                        left: BorderSide(color: tokens.borderSubtle),
                      ),
                    ),
                    child: Semantics(
                      button: true,
                      enabled: canConfirm,
                      label: confirming ? '확인 중' : '확인',
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: canConfirm ? onConfirm : null,
                          child: Center(
                            child: AnimatedDefaultTextStyle(
                              duration: duration,
                              curve: CommonUiMotion.enter,
                              style: (Theme.of(context).textTheme.bodyLarge ??
                                      const TextStyle())
                                  .copyWith(
                                color: canConfirm
                                    ? tokens.accent
                                    : tokens.textSecondary,
                                fontWeight: canConfirm
                                    ? FontWeight.w800
                                    : FontWeight.w600,
                                height: 1.4,
                              ),
                              child: AnimatedSwitcher(
                                duration: duration,
                                switchInCurve: CommonUiMotion.enter,
                                switchOutCurve: CommonUiMotion.exit,
                                child: Text(
                                  confirming ? '확인 중' : '확인',
                                  key: ValueKey<bool>(confirming),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ChecklistItem extends StatelessWidget {
  const _ChecklistItem({
    required this.index,
    required this.item,
    required this.checked,
    required this.onPressed,
  });

  final int index;
  final CommutePreClockInItem item;
  final bool checked;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final duration = reduceMotion ? Duration.zero : CommonUiMotion.selection;
    final number = (index + 1).toString().padLeft(2, '0');

    return Semantics(
      button: true,
      checked: checked,
      enabled: onPressed != null,
      label: '$number ${item.label}',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          child: AnimatedContainer(
            duration: duration,
            curve: CommonUiMotion.enter,
            color: checked
                ? tokens.accentContainer.withOpacity(0.12)
                : Colors.transparent,
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 15),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                SizedBox(
                  width: 42,
                  child: Text(
                    number,
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          color: checked
                              ? tokens.textPrimary
                              : tokens.textSecondary,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.6,
                        ),
                  ),
                ),
                Expanded(
                  child: AnimatedDefaultTextStyle(
                    duration: duration,
                    curve: CommonUiMotion.enter,
                    style: (Theme.of(context).textTheme.bodyLarge ??
                            const TextStyle())
                        .copyWith(
                      color: checked
                          ? tokens.textPrimary
                          : tokens.textSecondary,
                      fontWeight: checked ? FontWeight.w600 : FontWeight.w500,
                      height: 1.45,
                    ),
                    child: Text(item.label),
                  ),
                ),
                const SizedBox(width: 14),
                AnimatedScale(
                  scale: checked ? 1 : 0.96,
                  duration: duration,
                  curve: CommonUiMotion.enter,
                  child: AnimatedContainer(
                    duration: duration,
                    curve: CommonUiMotion.enter,
                    width: 27,
                    height: 27,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: checked ? tokens.accent : Colors.transparent,
                      border: Border.all(
                        color: checked ? tokens.accent : tokens.borderStrong,
                        width: 1.4,
                      ),
                    ),
                    child: AnimatedSwitcher(
                      duration: duration,
                      switchInCurve: CommonUiMotion.enter,
                      switchOutCurve: CommonUiMotion.exit,
                      child: checked
                          ? Icon(
                              Icons.check_rounded,
                              key: const ValueKey<String>('checked'),
                              size: 18,
                              color: tokens.onAccent,
                            )
                          : const SizedBox.shrink(
                              key: ValueKey<String>('unchecked'),
                            ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
