import 'package:flutter/material.dart';
import '../keypad/num_keypad_for_tablet_plate_search.dart';

class AnimatedKeypad extends StatelessWidget {
  final Animation<Offset> slideAnimation;
  final Animation<double> fadeAnimation;
  final TextEditingController controller;
  final VoidCallback onComplete;
  final VoidCallback onReset;
  final int maxLength;
  final bool enableDigitModeSwitch;
  /// Small Pad에서 키패드를 화면 100%로 확장하려면 true
  final bool fullHeight;

  const AnimatedKeypad({
    super.key,
    required this.slideAnimation,
    required this.fadeAnimation,
    required this.controller,
    required this.onComplete,
    required this.onReset,
    this.maxLength = 4,
    this.enableDigitModeSwitch = false,
    this.fullHeight = false,
  });

  @override
  Widget build(BuildContext context) {
    final keypad = Container(
      padding: const EdgeInsets.only(bottom: 8),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        boxShadow: [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 6,
            offset: Offset(0, -2),
          ),
        ],
      ),
      // fullHeight=false(기본)일 때만 최대 높이 45% 제한
      constraints: fullHeight
          ? const BoxConstraints()
          : BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.45),
      child: NumKeypadForTabletPlateSearch(
        controller: controller,
        maxLength: maxLength,
        enableDigitModeSwitch: enableDigitModeSwitch,
        onComplete: onComplete,
        onReset: onReset,
      ),
    );

    return FadeTransition(
      opacity: fadeAnimation,
      child: SlideTransition(
        position: slideAnimation,
        child: fullHeight
            ? SizedBox.expand(child: keypad) // 화면 전체 채우기
            : keypad,
      ),
    );
  }
}
