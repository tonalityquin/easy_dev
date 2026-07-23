import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../../../design_system/prompt_ui/prompt_ui_theme.dart';
import '../../../widgets/tablet_prompt_components.dart';

class TabletNumKeypadForTabletPlateSearch extends StatefulWidget {
  const TabletNumKeypadForTabletPlateSearch({
    super.key,
    required this.controller,
    required this.maxLength,
    this.onComplete,
    this.onChangeFrontDigitMode,
    this.onReset,
    this.backgroundColor,
    this.textStyle,
    this.enableDigitModeSwitch = true,
  });

  final TextEditingController controller;
  final int maxLength;
  final VoidCallback? onComplete;
  final ValueChanged<bool>? onChangeFrontDigitMode;
  final VoidCallback? onReset;
  final Color? backgroundColor;
  final TextStyle? textStyle;
  final bool enableDigitModeSwitch;

  @override
  State<TabletNumKeypadForTabletPlateSearch> createState() =>
      _TabletNumKeypadForTabletPlateSearchState();
}

class _TabletNumKeypadForTabletPlateSearchState
    extends State<TabletNumKeypadForTabletPlateSearch> {
  Timer? _repeatDeleteTimer;

  bool get _isFull => widget.controller.text.length >= widget.maxLength;
  bool get _isReadyToSearch =>
      widget.controller.text.length == widget.maxLength;

  @override
  void dispose() {
    _repeatDeleteTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = PromptUiTheme.of(context);
    return AnimatedContainer(
      duration: tabletPromptDuration(context, PromptUiMotion.component),
      curve: PromptUiMotion.standard,
      color: widget.backgroundColor ?? tokens.surfaceRaised,
      padding: const EdgeInsets.all(6),
      child: Column(
        mainAxisSize: MainAxisSize.max,
        children: <Widget>[
          _buildExpandedRow(const <_KeySpec>[
            _KeySpec.label('1'),
            _KeySpec.label('2'),
            _KeySpec.label('3'),
          ]),
          _buildExpandedRow(const <_KeySpec>[
            _KeySpec.label('4'),
            _KeySpec.label('5'),
            _KeySpec.label('6'),
          ]),
          _buildExpandedRow(const <_KeySpec>[
            _KeySpec.label('7'),
            _KeySpec.label('8'),
            _KeySpec.label('9'),
          ]),
          _buildExpandedRow(_lastRowKeys()),
        ],
      ),
    );
  }

  Widget _buildExpandedRow(List<_KeySpec> keys) {
    return Expanded(
      child: Row(
        children: <Widget>[
          for (final key in keys) Expanded(child: _buildKey(key)),
        ],
      ),
    );
  }

  List<_KeySpec> _lastRowKeys() {
    if (widget.enableDigitModeSwitch) {
      return const <_KeySpec>[
        _KeySpec.label('두자리'),
        _KeySpec.label('0'),
        _KeySpec.label('세자리'),
      ];
    }
    return const <_KeySpec>[
      _KeySpec.icon(label: '지움', icon: Icons.backspace_outlined),
      _KeySpec.label('0'),
      _KeySpec.label('검색'),
    ];
  }

  Widget _buildKey(_KeySpec spec) {
    final tokens = PromptUiTheme.of(context);
    final enabled = _isKeyEnabled(spec);
    final isSearch = spec.isSearch;
    final isBackspace = spec.isBackspace;
    final foreground = !enabled
        ? tokens.textDisabled
        : isSearch
            ? tokens.onAccent
            : isBackspace
                ? tokens.onDangerContainer
                : tokens.textPrimary;
    final background = !enabled
        ? tokens.surfaceDisabled
        : isSearch
            ? tokens.accent
            : isBackspace
                ? tokens.dangerContainer
                : tokens.surfaceOverlay;
    final border = !enabled
        ? tokens.borderSubtle
        : isSearch
            ? tokens.accent
            : isBackspace
                ? tokens.danger.withOpacity(tokens.isDark ? 0.62 : 0.46)
                : tokens.borderSubtle;
    final baseStyle = widget.textStyle ??
        Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ) ??
        const TextStyle(fontSize: 18, fontWeight: FontWeight.w600);

    return Padding(
      padding: const EdgeInsets.all(4),
      child: _Pressable(
        enabled: enabled,
        semanticsLabel: spec.label ?? '키패드 버튼',
        background: background,
        foreground: foreground,
        border: border,
        onTap: () => _handleTap(spec),
        onLongPressStart: spec.isBackspace && widget.onReset != null
            ? (_) => _startRepeatDelete(fullReset: true)
            : null,
        onLongPressEnd: spec.isBackspace && widget.onReset != null
            ? (_) => _stopRepeatDelete()
            : null,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: spec.icon == null
              ? Text(
                  spec.label!,
                  style: baseStyle.copyWith(
                    color: foreground,
                    fontFeatures: const <FontFeature>[
                      FontFeature.tabularFigures(),
                    ],
                  ),
                )
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Icon(spec.icon, size: 20, color: foreground),
                    if (spec.label != null) ...<Widget>[
                      const SizedBox(width: 6),
                      Text(
                        spec.label!,
                        style: baseStyle.copyWith(color: foreground),
                      ),
                    ],
                  ],
                ),
        ),
      ),
    );
  }

  bool _isKeyEnabled(_KeySpec spec) {
    if (spec.isDigit) return !_isFull;
    if (spec.isSearch) return _isReadyToSearch;
    return true;
  }

  void _handleTap(_KeySpec spec) {
    if (!_isKeyEnabled(spec)) return;
    HapticFeedback.selectionClick();
    if (spec.isDigit) {
      _insertDigit(spec.label!);
      if (_isReadyToSearch) {
        Future<void>.microtask(() => widget.onComplete?.call());
      }
      return;
    }
    if (spec.isBackspace) {
      _deleteOne();
      return;
    }
    if (spec.isSearch) {
      if (_isReadyToSearch) {
        Future<void>.microtask(() => widget.onComplete?.call());
      }
      return;
    }
    if (spec.label == '두자리') {
      widget.onChangeFrontDigitMode?.call(false);
      return;
    }
    if (spec.label == '세자리') {
      widget.onChangeFrontDigitMode?.call(true);
    }
  }

  void _insertDigit(String digit) {
    if (_isFull) return;
    final old = widget.controller.value;
    final text = old.text + digit;
    widget.controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
      composing: TextRange.empty,
    );
  }

  void _deleteOne() {
    final old = widget.controller.value;
    if (old.text.isEmpty) return;
    final text = old.text.substring(0, old.text.length - 1);
    widget.controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
      composing: TextRange.empty,
    );
  }

  void _startRepeatDelete({required bool fullReset}) {
    if (fullReset) {
      widget.onReset?.call();
    } else {
      _deleteOne();
    }
    _repeatDeleteTimer?.cancel();
    _repeatDeleteTimer = Timer.periodic(
      const Duration(milliseconds: 80),
      (_) {
        if (!mounted) return;
        if (fullReset || widget.controller.text.isEmpty) {
          _stopRepeatDelete();
        } else {
          _deleteOne();
        }
      },
    );
  }

  void _stopRepeatDelete() {
    _repeatDeleteTimer?.cancel();
    _repeatDeleteTimer = null;
  }
}

class _KeySpec {
  const _KeySpec._(this.label, this.icon);
  const _KeySpec.label(String label) : this._(label, null);
  const _KeySpec.icon({String? label, required IconData icon})
      : this._(label, icon);

  final String? label;
  final IconData? icon;

  bool get isDigit => label != null && RegExp(r'^\d$').hasMatch(label!);
  bool get isSearch => label == '검색';
  bool get isBackspace => icon == Icons.backspace_outlined;
}

class _Pressable extends StatefulWidget {
  const _Pressable({
    required this.child,
    required this.enabled,
    required this.semanticsLabel,
    required this.background,
    required this.foreground,
    required this.border,
    this.onTap,
    this.onLongPressStart,
    this.onLongPressEnd,
  });

  final Widget child;
  final GestureTapCallback? onTap;
  final GestureLongPressStartCallback? onLongPressStart;
  final GestureLongPressEndCallback? onLongPressEnd;
  final bool enabled;
  final String semanticsLabel;
  final Color background;
  final Color foreground;
  final Color border;

  @override
  State<_Pressable> createState() => _PressableState();
}

class _PressableState extends State<_Pressable> {
  bool _pressed = false;
  bool _hovered = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final tokens = PromptUiTheme.of(context);
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final background = _pressed || _hovered
        ? Color.alphaBlend(
            widget.foreground.withOpacity(_pressed ? 0.12 : 0.06),
            widget.background,
          )
        : widget.background;
    return Semantics(
      button: true,
      enabled: widget.enabled,
      label: widget.semanticsLabel,
      child: AnimatedScale(
        scale: _pressed && widget.enabled ? 0.97 : 1,
        duration: reduceMotion ? Duration.zero : PromptUiMotion.press,
        curve: PromptUiMotion.enter,
        child: AnimatedContainer(
          duration: reduceMotion ? Duration.zero : PromptUiMotion.selection,
          curve: PromptUiMotion.standard,
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(PromptUiShapes.control),
            border: Border.all(
              color: _focused ? tokens.focusRing : widget.border,
              width: _focused ? 2 : 1,
            ),
          ),
          child: Material(
            color: tokens.transparent,
            borderRadius: BorderRadius.circular(PromptUiShapes.control),
            clipBehavior: Clip.antiAlias,
            child: GestureDetector(
              onLongPressStart:
                  widget.enabled ? widget.onLongPressStart : null,
              onLongPressEnd: widget.enabled ? widget.onLongPressEnd : null,
              child: InkWell(
                onTap: widget.enabled ? widget.onTap : null,
                onHighlightChanged: (value) {
                  if (_pressed == value) return;
                  setState(() => _pressed = value);
                },
                onHover: (value) {
                  if (_hovered == value) return;
                  setState(() => _hovered = value);
                },
                onFocusChange: (value) {
                  if (_focused == value) return;
                  setState(() => _focused = value);
                },
                mouseCursor: widget.enabled
                    ? SystemMouseCursors.click
                    : SystemMouseCursors.basic,
                child: Center(child: widget.child),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
