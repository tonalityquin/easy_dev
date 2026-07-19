import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../../../design_system/prompt_ui/prompt_ui_theme.dart';

class NumKeypad extends StatelessWidget {
  final TextEditingController controller;
  final int maxLength;
  final VoidCallback? onComplete;
  final ValueChanged<bool>? onChangeFrontDigitMode;
  final bool enableDigitModeSwitch;
  final VoidCallback? onReset;

  const NumKeypad({
    super.key,
    required this.controller,
    required this.maxLength,
    this.onComplete,
    this.onChangeFrontDigitMode,
    this.enableDigitModeSwitch = false,
    this.onReset,
  });

  List<String> _lastRowKeys() {
    if (enableDigitModeSwitch) return ['두자리', '0', '세자리'];
    if (onReset != null) return ['처음', '0', '삭제'];
    return ['', '0', '삭제'];
  }

  void _handleKeyTap(String key) {
    HapticFeedback.selectionClick();
    if (key.isEmpty) return;
    if (key == '두자리') {
      onChangeFrontDigitMode?.call(false);
      return;
    }
    if (key == '세자리') {
      onChangeFrontDigitMode?.call(true);
      return;
    }
    if (key == '처음') {
      onReset?.call();
      return;
    }
    if (key == '삭제') {
      if (controller.text.isNotEmpty) {
        controller.text = controller.text.substring(0, controller.text.length - 1);
      }
      return;
    }
    if (controller.text.length < maxLength) {
      controller.text += key;
      if (controller.text.length == maxLength) {
        Future.microtask(() => onComplete?.call());
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = PromptUiTheme.of(context);
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final rows = <List<String>>[
      ['1', '2', '3'],
      ['4', '5', '6'],
      ['7', '8', '9'],
      _lastRowKeys(),
    ];

    return Semantics(
      container: true,
      label: '숫자 키패드',
      child: AnimatedContainer(
        duration: reduceMotion ? Duration.zero : PromptUiMotion.component,
        curve: PromptUiMotion.standard,
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
        decoration: BoxDecoration(
          color: tokens.surface,
          border: Border(top: BorderSide(color: tokens.borderSubtle)),
        ),
        child: TweenAnimationBuilder<double>(
          tween: Tween<double>(begin: reduceMotion ? 1 : 0, end: 1),
          duration: reduceMotion ? Duration.zero : PromptUiMotion.layout,
          curve: PromptUiMotion.enter,
          builder: (context, progress, child) {
            return Opacity(opacity: progress, child: child);
          },
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: List.generate(rows.length, (rowIndex) {
              final row = rows[rowIndex];
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: List.generate(row.length, (columnIndex) {
                    final label = row[columnIndex];
                    return Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: _PromptNumberKey(
                          label: label,
                          kind: _kindFor(label),
                          entranceDelay: Duration(
                            milliseconds: (rowIndex * 3 + columnIndex) * 18,
                          ),
                          onTap: () => _handleKeyTap(label),
                        ),
                      ),
                    );
                  }),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }

  _NumberKeyKind _kindFor(String label) {
    if (label.isEmpty) return _NumberKeyKind.empty;
    if (label == '삭제') return _NumberKeyKind.destructive;
    if (label.length > 1) return _NumberKeyKind.utility;
    return _NumberKeyKind.standard;
  }
}

enum _NumberKeyKind {
  empty,
  standard,
  utility,
  destructive,
}

class _PromptNumberKey extends StatefulWidget {
  const _PromptNumberKey({
    required this.label,
    required this.kind,
    required this.entranceDelay,
    required this.onTap,
  });

  final String label;
  final _NumberKeyKind kind;
  final Duration entranceDelay;
  final VoidCallback onTap;

  @override
  State<_PromptNumberKey> createState() => _PromptNumberKeyState();
}

class _PromptNumberKeyState extends State<_PromptNumberKey> {
  bool _pressed = false;
  bool _hovered = false;
  bool _focused = false;
  bool? _pendingPressed;
  bool? _pendingHovered;
  bool? _pendingFocused;
  bool _interactionUpdateScheduled = false;

  bool get _empty => widget.kind == _NumberKeyKind.empty;

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
    if (_empty) return const SizedBox(height: 52);

    final tokens = PromptUiTheme.of(context);
    final textTheme = Theme.of(context).textTheme;
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final baseBackground = switch (widget.kind) {
      _NumberKeyKind.standard => tokens.surfaceRaised,
      _NumberKeyKind.utility => tokens.surfaceOverlay,
      _NumberKeyKind.destructive => tokens.dangerContainer,
      _NumberKeyKind.empty => tokens.transparent,
    };
    final foreground = switch (widget.kind) {
      _NumberKeyKind.standard => tokens.textPrimary,
      _NumberKeyKind.utility => tokens.textSecondary,
      _NumberKeyKind.destructive => tokens.onDangerContainer,
      _NumberKeyKind.empty => tokens.transparent,
    };
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
        : widget.kind == _NumberKeyKind.standard
            ? tokens.accent.withOpacity(tokens.isDark ? 0.34 : 0.22)
            : widget.kind == _NumberKeyKind.destructive
                ? tokens.danger.withOpacity(tokens.isDark ? 0.48 : 0.34)
                : tokens.borderSubtle;

    return Semantics(
      button: true,
      label: widget.label,
      child: AnimatedContainer(
        height: 52,
        duration: reduceMotion ? Duration.zero : PromptUiMotion.selection,
        curve: PromptUiMotion.standard,
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(PromptUiShapes.button),
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
          borderRadius: BorderRadius.circular(PromptUiShapes.button),
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
                    : PromptUiMotion.component + widget.entranceDelay,
                curve: PromptUiMotion.enter,
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
                  duration: reduceMotion ? Duration.zero : PromptUiMotion.press,
                  curve: PromptUiMotion.enter,
                  child: Text(
                    widget.label,
                    style: (widget.kind == _NumberKeyKind.standard
                            ? textTheme.titleLarge
                            : textTheme.labelLarge)
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
