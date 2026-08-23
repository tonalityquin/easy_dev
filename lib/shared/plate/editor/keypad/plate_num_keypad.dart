import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class PlateNumKeypad extends StatefulWidget {
  const PlateNumKeypad({
    super.key,
    required this.controller,
    required this.maxLength,
    this.onComplete,
    this.onChangeFrontDigitMode,
    this.onReset,
    this.backgroundColor,
    this.textStyle,
    this.enableDigitModeSwitch = true,
    this.height = 248.0,
    this.replaceExistingOnFirstInput = false,
    this.debugName = 'number',
    this.onDebug,
  });

  final TextEditingController controller;
  final int maxLength;
  final VoidCallback? onComplete;
  final ValueChanged<bool>? onChangeFrontDigitMode;
  final VoidCallback? onReset;
  final Color? backgroundColor;
  final TextStyle? textStyle;
  final bool enableDigitModeSwitch;
  final double height;
  final bool replaceExistingOnFirstInput;
  final String debugName;
  final ValueChanged<String>? onDebug;

  @override
  State<PlateNumKeypad> createState() => _PlateNumKeypadState();
}

class _PlateNumKeypadState extends State<PlateNumKeypad>
    with TickerProviderStateMixin {
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
  void didUpdateWidget(covariant PlateNumKeypad oldWidget) {
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

  List<String> _lastRowKeys() {
    if (widget.enableDigitModeSwitch) {
      return ['두자리', '0', '세자리'];
    }
    if (widget.onReset != null) {
      return ['처음', '0', '처음'];
    }
    return ['', '0', ''];
  }

  @override
  Widget build(BuildContext context) {
    final bg = widget.backgroundColor ?? Theme.of(context).colorScheme.surface;
    final rows = <List<String>>[
      ['1', '2', '3'],
      ['4', '5', '6'],
      ['7', '8', '9'],
      _lastRowKeys(),
    ];

    return Semantics(
      container: true,
      label: '숫자 키패드',
      child: Container(
        decoration: BoxDecoration(
          color: bg,
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
          child: Column(
            children: List.generate(rows.length, (r) {
              return Expanded(child: _buildRow(rows[r], rowIndex: r));
            }),
          ),
        ),
      ),
    );
  }

  Widget _buildRow(List<String> keys, {required int rowIndex}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: List.generate(keys.length, (col) {
        return _buildKeyButton(keys[col], rowIndex: rowIndex, colIndex: col);
      }),
    );
  }

  Widget _buildKeyButton(
    String label, {
    required int rowIndex,
    required int colIndex,
  }) {
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
    final labelStyle = (widget.textStyle ??
            const TextStyle(fontSize: 18, fontWeight: FontWeight.w500))
        .copyWith(color: Theme.of(context).colorScheme.onSurface);

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
            _handleKeyTap(label);
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
                child: Center(child: Text(label, style: labelStyle)),
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _semanticLabel(String label) {
    switch (label) {
      case '두자리':
        return '두 자리 모드';
      case '세자리':
        return '세 자리 모드';
      case '처음':
        return '처음으로';
      default:
        return RegExp(r'^[0-9]$').hasMatch(label) ? '숫자 $label' : label;
    }
  }

  void _writeKey(String key) {
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
      return;
    }
    if (widget.controller.text.length >= widget.maxLength) return;
    final next = '${widget.controller.text}$key';
    widget.controller.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: next.length),
    );
  }

  void _handleKeyTap(String key) {
    if (key == '두자리') {
      widget.onChangeFrontDigitMode?.call(false);
      return;
    }
    if (key == '세자리') {
      widget.onChangeFrontDigitMode?.call(true);
      return;
    }
    if (key == '처음') {
      widget.onReset?.call();
      return;
    }

    _writeKey(key);
    if (widget.controller.text.length == widget.maxLength) {
      Future.microtask(() => widget.onComplete?.call());
    }
  }
}
