import 'package:flutter/material.dart';

class InputAnimatedActionButton extends StatefulWidget {
  final bool isLoading;
  final bool isLocationSelected;

  
  
  
  final bool isMinorMode;

  final Future<void> Function() onPressed;

  const InputAnimatedActionButton({
    super.key,
    required this.isLoading,
    required this.isLocationSelected,
    required this.onPressed,
    this.isMinorMode = false,
  });

  @override
  State<InputAnimatedActionButton> createState() => _InputAnimatedActionButtonState();
}

class _InputAnimatedActionButtonState extends State<InputAnimatedActionButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
      lowerBound: 0.95,
      upperBound: 1.0,
    );

    
    _controller.value = 1.0;

    _scaleAnimation = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
  }

  Future<void> _handleTap() async {
    await _controller.reverse();
    await _controller.forward();
    await widget.onPressed();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final bool isLoading = widget.isLoading;
    final bool isLocationSelected = widget.isLocationSelected;

    final bool requestMode = widget.isMinorMode && !isLocationSelected;
    final String label = requestMode ? '입차 요청' : '입차 완료';

    
    
    
    final bool isDisabled = isLoading || (!widget.isMinorMode && !isLocationSelected);

    final Color bg;
    final Color fg;
    final Color border;

    if (isDisabled) {
      bg = cs.surfaceContainerLow;
      fg = cs.onSurfaceVariant;
      border = cs.outlineVariant.withOpacity(0.85);
    } else if (requestMode) {
      
      bg = cs.secondary;
      fg = cs.onSecondary;
      border = cs.secondary.withOpacity(0.55);
    } else {
      
      bg = cs.primary;
      fg = cs.onPrimary;
      border = cs.primary.withOpacity(0.55);
    }

    return ScaleTransition(
      scale: _scaleAnimation,
      child: ElevatedButton(
        onPressed: isDisabled ? null : _handleTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: bg,
          foregroundColor: fg,
          elevation: 0,
          padding: const EdgeInsets.symmetric(vertical: 16.0, horizontal: 80),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: border, width: 1.5),
          ),
          disabledBackgroundColor: cs.surfaceContainerLow,
          disabledForegroundColor: cs.onSurfaceVariant,
        ).copyWith(
          overlayColor: MaterialStateProperty.resolveWith<Color?>(
                (states) {
              if (!states.contains(MaterialState.pressed)) return null;
              return requestMode
                  ? cs.secondary.withOpacity(0.10)
                  : cs.primary.withOpacity(0.10);
            },
          ),
        ),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          transitionBuilder: (Widget child, Animation<double> animation) {
            return ScaleTransition(scale: animation, child: child);
          },
          child: isLoading
              ? SizedBox(
            key: const ValueKey('loading'),
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(fg),
            ),
          )
              : Text(
            key: const ValueKey('buttonText'),
            label,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
          ),
        ),
      ),
    );
  }
}
