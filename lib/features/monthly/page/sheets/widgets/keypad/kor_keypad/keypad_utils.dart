import 'package:flutter/material.dart';

import '../../../../../../../design_system/common_ui/common_ui_theme.dart';

class KorKeypadUtils {
  static Widget buildSubLayout(
    List<List<String>> keyRows,
    void Function(String) onKeyTap, {
    required State state,
    required StateSetter setState,
    Map<String, AnimationController>? controllers,
    Map<String, bool>? isPressed,
  }) {
    return Column(
      children: List.generate(keyRows.length, (rowIndex) {
        final row = keyRows[rowIndex];
        return Expanded(
          child: Row(
            children: List.generate(row.length, (columnIndex) {
              final label = row[columnIndex];
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: label.isEmpty
                      ? const SizedBox.shrink()
                      : _CommonKoreanSubKey(
                          label: label,
                          entranceDelay: Duration(
                            milliseconds: (rowIndex * 3 + columnIndex) * 18,
                          ),
                          onTap: () => onKeyTap(label),
                        ),
                ),
              );
            }),
          ),
        );
      }),
    );
  }
}

class _CommonKoreanSubKey extends StatefulWidget {
  const _CommonKoreanSubKey({
    required this.label,
    required this.entranceDelay,
    required this.onTap,
  });

  final String label;
  final Duration entranceDelay;
  final VoidCallback onTap;

  @override
  State<_CommonKoreanSubKey> createState() => _CommonKoreanSubKeyState();
}

class _CommonKoreanSubKeyState extends State<_CommonKoreanSubKey> {
  bool _pressed = false;
  bool _hovered = false;
  bool _focused = false;
  bool? _pendingPressed;
  bool? _pendingHovered;
  bool? _pendingFocused;
  bool _interactionUpdateScheduled = false;

  bool get _isBack => widget.label == 'back';

  void _queueInteraction({
    bool? pressed,
    bool? hovered,
    bool? focused,
  }) {
    if (pressed != null) _pendingPressed = pressed;
    if (hovered != null) _pendingHovered = hovered;
    if (focused != null) _pendingFocused = focused;
    if (_interactionUpdateScheduled) return;
    _interactionUpdateScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _interactionUpdateScheduled = false;
      if (!mounted) return;
      final nextPressed = _pendingPressed;
      final nextHovered = _pendingHovered;
      final nextFocused = _pendingFocused;
      _pendingPressed = null;
      _pendingHovered = null;
      _pendingFocused = null;
      if ((nextPressed == null || nextPressed == _pressed) &&
          (nextHovered == null || nextHovered == _hovered) &&
          (nextFocused == null || nextFocused == _focused)) {
        return;
      }
      setState(() {
        if (nextPressed != null) _pressed = nextPressed;
        if (nextHovered != null) _hovered = nextHovered;
        if (nextFocused != null) _focused = nextFocused;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final textTheme = Theme.of(context).textTheme;
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final baseBackground = _isBack ? tokens.accentContainer : tokens.surfaceRaised;
    final foreground = _isBack ? tokens.onAccentContainer : tokens.textPrimary;
    final background = _pressed
        ? tokens.surfaceSelected
        : _hovered
            ? Color.alphaBlend(
                tokens.accent.withOpacity(tokens.isDark ? 0.16 : 0.09),
                baseBackground,
              )
            : baseBackground;
    final borderColor = _focused
        ? tokens.focusRing
        : _isBack
            ? tokens.borderSubtle
            : tokens.accent.withOpacity(tokens.isDark ? 0.34 : 0.22);
    final displayLabel = _isBack ? '뒤로' : widget.label;

    return Semantics(
      button: true,
      label: displayLabel,
      child: AnimatedContainer(
        duration: reduceMotion ? Duration.zero : CommonUiMotion.selection,
        curve: CommonUiMotion.standard,
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(CommonUiShapes.button),
          border: Border.all(
            color: borderColor,
            width: _focused ? 2 : 1,
          ),
          boxShadow: [
            if (_hovered)
              BoxShadow(
                color: tokens.shadow,
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
          ],
        ),
        child: Material(
          color: tokens.transparent,
          borderRadius: BorderRadius.circular(CommonUiShapes.button),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: widget.onTap,
            onHighlightChanged: (value) => _queueInteraction(pressed: value),
            onHover: (value) => _queueInteraction(hovered: value),
            onFocusChange: (value) => _queueInteraction(focused: value),
            child: Center(
              child: TweenAnimationBuilder<double>(
                tween: Tween<double>(begin: reduceMotion ? 1 : 0, end: 1),
                duration: reduceMotion
                    ? Duration.zero
                    : CommonUiMotion.component + widget.entranceDelay,
                curve: CommonUiMotion.enter,
                builder: (context, progress, child) {
                  return Opacity(
                    opacity: progress,
                    child: Transform.translate(
                      offset: Offset(0, 5 * (1 - progress)),
                      child: child,
                    ),
                  );
                },
                child: AnimatedScale(
                  scale: _pressed ? 0.92 : 1,
                  duration: reduceMotion ? Duration.zero : CommonUiMotion.press,
                  curve: CommonUiMotion.enter,
                  child: Text(
                    displayLabel,
                    style: (_isBack ? textTheme.labelLarge : textTheme.titleLarge)
                        ?.copyWith(
                      color: foreground,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
