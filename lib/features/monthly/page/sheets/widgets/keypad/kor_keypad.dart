import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../../../design_system/prompt_ui/prompt_ui_theme.dart';
import 'kor_keypad/kor_0.dart';
import 'kor_keypad/kor_1.dart';
import 'kor_keypad/kor_2.dart';
import 'kor_keypad/kor_3.dart';
import 'kor_keypad/kor_4.dart';
import 'kor_keypad/kor_5.dart';
import 'kor_keypad/kor_6.dart';
import 'kor_keypad/kor_7.dart';
import 'kor_keypad/kor_8.dart';
import 'kor_keypad/kor_9.dart';

class KorKeypad extends StatefulWidget {
  final TextEditingController controller;
  final VoidCallback? onComplete;
  final VoidCallback? onReset;
  final int maxLength;
  final double height;

  const KorKeypad({
    super.key,
    required this.controller,
    this.onComplete,
    this.onReset,
    this.maxLength = 1,
    this.height = 248.0,
  });

  @override
  State<KorKeypad> createState() => _KorKeypadState();
}

class _KorKeypadState extends State<KorKeypad> {
  String? activeSubLayout;

  final Map<String, String> keyToSubLayout = const {
    'ㄱ': 'kor1',
    'ㄴ': 'kor2',
    'ㄷ': 'kor3',
    'ㄹ': 'kor4',
    'ㅁ': 'kor5',
    'ㅂ': 'kor6',
    'ㅅ': 'kor7',
    'ㅇ': 'kor8',
    'ㅈ': 'kor9',
    'ㅎ': 'kor0',
  };

  @override
  Widget build(BuildContext context) {
    final tokens = PromptUiTheme.of(context);
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final layoutKey = activeSubLayout ?? 'main';

    return Semantics(
      container: true,
      label: '한글 키패드',
      child: AnimatedContainer(
        duration: reduceMotion ? Duration.zero : PromptUiMotion.component,
        curve: PromptUiMotion.standard,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: tokens.surface,
          border: Border(top: BorderSide(color: tokens.borderSubtle)),
        ),
        child: SizedBox(
          height: widget.height,
          child: AnimatedSwitcher(
            duration: reduceMotion ? Duration.zero : PromptUiMotion.layout,
            reverseDuration: reduceMotion ? Duration.zero : PromptUiMotion.component,
            switchInCurve: PromptUiMotion.enter,
            switchOutCurve: PromptUiMotion.exit,
            layoutBuilder: (currentChild, previousChildren) {
              return Stack(
                alignment: Alignment.center,
                children: [
                  ...previousChildren,
                  if (currentChild != null) currentChild,
                ],
              );
            },
            transitionBuilder: (child, animation) {
              return FadeTransition(opacity: animation, child: child);
            },
            child: KeyedSubtree(
              key: ValueKey<String>(layoutKey),
              child: activeSubLayout == null
                  ? _buildMainLayout()
                  : _buildActiveSubLayout(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMainLayout() {
    const rows = [
      ['ㄱ', 'ㄴ', 'ㄷ'],
      ['ㄹ', 'ㅁ', 'ㅂ'],
      ['ㅅ', 'ㅇ', 'ㅈ'],
      ['공란', 'ㅎ', '지움'],
    ];
    return Column(
      children: List.generate(rows.length, (rowIndex) {
        final row = rows[rowIndex];
        return Expanded(
          child: Row(
            children: List.generate(row.length, (columnIndex) {
              final label = row[columnIndex];
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: _PromptKoreanMainKey(
                    label: label,
                    kind: label == '지움'
                        ? _KoreanMainKeyKind.destructive
                        : label == '공란'
                            ? _KoreanMainKeyKind.utility
                            : _KoreanMainKeyKind.standard,
                    entranceDelay: Duration(
                      milliseconds: (rowIndex * 3 + columnIndex) * 18,
                    ),
                    onTap: () => _handleMainKeyTap(label),
                  ),
                ),
              );
            }),
          ),
        );
      }),
    );
  }

  Widget _buildActiveSubLayout() {
    switch (activeSubLayout) {
      case 'kor0':
        return Kor0(onKeyTap: _handleSubKeyTap);
      case 'kor1':
        return Kor1(onKeyTap: _handleSubKeyTap);
      case 'kor2':
        return Kor2(onKeyTap: _handleSubKeyTap);
      case 'kor3':
        return Kor3(onKeyTap: _handleSubKeyTap);
      case 'kor4':
        return Kor4(onKeyTap: _handleSubKeyTap);
      case 'kor5':
        return Kor5(onKeyTap: _handleSubKeyTap);
      case 'kor6':
        return Kor6(onKeyTap: _handleSubKeyTap);
      case 'kor7':
        return Kor7(onKeyTap: _handleSubKeyTap);
      case 'kor8':
        return Kor8(onKeyTap: _handleSubKeyTap);
      case 'kor9':
        return Kor9(onKeyTap: _handleSubKeyTap);
      default:
        return const SizedBox.shrink();
    }
  }

  void _handleMainKeyTap(String key) {
    HapticFeedback.selectionClick();
    if (key == '지움') {
      widget.controller.clear();
      return;
    }
    if (keyToSubLayout.containsKey(key)) {
      setState(() => activeSubLayout = keyToSubLayout[key]);
    } else if (key == '공란') {
      Future.microtask(() => widget.onComplete?.call());
    }
  }

  void _handleSubKeyTap(String key) {
    HapticFeedback.selectionClick();
    if (key == 'back') {
      setState(() => activeSubLayout = null);
      return;
    }
    if (widget.controller.text.length >= widget.maxLength) {
      Future.microtask(() => widget.onComplete?.call());
      return;
    }
    widget.controller.text += key;
    Future.microtask(() => widget.onComplete?.call());
  }
}

enum _KoreanMainKeyKind {
  standard,
  utility,
  destructive,
}

class _PromptKoreanMainKey extends StatefulWidget {
  const _PromptKoreanMainKey({
    required this.label,
    required this.kind,
    required this.entranceDelay,
    required this.onTap,
  });

  final String label;
  final _KoreanMainKeyKind kind;
  final Duration entranceDelay;
  final VoidCallback onTap;

  @override
  State<_PromptKoreanMainKey> createState() => _PromptKoreanMainKeyState();
}

class _PromptKoreanMainKeyState extends State<_PromptKoreanMainKey> {
  bool _pressed = false;
  bool _hovered = false;
  bool _focused = false;
  bool? _pendingPressed;
  bool? _pendingHovered;
  bool? _pendingFocused;
  bool _interactionUpdateScheduled = false;

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
    final tokens = PromptUiTheme.of(context);
    final textTheme = Theme.of(context).textTheme;
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final baseBackground = switch (widget.kind) {
      _KoreanMainKeyKind.standard => tokens.surfaceRaised,
      _KoreanMainKeyKind.utility => tokens.accentContainer,
      _KoreanMainKeyKind.destructive => tokens.dangerContainer,
    };
    final foreground = switch (widget.kind) {
      _KoreanMainKeyKind.standard => tokens.textPrimary,
      _KoreanMainKeyKind.utility => tokens.onAccentContainer,
      _KoreanMainKeyKind.destructive => tokens.onDangerContainer,
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
        : widget.kind == _KoreanMainKeyKind.standard
            ? tokens.accent.withOpacity(tokens.isDark ? 0.34 : 0.22)
            : widget.kind == _KoreanMainKeyKind.destructive
                ? tokens.danger.withOpacity(tokens.isDark ? 0.48 : 0.34)
                : tokens.borderSubtle;

    return Semantics(
      button: true,
      label: widget.label,
      child: AnimatedContainer(
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
                    style: (widget.kind == _KoreanMainKeyKind.standard
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
