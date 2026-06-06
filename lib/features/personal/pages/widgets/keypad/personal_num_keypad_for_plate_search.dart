
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';





class PersonalNumKeypadForPlateSearch extends StatefulWidget {
  final TextEditingController controller;
  final int maxLength;
  final VoidCallback? onComplete;
  final ValueChanged<bool>? onChangeFrontDigitMode;
  final VoidCallback? onReset;

  
  final Color? backgroundColor;

  
  final TextStyle? textStyle;

  final bool enableDigitModeSwitch;

  const PersonalNumKeypadForPlateSearch({
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

  @override
  State<PersonalNumKeypadForPlateSearch> createState() =>
      _PersonalNumKeypadForPlateSearchState();
}

class _PersonalNumKeypadForPlateSearchState
    extends State<PersonalNumKeypadForPlateSearch> {
  Timer? _repeatDeleteTimer;

  bool get _isFull => widget.controller.text.length >= widget.maxLength;
  bool get _isReadyToSearch => widget.controller.text.length == widget.maxLength;

  @override
  void dispose() {
    _repeatDeleteTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    
    final bg = widget.backgroundColor ?? cs.surface;

    return Container(
      color: bg, 
      padding: EdgeInsets.zero,
      child: Column(
        mainAxisSize: MainAxisSize.max, 
        children: [
          _buildExpandedRow(const [
            _KeySpec.label('1'),
            _KeySpec.label('2'),
            _KeySpec.label('3')
          ]),
          _buildExpandedRow(const [
            _KeySpec.label('4'),
            _KeySpec.label('5'),
            _KeySpec.label('6')
          ]),
          _buildExpandedRow(const [
            _KeySpec.label('7'),
            _KeySpec.label('8'),
            _KeySpec.label('9')
          ]),
          _buildExpandedRow(_lastRowKeys()),
        ],
      ),
    );
  }

  
  Widget _buildExpandedRow(List<_KeySpec> keys) {
    return Expanded(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          for (final k in keys) Expanded(child: _buildKey(k)),
        ],
      ),
    );
  }

  List<_KeySpec> _lastRowKeys() {
    if (widget.enableDigitModeSwitch) {
      return const [
        _KeySpec.label('두자리'),
        _KeySpec.label('0'),
        _KeySpec.label('세자리'),
      ];
    }
    return const [
      _KeySpec.icon(label: '지움', icon: Icons.backspace_outlined),
      _KeySpec.label('0'),
      _KeySpec.label('검색'),
    ];
  }

  Widget _buildKey(_KeySpec spec) {
    final cs = Theme.of(context).colorScheme;

    final enabled = _isKeyEnabled(spec);

    
    final Color fg = enabled ? cs.onSurface : cs.onSurfaceVariant.withOpacity(0.55);

    
    final Color tileBg = cs.surfaceContainerLow;
    final Color border = cs.outlineVariant.withOpacity(0.85);

    final baseStyle =
        widget.textStyle ?? const TextStyle(fontSize: 18, fontWeight: FontWeight.w500);
    final labelStyle = baseStyle.copyWith(color: fg);

    return Padding(
      padding: const EdgeInsets.all(4.0), 
      child: _Pressable(
        enabled: enabled,
        onTap: () => _handleTap(spec),
        onLongPressStart: spec.isBackspace && widget.onReset != null
            ? (_) {
          
          _startRepeatDelete(fullReset: true);
        }
            : null,
        onLongPressEnd: spec.isBackspace && widget.onReset != null
            ? (_) {
          _stopRepeatDelete();
        }
            : null,
        child: SizedBox.expand( 
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: tileBg,
              border: Border.all(color: border),
            ),
            child: Center(
              child: FittedBox( 
                fit: BoxFit.scaleDown,
                child: spec.icon == null
                    ? Text(spec.label!, style: labelStyle)
                    : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(spec.icon, size: 20, color: fg),
                    if (spec.label != null) ...[
                      const SizedBox(width: 6),
                      Text(spec.label!, style: labelStyle),
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

  bool _isKeyEnabled(_KeySpec spec) {
    if (spec.isDigit) return !_isFull;
    if (spec.isSearch) return _isReadyToSearch;
    return true; 
  }

  void _handleTap(_KeySpec spec) {
    HapticFeedback.lightImpact();

    if (spec.isDigit) {
      _insertDigit(spec.label!);
      if (_isReadyToSearch) Future.microtask(() => widget.onComplete?.call());
      return;
    }
    if (spec.isBackspace) {
      _deleteOne();
      return;
    }
    if (spec.isSearch) {
      if (_isReadyToSearch) Future.microtask(() => widget.onComplete?.call());
      return;
    }
    
    if (spec.label == '두자리') {
      widget.onChangeFrontDigitMode?.call(false);
      return;
    }
    if (spec.label == '세자리') {
      widget.onChangeFrontDigitMode?.call(true);
      return;
    }
  }

  void _insertDigit(String d) {
    if (_isFull) return;
    final old = widget.controller.value;
    final newText = old.text + d;
    widget.controller.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: newText.length),
      composing: TextRange.empty,
    );
  }

  void _deleteOne() {
    final old = widget.controller.value;
    if (old.text.isEmpty) return;
    final newText = old.text.substring(0, old.text.length - 1);
    widget.controller.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: newText.length),
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
    _repeatDeleteTimer = Timer.periodic(const Duration(milliseconds: 80), (_) {
      if (!mounted) return;
      if (fullReset) {
        _stopRepeatDelete();
      } else {
        if (widget.controller.text.isEmpty) {
          _stopRepeatDelete();
        } else {
          _deleteOne();
        }
      }
    });
  }

  void _stopRepeatDelete() {
    _repeatDeleteTimer?.cancel();
    _repeatDeleteTimer = null;
  }
}

class _KeySpec {
  final String? label;
  final IconData? icon;

  const _KeySpec._(this.label, this.icon);
  const _KeySpec.label(String label) : this._(label, null);
  const _KeySpec.icon({String? label, required IconData icon}) : this._(label, icon);

  bool get isDigit => label != null && RegExp(r'^\d$').hasMatch(label!);
  bool get isSearch => label == '검색';
  bool get isBackspace => icon == Icons.backspace_outlined;
}


class _Pressable extends StatefulWidget {
  final Widget child;
  final GestureTapCallback? onTap;
  final GestureLongPressStartCallback? onLongPressStart;
  final GestureLongPressEndCallback? onLongPressEnd;
  final bool enabled;

  const _Pressable({
    required this.child,
    this.onTap,
    this.onLongPressStart,
    this.onLongPressEnd,
    this.enabled = true,
  });

  @override
  State<_Pressable> createState() => _PressableState();
}

class _PressableState extends State<_Pressable> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final scaledChild = AnimatedScale(
      scale: _pressed ? 0.92 : 1.0,
      duration: const Duration(milliseconds: 90),
      curve: Curves.easeOut,
      child: widget.child,
    );

    
    final splash = cs.primary.withOpacity(0.12);
    final highlight = cs.primary.withOpacity(0.06);

    return Material(
      color: Colors.transparent,
      child: GestureDetector(
        onLongPressStart: widget.enabled ? widget.onLongPressStart : null,
        onLongPressEnd: widget.enabled ? widget.onLongPressEnd : null,
        child: InkWell(
          onTap: widget.enabled ? widget.onTap : null,
          onHighlightChanged: (v) => setState(() => _pressed = v && widget.enabled),
          splashColor: splash,
          highlightColor: highlight,
          child: scaledChild,
        ),
      ),
    );
  }
}
