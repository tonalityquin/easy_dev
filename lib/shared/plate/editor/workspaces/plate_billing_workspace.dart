import 'package:flutter/material.dart';

import '../../../../design_system/common_ui/common_ui_components.dart';
import '../../../../design_system/common_ui/common_ui_theme.dart';

class PlateBillingOption {
  const PlateBillingOption({
    required this.value,
    this.detail = '',
  });

  final String value;
  final String detail;
}

class PlateBillingDetailRow {
  const PlateBillingDetailRow({
    required this.label,
    required this.value,
    this.section,
  });

  final String label;
  final String value;
  final String? section;
}

class PlateBillingWorkspace extends StatelessWidget {
  const PlateBillingWorkspace({
    super.key,
    required this.onExit,
    required this.selectedType,
    required this.selectedValue,
    this.title = '정산',
    this.subtitle = '차량에 적용할 정산 정보를 확인합니다.',
    this.typeOptions = const <String>[],
    this.valueOptions = const <PlateBillingOption>[],
    this.detailRows = const <PlateBillingDetailRow>[],
    this.loading = false,
    this.monthlyEnabled = true,
    this.monthlyMessage,
    this.monthlyAction,
    this.monthlyActionLabel,
    this.onTypeChanged,
    this.onValueChanged,
  });

  final VoidCallback onExit;
  final String selectedType;
  final String selectedValue;
  final String title;
  final String subtitle;
  final List<String> typeOptions;
  final List<PlateBillingOption> valueOptions;
  final List<PlateBillingDetailRow> detailRows;
  final bool loading;
  final bool monthlyEnabled;
  final String? monthlyMessage;
  final VoidCallback? monthlyAction;
  final String? monthlyActionLabel;
  final ValueChanged<String>? onTypeChanged;
  final ValueChanged<String>? onValueChanged;

  bool get _editable => onTypeChanged != null || onValueChanged != null;

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: tokens.borderSubtle),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 12, 8),
            child: Row(
              children: [
                CommonIconButton(
                  icon: Icons.close_rounded,
                  tooltip: '닫기',
                  size: 36,
                  iconSize: 18,
                  onPressed: onExit,
                ),
                const SizedBox(width: 6),
                Icon(
                  Icons.receipt_long_rounded,
                  color: tokens.accent,
                  size: 21,
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _editable ? title : '$title 상세',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              color: tokens.textPrimary,
                              fontWeight: FontWeight.w900,
                            ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: tokens.textSecondary,
                              height: 1.3,
                            ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: tokens.borderSubtle),
          Expanded(
            child: loading
                ? Center(
                    child: CircularProgressIndicator(color: tokens.accent),
                  )
                : LayoutBuilder(
                    builder: (context, constraints) {
                      final minHeight = (constraints.maxHeight - 30)
                          .clamp(0.0, double.infinity)
                          .toDouble();
                      return SingleChildScrollView(
                        physics: const ClampingScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
                        child: ConstrainedBox(
                          constraints: BoxConstraints(minHeight: minHeight),
                          child: Center(
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 520),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  if (typeOptions.isNotEmpty) ...[
                                    Text(
                                      '정산 유형',
                                      textAlign: TextAlign.center,
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelMedium
                                          ?.copyWith(
                                            color: tokens.textSecondary,
                                            fontWeight: FontWeight.w900,
                                          ),
                                    ),
                                    const SizedBox(height: 7),
                                    Wrap(
                                      alignment: WrapAlignment.center,
                                      spacing: 8,
                                      runSpacing: 8,
                                      children: [
                                        for (final type in typeOptions)
                                          CommonButton(
                                            label: type,
                                            selected: selectedType == type,
                                            variant:
                                                CommonButtonVariant.secondary,
                                            onPressed:
                                                type == '정기' && !monthlyEnabled
                                                    ? null
                                                    : onTypeChanged == null
                                                        ? null
                                                        : () => onTypeChanged!(
                                                              type,
                                                            ),
                                          ),
                                      ],
                                    ),
                                    const SizedBox(height: 14),
                                  ],
                                  if (_editable) ...[
                                    _SelectionBlock(
                                      selectedValue: selectedValue,
                                      valueOptions: valueOptions,
                                      onValueChanged: onValueChanged,
                                    ),
                                    if (monthlyMessage != null &&
                                        monthlyMessage!.trim().isNotEmpty) ...[
                                      const SizedBox(height: 12),
                                      Container(
                                        padding: const EdgeInsets.all(11),
                                        decoration: BoxDecoration(
                                          color: tokens.surfaceOverlay,
                                          borderRadius: BorderRadius.circular(
                                            CommonUiShapes.control,
                                          ),
                                          border: Border.all(
                                            color: tokens.borderSubtle,
                                          ),
                                        ),
                                        child: Text(
                                          monthlyMessage!,
                                          textAlign: TextAlign.center,
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodySmall
                                              ?.copyWith(
                                                color: tokens.textSecondary,
                                                height: 1.35,
                                              ),
                                        ),
                                      ),
                                    ],
                                    if (monthlyAction != null &&
                                        monthlyActionLabel != null) ...[
                                      const SizedBox(height: 10),
                                      Center(
                                        child: CommonButton(
                                          label: monthlyActionLabel!,
                                          icon: Icons.sync_rounded,
                                          variant:
                                              CommonButtonVariant.secondary,
                                          onPressed: monthlyAction,
                                        ),
                                      ),
                                    ],
                                  ],
                                  if (detailRows.isNotEmpty) ...[
                                    if (_editable) const SizedBox(height: 16),
                                    _DetailRows(rows: detailRows),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _SelectionBlock extends StatelessWidget {
  const _SelectionBlock({
    required this.selectedValue,
    required this.valueOptions,
    required this.onValueChanged,
  });

  final String selectedValue;
  final List<PlateBillingOption> valueOptions;
  final ValueChanged<String>? onValueChanged;

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '적용 기준',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: tokens.textSecondary,
                fontWeight: FontWeight.w900,
              ),
        ),
        const SizedBox(height: 7),
        if (valueOptions.isEmpty)
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: tokens.surfaceOverlay,
              borderRadius: BorderRadius.circular(CommonUiShapes.control),
              border: Border.all(color: tokens.borderSubtle),
            ),
            child: Text(
              selectedValue.trim().isEmpty
                  ? '선택 가능한 정산 기준이 없습니다.'
                  : selectedValue,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: tokens.textPrimary,
                    fontWeight: FontWeight.w800,
                  ),
            ),
          )
        else
          ...valueOptions.map((option) {
            final selected = option.value == selectedValue;
            return Padding(
              padding: const EdgeInsets.only(bottom: 7),
              child: Material(
                color: selected
                    ? tokens.surfaceSelected
                    : tokens.surfaceOverlay,
                borderRadius: BorderRadius.circular(CommonUiShapes.control),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: onValueChanged == null
                      ? null
                      : () => onValueChanged!(option.value),
                  child: AnimatedContainer(
                    duration: reduceMotion
                        ? Duration.zero
                        : const Duration(milliseconds: 150),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      borderRadius:
                          BorderRadius.circular(CommonUiShapes.control),
                      border: Border.all(
                        color: selected ? tokens.accent : tokens.borderSubtle,
                      ),
                    ),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 32),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                option.value,
                                textAlign: TextAlign.center,
                                style: Theme.of(context)
                                    .textTheme
                                    .bodyMedium
                                    ?.copyWith(
                                      color: tokens.textPrimary,
                                      fontWeight: FontWeight.w900,
                                    ),
                              ),
                              if (option.detail.trim().isNotEmpty) ...[
                                const SizedBox(height: 2),
                                Text(
                                  option.detail,
                                  textAlign: TextAlign.center,
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(
                                        color: tokens.textSecondary,
                                      ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        Positioned.fill(
                          child: Align(
                            alignment: Alignment.centerRight,
                            child: AnimatedSwitcher(
                              duration: reduceMotion
                                  ? Duration.zero
                                  : const Duration(milliseconds: 140),
                              child: selected
                                  ? Icon(
                                      Icons.check_circle_rounded,
                                      key: const ValueKey<String>('selected'),
                                      color: tokens.accent,
                                    )
                                  : Icon(
                                      Icons.circle_outlined,
                                      key: const ValueKey<String>('unselected'),
                                      color: tokens.iconSecondary,
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
          }),
      ],
    );
  }
}

class _DetailRows extends StatelessWidget {
  const _DetailRows({required this.rows});

  final List<PlateBillingDetailRow> rows;

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    String? section;
    final children = <Widget>[];
    for (final row in rows) {
      if (row.section != null && row.section != section) {
        section = row.section;
        if (children.isNotEmpty) children.add(const SizedBox(height: 12));
        children.add(
          Text(
            section!,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: tokens.textSecondary,
                  fontWeight: FontWeight.w900,
                ),
          ),
        );
        children.add(const SizedBox(height: 4));
      }
      children.add(
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                row.label,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: tokens.textSecondary,
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 3),
              Text(
                row.value,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: tokens.textPrimary,
                      fontWeight: FontWeight.w900,
                    ),
              ),
            ],
          ),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }
}
