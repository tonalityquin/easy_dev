import 'package:flutter/material.dart';
import '../keypad/tablet_num_keypad_for_tablet_plate_search.dart';

class TabletAnimatedKeypad extends StatelessWidget {
  final Animation<Offset> slideAnimation;
  final Animation<double> fadeAnimation;
  final TextEditingController controller;
  final VoidCallback onComplete;
  final VoidCallback onReset;
  final int maxLength;
  final bool enableDigitModeSwitch;
  /// Small Pad에서 키패드를 화면 100%로 확장하려면 true
  final bool fullHeight;

  const TabletAnimatedKeypad({
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
      // fullHeight가 true라도 내부 키패드가 전체를 자연스럽게 차지하도록 여백 최소화
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
          ? const BoxConstraints() // 제약 없음
          : BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.45),
      child: TabletNumKeypadForTabletPlateSearch(
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
        // 🔹 스몰패드에서는 패널(가용 영역)을 전부 채움
            ? SizedBox.expand(child: keypad)
            : keypad,
      ),
    );
  }
}
