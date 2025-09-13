// lib/screens/tablet_package/widgets/keypad/tablet_num_keypad_for_tablet_plate_search.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 숫자 4자리 입력 중심의 키패드.
/// - 각 행(Row)과 각 버튼을 Expanded로 구성 → 가용 높이/너비를 모두 채움
/// - 스몰패드에서 여백 없이 패널 전체를 버튼이 채우도록 동작
/// - FittedBox로 콘텐츠 오버플로우 방지
class TabletNumKeypadForTabletPlateSearch extends StatefulWidget {
  final TextEditingController controller;
  final int maxLength;
  final VoidCallback? onComplete;
  final ValueChanged<bool>? onChangeFrontDigitMode;
  final VoidCallback? onReset;
  final Color? backgroundColor;
  final TextStyle? textStyle;
  final bool enableDigitModeSwitch;

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

  @override
  State<TabletNumKeypadForTabletPlateSearch> createState() => _TabletNumKeypadForTabletPlateSearchState();
}

class _TabletNumKeypadForTabletPlateSearchState extends State<TabletNumKeypadForTabletPlateSearch> {
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
    final bg = widget.backgroundColor ?? Colors.white;
    return Container(
      color: bg, // 여백 제거를 위해 데코 단순화
      padding: EdgeInsets.zero,
      child: Column(
        mainAxisSize: MainAxisSize.max, // 🔹 가용 높이를 끝까지 사용
        children: [
          _buildExpandedRow(const [_KeySpec.label('1'), _KeySpec.label('2'), _KeySpec.label('3')]),
          _buildExpandedRow(const [_KeySpec.label('4'), _KeySpec.label('5'), _KeySpec.label('6')]),
          _buildExpandedRow(const [_KeySpec.label('7'), _KeySpec.label('8'), _KeySpec.label('9')]),
          _buildExpandedRow(_lastRowKeys()),
        ],
      ),
    );
  }

  // 각 행 전체를 Expanded로
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
    final enabled = _isKeyEnabled(spec);
    final labelStyle = (widget.textStyle ?? const TextStyle(fontSize: 18, fontWeight: FontWeight.w500))
        .copyWith(color: enabled ? Colors.black87 : Colors.black38);

    return Padding(
      padding: const EdgeInsets.all(4.0), // 셀 간 최소 간격(완전 0 원하면 제거)
      child: _Pressable(
        enabled: enabled,
        onTap: () => _handleTap(spec),
        onLongPressStart: spec.isBackspace && widget.onReset != null
            ? (_) {
          // 길게 누르면 전체 초기화
          _startRepeatDelete(fullReset: true);
        }
            : null,
        onLongPressEnd: spec.isBackspace && widget.onReset != null
            ? (_) {
          _stopRepeatDelete();
        }
            : null,
        child: SizedBox.expand( // 🔹 셀 영역을 100% 채움
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.grey[50],
              border: Border.all(color: Colors.grey[300]!),
            ),
            child: Center(
              child: FittedBox( // 🔹 폭이 좁아도 자동 축소
                fit: BoxFit.scaleDown,
                child: spec.icon == null
                    ? Text(spec.label!, style: labelStyle)
                    : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(spec.icon, size: 20, color: enabled ? Colors.black87 : Colors.black38),
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
    return true; // 두자리/세자리/지움은 항상 가능
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
    // 모드 스위치
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

/// 눌림 애니메이션 + 롱프레스 감지
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
    final scaledChild = AnimatedScale(
      scale: _pressed ? 0.92 : 1.0,
      duration: const Duration(milliseconds: 90),
      curve: Curves.easeOut,
      child: widget.child,
    );

    return Material(
      color: Colors.transparent,
      child: GestureDetector(
        onLongPressStart: widget.enabled ? widget.onLongPressStart : null,
        onLongPressEnd: widget.enabled ? widget.onLongPressEnd : null,
        child: InkWell(
          onTap: widget.enabled ? widget.onTap : null,
          onHighlightChanged: (v) => setState(() => _pressed = v && widget.enabled),
          splashColor: Colors.lightBlue.withOpacity(0.12),
          highlightColor: Colors.lightBlue.withOpacity(0.06),
          child: scaledChild,
        ),
      ),
    );
  }
}
