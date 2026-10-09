import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'common_ui_theme.dart';

class CommonSideDockListSurface extends StatelessWidget {
  const CommonSideDockListSurface({
    super.key,
    required this.children,
    this.dividerInset = 54,
  });

  final List<Widget> children;
  final double dividerInset;

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final items = <Widget>[];
    for (var index = 0; index < children.length; index += 1) {
      if (index > 0) {
        items.add(
          Padding(
            padding: EdgeInsets.only(left: dividerInset),
            child: Divider(
              height: 1,
              thickness: 1,
              color: tokens.borderSubtle,
            ),
          ),
        );
      }
      items.add(children[index]);
    }

    return AnimatedSize(
      duration: reduceMotion ? Duration.zero : CommonUiMotion.component,
      curve: CommonUiMotion.standard,
      alignment: Alignment.topCenter,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: tokens.surfaceRaised,
          borderRadius: BorderRadius.circular(CommonUiShapes.button),
          border: Border.all(color: tokens.borderSubtle),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(CommonUiShapes.button - 1),
          child: Material(
            color: tokens.transparent,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: items,
            ),
          ),
        ),
      ),
    );
  }
}

class CommonSideDockListAction extends StatefulWidget {
  const CommonSideDockListAction({
    super.key,
    required this.icon,
    required this.title,
    required this.onTap,
    this.showChevron = true,
    this.iconBackgroundColor,
    this.iconForegroundColor,
  });

  final IconData icon;
  final String title;
  final VoidCallback? onTap;
  final bool showChevron;
  final Color? iconBackgroundColor;
  final Color? iconForegroundColor;

  @override
  State<CommonSideDockListAction> createState() =>
      _CommonSideDockListActionState();
}

class _CommonSideDockListActionState extends State<CommonSideDockListAction> {
  bool _pressed = false;
  bool _hovered = false;
  bool _focused = false;

  bool get _enabled => widget.onTap != null;

  void _setPressed(bool value) {
    if (_pressed == value) return;
    setState(() => _pressed = value);
  }

  void _setHovered(bool value) {
    if (_hovered == value) return;
    setState(() => _hovered = value);
  }

  void _setFocused(bool value) {
    if (_focused == value) return;
    setState(() => _focused = value);
  }

  void _activate() {
    final action = widget.onTap;
    if (action == null) return;
    HapticFeedback.selectionClick();
    action();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final background = !_enabled
        ? tokens.surfaceDisabled
        : _pressed
            ? tokens.surfaceSelected
            : _hovered
                ? tokens.surfaceOverlay
                : tokens.transparent;
    final iconBackground =
        widget.iconBackgroundColor ?? tokens.accentContainer;
    final iconForeground =
        widget.iconForegroundColor ?? tokens.onAccentContainer;
    final foreground = _enabled ? tokens.textPrimary : tokens.textDisabled;
    final secondary = _enabled ? tokens.iconSecondary : tokens.iconDisabled;

    return Semantics(
      button: true,
      enabled: _enabled,
      label: widget.title,
      child: AnimatedContainer(
        duration: reduceMotion ? Duration.zero : CommonUiMotion.selection,
        curve: CommonUiMotion.standard,
        constraints: const BoxConstraints(minHeight: 54),
        decoration: BoxDecoration(
          color: background,
          border: Border.all(
            color: _focused ? tokens.focusRing : tokens.transparent,
            width: 2,
          ),
        ),
        child: InkWell(
          onTap: _enabled ? _activate : null,
          onHighlightChanged: _enabled ? _setPressed : null,
          onHover: _enabled ? _setHovered : null,
          onFocusChange: _enabled ? _setFocused : null,
          overlayColor: WidgetStatePropertyAll(tokens.transparent),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: iconBackground,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    widget.icon,
                    size: 18,
                    color: _enabled ? iconForeground : tokens.iconDisabled,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    widget.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: foreground,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.1,
                        ),
                  ),
                ),
                if (widget.showChevron) ...[
                  const SizedBox(width: 8),
                  AnimatedSlide(
                    offset: _hovered && _enabled
                        ? const Offset(0.08, 0)
                        : Offset.zero,
                    duration: reduceMotion
                        ? Duration.zero
                        : CommonUiMotion.selection,
                    curve: CommonUiMotion.enter,
                    child: AnimatedOpacity(
                      opacity: _pressed && _enabled ? 0.72 : 1,
                      duration: reduceMotion
                          ? Duration.zero
                          : CommonUiMotion.press,
                      child: Icon(
                        Icons.chevron_right_rounded,
                        size: 22,
                        color: secondary,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
