import 'package:flutter/material.dart';

import 'common_ui_theme.dart';

class CommonOperationalReportMetadataRow extends StatelessWidget {
  const CommonOperationalReportMetadataRow({
    super.key,
    required this.label,
    required this.value,
    this.dense = false,
  });

  final String label;
  final Widget value;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: dense ? 72 : 82,
          child: Text(
            label,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: tokens.textSecondary,
                  fontWeight: FontWeight.w600,
                  height: 1.4,
                ),
          ),
        ),
        SizedBox(width: dense ? 12 : 16),
        Expanded(child: value),
      ],
    );
  }
}

class CommonOperationalReportNumberedRow extends StatelessWidget {
  const CommonOperationalReportNumberedRow({
    super.key,
    required this.index,
    required this.text,
    this.interactive = false,
    this.selected = false,
    this.enabled = true,
    this.onPressed,
    this.trailing,
    this.dense = false,
    this.semanticLabel,
  });

  final int index;
  final String text;
  final bool interactive;
  final bool selected;
  final bool enabled;
  final VoidCallback? onPressed;
  final Widget? trailing;
  final bool dense;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final duration = reduceMotion ? Duration.zero : CommonUiMotion.selection;
    final number = (index + 1).toString().padLeft(2, '0');
    final numberColor = selected ? tokens.textPrimary : tokens.textSecondary;
    final bodyColor = interactive
        ? (selected ? tokens.textPrimary : tokens.textSecondary)
        : tokens.textPrimary;
    final bodyWeight = interactive
        ? (selected ? FontWeight.w600 : FontWeight.w500)
        : FontWeight.w500;
    final row = AnimatedContainer(
      duration: duration,
      curve: CommonUiMotion.enter,
      color: selected
          ? tokens.accentContainer.withOpacity(0.12)
          : Colors.transparent,
      padding: EdgeInsets.symmetric(
        horizontal: 4,
        vertical: dense ? 12 : 15,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: dense ? 36 : 42,
            child: AnimatedDefaultTextStyle(
              duration: duration,
              curve: CommonUiMotion.enter,
              style: (Theme.of(context).textTheme.labelMedium ??
                      const TextStyle())
                  .copyWith(
                color: numberColor,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6,
              ),
              child: Text(number),
            ),
          ),
          Expanded(
            child: AnimatedDefaultTextStyle(
              duration: duration,
              curve: CommonUiMotion.enter,
              style: ((dense
                          ? Theme.of(context).textTheme.bodyMedium
                          : Theme.of(context).textTheme.bodyLarge) ??
                      const TextStyle())
                  .copyWith(
                color: bodyColor,
                fontWeight: bodyWeight,
                height: 1.45,
              ),
              child: Text(text),
            ),
          ),
          if (trailing != null) ...[
            SizedBox(width: dense ? 10 : 14),
            trailing!,
          ],
        ],
      ),
    );

    if (!interactive) {
      return Semantics(
        container: true,
        label: semanticLabel ?? '$number $text',
        child: ExcludeSemantics(child: row),
      );
    }

    return Semantics(
      button: true,
      checked: selected,
      enabled: enabled && onPressed != null,
      label: semanticLabel ?? '$number $text',
      child: ExcludeSemantics(
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: enabled ? onPressed : null,
            child: row,
          ),
        ),
      ),
    );
  }
}
