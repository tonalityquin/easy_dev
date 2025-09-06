import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class NumKeypadForTabletPlateSearch extends StatefulWidget {
  final TextEditingController controller;
  final int maxLength;
  final VoidCallback? onComplete;
  final ValueChanged<bool>? onChangeFrontDigitMode;
  final VoidCallback? onReset;
  final Color? backgroundColor;
  final TextStyle? textStyle;
  final bool enableDigitModeSwitch;

  const NumKeypadForTabletPlateSearch({
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
  State<NumKeypadForTabletPlateSearch> createState() => _NumKeypadForTabletPlateSearchState();
}

class _NumKeypadForTabletPlateSearchState extends State<NumKeypadForTabletPlateSearch> with TickerProviderStateMixin {
  final Map<String, AnimationController> _controllers = {};
  final Map<String, bool> _isPressed = {};

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: widget.backgroundColor ?? Colors.white,
        borderRadius: BorderRadius.zero,
        boxShadow: const [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 6,
            offset: Offset(0, -2),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(vertical: 6.0, horizontal: 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildRow(['1', '2', '3']),
          _buildRow(['4', '5', '6']),
          _buildRow(['7', '8', '9']),
          _buildRow(_lastRowKeys()),
        ],
      ),
    );
  }

  List<String> _lastRowKeys() {
    if (widget.enableDigitModeSwitch) {
      return ['두자리', '0', '세자리'];
    } else if (widget.onReset != null) {
      return ['처음', '0', '처음'];
    } else {
      return ['', '0', ''];
    }
  }

  Widget _buildRow(List<String> keys) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: keys.map((key) => _buildKeyButton(key)).toList(),
    );
  }

  Widget _buildKeyButton(String key) {
    if (key.isEmpty) {
      return const Expanded(child: SizedBox());
    }

    _controllers.putIfAbsent(
      key,
      () => AnimationController(
        duration: const Duration(milliseconds: 80),
        vsync: this,
        lowerBound: 0.0,
        upperBound: 0.1,
      ),
    );
    _isPressed.putIfAbsent(key, () => false);

    final controller = _controllers[key]!;
    final animation = Tween(begin: 1.0, end: 0.85).animate(
      CurvedAnimation(parent: controller, curve: Curves.easeOut),
    );

    return Expanded(
      child: Padding(
        padding: const EdgeInsets.all(4.0),
        child: GestureDetector(
          onTapDown: (_) {
            HapticFeedback.selectionClick();
            setState(() => _isPressed[key] = true);
            controller.forward();
          },
          onTapUp: (_) {
            setState(() => _isPressed[key] = false);
            Future.delayed(const Duration(milliseconds: 100), () {
              if (mounted) controller.reverse();
            });
            _handleKeyTap(key);
          },
          onTapCancel: () {
            setState(() => _isPressed[key] = false);
            controller.reverse();
          },
          child: ScaleTransition(
            scale: animation,
            child: Container(
              constraints: const BoxConstraints(
                minHeight: 48,
              ),
              padding: const EdgeInsets.symmetric(vertical: 12.0),
              decoration: BoxDecoration(
                color: _isPressed[key]! ? Colors.lightBlue[100] : Colors.grey[50],
                borderRadius: BorderRadius.zero,
                border: Border.all(color: Colors.grey[300]!),
              ),
              child: Center(
                child: Text(
                  key,
                  style: (widget.textStyle ??
                          const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w500,
                          ))
                      .copyWith(color: Colors.black87),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _handleKeyTap(String key) {
    if (key == '두자리') {
      widget.onChangeFrontDigitMode?.call(false);
      return;
    } else if (key == '세자리') {
      widget.onChangeFrontDigitMode?.call(true);
      return;
    } else if (key == '처음') {
      widget.onReset?.call();
      return;
    }

    if (widget.controller.text.length < widget.maxLength) {
      widget.controller.text += key;
      if (widget.controller.text.length == widget.maxLength) {
        Future.microtask(() {
          widget.onComplete?.call();
        });
      }
    }
  }
}
