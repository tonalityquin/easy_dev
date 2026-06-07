import 'package:flutter/material.dart';

const _bottomPanel = Color(0xFFFFFFFF);
const _bottomLine = Color(0xFFD8DEE8);

class MonthlyBottomNavigation extends StatelessWidget {
  final bool showKeypad;
  final Widget keypad;
  final Widget actionButton;
  final VoidCallback? onTap;
  final Color? backgroundColor;

  const MonthlyBottomNavigation({
    super.key,
    required this.showKeypad,
    required this.keypad,
    required this.actionButton,
    this.onTap,
    this.backgroundColor,
  });

  static const _duration = Duration(milliseconds: 180);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap ?? () {},
      child: SafeArea(
        top: false,
        child: AnimatedContainer(
          duration: _duration,
          curve: Curves.easeOut,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: backgroundColor ?? _bottomPanel,
            border: const Border(top: BorderSide(color: _bottomLine)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(.08),
                blurRadius: 14,
                offset: const Offset(0, -3),
              ),
            ],
          ),
          child: AnimatedSwitcher(
            duration: _duration,
            switchInCurve: Curves.easeOut,
            switchOutCurve: Curves.easeIn,
            child: showKeypad
                ? KeyedSubtree(key: const ValueKey('keypad'), child: keypad)
                : KeyedSubtree(key: const ValueKey('action'), child: actionButton),
          ),
        ),
      ),
    );
  }
}
