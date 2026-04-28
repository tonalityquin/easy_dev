import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class NumKeypadForPlateSearch extends StatefulWidget {
  final TextEditingController controller;
  final int maxLength;
  final VoidCallback? onComplete;
  final ValueChanged<bool>? onChangeFrontDigitMode;
  final VoidCallback? onReset;

  
  final Color? backgroundColor;
  final TextStyle? textStyle;

  final bool enableDigitModeSwitch;

  const NumKeypadForPlateSearch({
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
  State<NumKeypadForPlateSearch> createState() => _NumKeypadForPlateSearchState();
}

class _NumKeypadForPlateSearchState extends State<NumKeypadForPlateSearch>
    with TickerProviderStateMixin {
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
    final cs = Theme.of(context).colorScheme;

    
    final Color panelBg = widget.backgroundColor ?? cs.surface;
    final Color divider = cs.outlineVariant.withOpacity(0.9);
    final Color shadowColor = cs.shadow.withOpacity(0.10);

    return Container(
      decoration: BoxDecoration(
        color: panelBg,
        borderRadius: BorderRadius.zero,
        boxShadow: [
          BoxShadow(
            color: shadowColor,
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
        border: Border(top: BorderSide(color: divider)),
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
      children: keys.map(_buildKeyButton).toList(),
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

    final cs = Theme.of(context).colorScheme;

    final controller = _controllers[key]!;
    final animation = Tween(begin: 1.0, end: 0.85).animate(
      CurvedAnimation(parent: controller, curve: Curves.easeOut),
    );

    final bool pressed = _isPressed[key] ?? false;

    
    final bool isDigit = RegExp(r'^\d$').hasMatch(key);
    final bool isModeKey = (key == '두자리' || key == '세자리');
    final bool isResetKey = (key == '처음');

    
    final Color baseBg = cs.surfaceContainerLow;
    final Color pressedBg = cs.primaryContainer.withOpacity(0.55);

    
    final Color functionBaseBg = cs.surfaceContainerHighest.withOpacity(0.65);
    final Color functionPressedBg = cs.primaryContainer.withOpacity(0.70);

    final Color bgColor = pressed
        ? (isDigit ? pressedBg : functionPressedBg)
        : (isDigit ? baseBg : functionBaseBg);

    final Color borderColor = cs.outlineVariant.withOpacity(0.9);

    
    final TextStyle baseTextStyle = widget.textStyle ??
        TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: cs.onSurface,
        );

    
    final TextStyle textStyle = (isModeKey || isResetKey)
        ? baseTextStyle.copyWith(
      fontSize: 16,
      fontWeight: FontWeight.w700,
      color: cs.onSurface,
    )
        : baseTextStyle.copyWith(color: cs.onSurface);

    return Expanded(
      child: Padding(
        padding: const EdgeInsets.all(4.0),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
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
              constraints: const BoxConstraints(minHeight: 48),
              padding: const EdgeInsets.symmetric(vertical: 12.0),
              decoration: BoxDecoration(
                color: bgColor,
                borderRadius: BorderRadius.zero,
                border: Border.all(color: borderColor),
              ),
              child: Center(
                child: Text(key, style: textStyle),
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

    
    if (!RegExp(r'^\d$').hasMatch(key)) return;

    if (widget.controller.text.length < widget.maxLength) {
      widget.controller.text += key;
      if (widget.controller.text.length == widget.maxLength) {
        Future.microtask(() => widget.onComplete?.call());
      }
    }
  }
}