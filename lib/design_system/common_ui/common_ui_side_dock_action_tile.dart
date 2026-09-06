import 'package:flutter/material.dart';

import 'common_ui_theme.dart';

class CommonSideDockActionTile extends StatefulWidget {
  const CommonSideDockActionTile({
    super.key,
    required this.icon,
    required this.title,
    required this.description,
    this.onTap,
    this.status = '',
    this.compact = false,
    this.singleLine = false,
    this.showChevron = true,
    this.accentColor,
    this.foregroundColor,
  });

  final IconData icon;
  final String title;
  final String description;
  final VoidCallback? onTap;
  final String status;
  final bool compact;
  final bool singleLine;
  final bool showChevron;
  final Color? accentColor;
  final Color? foregroundColor;

  @override
  State<CommonSideDockActionTile> createState() =>
      _CommonSideDockActionTileState();
}

class _CommonSideDockActionTileState
    extends State<CommonSideDockActionTile> {
  bool _pressed = false;
  bool _hovered = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final textTheme = Theme.of(context).textTheme;
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final background =
        _pressed || _hovered ? tokens.surfaceSelected : tokens.surface;
    final border = _focused ? tokens.focusRing : tokens.borderSubtle;
    final accent = widget.accentColor ?? tokens.accentContainer;
    final foreground = widget.foregroundColor ?? tokens.onAccentContainer;
    final iconBoxSize = widget.singleLine
        ? (widget.compact ? 28.0 : 34.0)
        : (widget.compact ? 38.0 : 42.0);
    final iconSize = widget.singleLine
        ? (widget.compact ? 16.0 : 18.0)
        : (widget.compact ? 20.0 : 22.0);
    final horizontalPadding = widget.singleLine
        ? (widget.compact ? 8.0 : 10.0)
        : (widget.compact ? 10.0 : 12.0);
    final verticalPadding = widget.singleLine
        ? (widget.compact ? 3.0 : 5.0)
        : (widget.compact ? 9.0 : 12.0);
    final contentGap = widget.singleLine
        ? (widget.compact ? 8.0 : 9.0)
        : (widget.compact ? 10.0 : 12.0);

    final semanticDescription = widget.description.trim();
    return Semantics(
      button: widget.onTap != null,
      label: semanticDescription.isEmpty
          ? widget.title
          : '${widget.title}, $semanticDescription',
      value: widget.status.trim().isEmpty ? null : widget.status.trim(),
      child: AnimatedScale(
        scale: _pressed ? .985 : 1,
        duration: reduceMotion ? Duration.zero : CommonUiMotion.press,
        curve: CommonUiMotion.enter,
        child: AnimatedContainer(
          duration: reduceMotion ? Duration.zero : CommonUiMotion.selection,
          curve: CommonUiMotion.standard,
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: border,
              width: _focused ? 2 : 1,
            ),
            boxShadow: _hovered
                ? [
                    BoxShadow(
                      color: tokens.shadow,
                      blurRadius: 12,
                      offset: const Offset(0, 5),
                    ),
                  ]
                : const [],
          ),
          child: Material(
            color: tokens.transparent,
            borderRadius: BorderRadius.circular(14),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: widget.onTap,
              onHighlightChanged: widget.onTap == null
                  ? null
                  : (value) {
                      if (_pressed == value) return;
                      setState(() => _pressed = value);
                    },
              onHover: widget.onTap == null
                  ? null
                  : (value) {
                      if (_hovered == value) return;
                      setState(() => _hovered = value);
                    },
              onFocusChange: widget.onTap == null
                  ? null
                  : (value) {
                      if (_focused == value) return;
                      setState(() => _focused = value);
                    },
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: horizontalPadding,
                  vertical: verticalPadding,
                ),
                child: Row(
                  children: [
                    AnimatedContainer(
                      duration: reduceMotion
                          ? Duration.zero
                          : CommonUiMotion.selection,
                      curve: CommonUiMotion.standard,
                      width: iconBoxSize,
                      height: iconBoxSize,
                      decoration: BoxDecoration(
                        color: accent,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: tokens.shadow,
                            blurRadius: _hovered ? 11 : 8,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      alignment: Alignment.center,
                      child: Icon(
                        widget.icon,
                        color: foreground,
                        size: iconSize,
                      ),
                    ),
                    SizedBox(width: contentGap),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            widget.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: textTheme.titleSmall?.copyWith(
                              color: tokens.textPrimary,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.2,
                            ),
                          ),
                          if (!widget.singleLine &&
                              widget.description.trim().isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              widget.description.trim(),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: textTheme.bodySmall?.copyWith(
                                color: tokens.textSecondary,
                                height: 1.15,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (widget.status.trim().isNotEmpty) ...[
                      const SizedBox(width: 8),
                      AnimatedDefaultTextStyle(
                        duration: reduceMotion
                            ? Duration.zero
                            : CommonUiMotion.selection,
                        curve: CommonUiMotion.standard,
                        style: textTheme.labelMedium?.copyWith(
                              color: tokens.accent,
                              fontWeight: FontWeight.w800,
                            ) ??
                            const TextStyle(),
                        child: Text(
                          widget.status.trim(),
                          maxLines: 1,
                        ),
                      ),
                    ],
                    if (widget.showChevron) ...[
                      const SizedBox(width: 8),
                      AnimatedSlide(
                        offset:
                            _hovered ? const Offset(.08, 0) : Offset.zero,
                        duration: reduceMotion
                            ? Duration.zero
                            : CommonUiMotion.selection,
                        curve: CommonUiMotion.enter,
                        child: Icon(
                          Icons.chevron_right_rounded,
                          color: tokens.iconSecondary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
