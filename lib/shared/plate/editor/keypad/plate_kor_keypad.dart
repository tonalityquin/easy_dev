import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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

class PlateKorKeypad extends StatefulWidget {
  const PlateKorKeypad({
    super.key,
    required this.controller,
    this.onComplete,
    this.onReset,
    this.maxLength = 1,
    this.height = 248.0,
    this.replaceExistingOnFirstInput = false,
    this.debugName = 'middle',
    this.onDebug,
  });

  final TextEditingController controller;
  final VoidCallback? onComplete;
  final VoidCallback? onReset;
  final int maxLength;
  final double height;
  final bool replaceExistingOnFirstInput;
  final String debugName;
  final ValueChanged<String>? onDebug;

  @override
  State<PlateKorKeypad> createState() => _PlateKorKeypadState();
}

class _PlateKorKeypadState extends State<PlateKorKeypad>
    with TickerProviderStateMixin {
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
  final Map<String, AnimationController> _controllers = {};
  final Map<String, bool> _isPressed = {};
  late bool _replaceOnNextInput;

  @override
  void initState() {
    super.initState();
    _replaceOnNextInput = widget.replaceExistingOnFirstInput &&
        widget.controller.text.trim().isNotEmpty;
  }

  @override
  void didUpdateWidget(covariant PlateKorKeypad oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller ||
        oldWidget.maxLength != widget.maxLength) {
      _replaceOnNextInput = widget.replaceExistingOnFirstInput &&
          widget.controller.text.trim().isNotEmpty;
    }
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: '한글 키패드',
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          boxShadow: const [
            BoxShadow(
              color: Colors.black12,
              blurRadius: 6,
              offset: Offset(0, -2),
            ),
          ],
        ),
        padding: const EdgeInsets.symmetric(vertical: 6.0, horizontal: 12),
        child: SizedBox(
          height: widget.height,
          child: activeSubLayout == null
              ? _buildMainLayoutExpanded()
              : _buildActiveSubLayoutExpanded(),
        ),
      ),
    );
  }

  Widget _buildMainLayoutExpanded() {
    const rows = [
      ['ㄱ', 'ㄴ', 'ㄷ'],
      ['ㄹ', 'ㅁ', 'ㅂ'],
      ['ㅅ', 'ㅇ', 'ㅈ'],
      ['공란', 'ㅎ', '공란'],
    ];
    return Column(
      children: List.generate(rows.length, (r) {
        return Expanded(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: List.generate(rows[r].length, (c) {
              return _buildMainKeyButton(rows[r][c], r, c);
            }),
          ),
        );
      }),
    );
  }

  Widget _buildMainKeyButton(String label, int rowIndex, int colIndex) {
    if (label.isEmpty) {
      return const Expanded(child: SizedBox());
    }

    final id = '$label#$rowIndex:$colIndex';
    _controllers.putIfAbsent(
      id,
      () => AnimationController(
        duration: const Duration(milliseconds: 80),
        vsync: this,
        lowerBound: 0.0,
        upperBound: 0.1,
      ),
    );
    _isPressed.putIfAbsent(id, () => false);

    final controller = _controllers[id]!;
    final animation = Tween(begin: 1.0, end: 0.85).animate(
      CurvedAnimation(parent: controller, curve: Curves.easeOut),
    );
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;

    return Expanded(
      child: Padding(
        padding: const EdgeInsets.all(4.0),
        child: GestureDetector(
          onTapDown: (_) {
            HapticFeedback.selectionClick();
            setState(() => _isPressed[id] = true);
            if (!reduceMotion) controller.forward();
          },
          onTapUp: (_) {
            setState(() => _isPressed[id] = false);
            if (reduceMotion) {
              controller.value = 0;
            } else {
              Future.delayed(const Duration(milliseconds: 100), () {
                if (mounted) controller.reverse();
              });
            }
            _handleMainKeyTap(label);
          },
          onTapCancel: () {
            setState(() => _isPressed[id] = false);
            if (reduceMotion) {
              controller.value = 0;
            } else {
              controller.reverse();
            }
          },
          child: Semantics(
            button: true,
            label: _semanticLabel(label),
            child: ScaleTransition(
              scale: animation,
              child: Container(
                constraints: const BoxConstraints(minHeight: 48),
                padding: const EdgeInsets.symmetric(vertical: 12.0),
                decoration: BoxDecoration(
                  color: _isPressed[id]!
                      ? Theme.of(context)
                          .colorScheme
                          .primaryContainer
                          .withOpacity(0.6)
                      : Theme.of(context)
                          .colorScheme
                          .surfaceVariant
                          .withOpacity(0.4),
                  borderRadius: BorderRadius.zero,
                  border: Border.all(
                    color: Theme.of(context).colorScheme.outlineVariant,
                  ),
                ),
                child: Center(
                  child: Text(
                    label,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w500,
                      color: Colors.black87,
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

  String _semanticLabel(String label) {
    return label == '공란' ? '공란' : '자음 $label';
  }

  Widget _buildActiveSubLayoutExpanded() {
    return SizedBox.expand(child: _buildActiveSubLayout());
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
    if (keyToSubLayout.containsKey(key)) {
      setState(() => activeSubLayout = keyToSubLayout[key]);
      return;
    }
    if (key == '공란') {
      Future.microtask(() => widget.onComplete?.call());
    }
  }

  void _handleSubKeyTap(String key) {
    if (key == 'back') {
      setState(() => activeSubLayout = null);
      return;
    }
    _processKeyInput(key);
  }

  void _processKeyInput(String key) {
    final previous = widget.controller.text;
    if (_replaceOnNextInput) {
      _replaceOnNextInput = false;
      widget.controller.value = TextEditingValue(
        text: key,
        selection: TextSelection.collapsed(offset: key.length),
      );
      if (previous.trim().isNotEmpty) {
        widget.onDebug?.call(
          'identity_keypad=first_input_replaced target=${widget.debugName} previous=$previous next=$key',
        );
      }
      Future.microtask(() => widget.onComplete?.call());
      return;
    }
    if (widget.controller.text.length >= widget.maxLength) {
      Future.microtask(() => widget.onComplete?.call());
      return;
    }
    final next = '${widget.controller.text}$key';
    widget.controller.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: next.length),
    );
    Future.microtask(() => widget.onComplete?.call());
  }
}
