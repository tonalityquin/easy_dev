import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class KorKeypadUtils {
  static Widget buildSubLayout(
      List<List<String>> keyRows,
      Function(String) onKeyTap, {
        required State state,
        Map<String, AnimationController>? controllers,
        Map<String, bool>? isPressed,
      }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: keyRows.map((row) {
        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: row.map((key) {
            return _buildAnimatedKeyButton(
              key,
              key.isNotEmpty ? () => onKeyTap(key) : null,
              state,
              controllers!,
              isPressed!,
            );
          }).toList(),
        );
      }).toList(),
    );
  }

  static Widget _buildAnimatedKeyButton(
      String key,
      VoidCallback? onTap,
      State state,
      Map<String, AnimationController> controllers,
      Map<String, bool> isPressed,
      ) {
    controllers.putIfAbsent(
      key,
          () => AnimationController(
        duration: const Duration(milliseconds: 80),
        vsync: state as TickerProvider,
        lowerBound: 0.0,
        upperBound: 0.1,
      ),
    );
    isPressed.putIfAbsent(key, () => false);

    final controller = controllers[key]!;
    final animation = Tween(begin: 1.0, end: 0.85).animate(
      CurvedAnimation(parent: controller, curve: Curves.easeOut),
    );

    return Expanded(
      child: Padding(
        padding: const EdgeInsets.all(4.0),
        child: GestureDetector(
          onTapDown: (_) {
            HapticFeedback.selectionClick();
            isPressed[key] = true;
            controller.forward();
          },
          onTapUp: (_) {
            isPressed[key] = false;
            Future.delayed(const Duration(milliseconds: 100), () {
              if (state.mounted) {
                controller.reverse();
              }
            });
            onTap?.call();
          },
          onTapCancel: () {
            isPressed[key] = false;
            controller.reverse();
          },
          child: ScaleTransition(
            scale: animation,
            child: Container(
              constraints: const BoxConstraints(minHeight: 48),
              padding: const EdgeInsets.symmetric(vertical: 12.0),
              decoration: BoxDecoration(
                color: isPressed[key]! ? Colors.lightBlue[100] : Colors.grey[50],
                borderRadius: BorderRadius.zero,
                border: Border.all(color: Colors.grey[300]!),
              ),
              child: Center(
                child: Text(
                  key,
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
    );
  }
}
