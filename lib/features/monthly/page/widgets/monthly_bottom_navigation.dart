import 'package:flutter/material.dart';





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

  static const _kDuration = Duration(milliseconds: 180);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final Color baseBg = backgroundColor ?? cs.surface;
    final Color effectiveBg = showKeypad ? cs.surfaceVariant.withOpacity(.55) : baseBg;

    final Color borderTop =
    showKeypad ? cs.primary.withOpacity(.18) : cs.outlineVariant.withOpacity(.50);

    return GestureDetector(
      onTap: onTap ?? () {},
      child: SafeArea(
        top: false,
        child: AnimatedContainer(
          duration: _kDuration,
          curve: Curves.easeOut,
          padding: const EdgeInsets.all(16.0),
          decoration: BoxDecoration(
            color: effectiveBg,
            border: Border(top: BorderSide(color: borderTop, width: 1)),
            boxShadow: [
              BoxShadow(
                color: cs.shadow.withOpacity(.08),
                blurRadius: 12,
                offset: const Offset(0, -2),
              ),
            ],
          ),
          child: _buildContent(),
        ),
      ),
    );
  }

  Widget _buildContent() {
    return Stack(
      children: [
        AnimatedOpacity(
          duration: _kDuration,
          opacity: showKeypad ? 0.0 : 1.0,
          curve: Curves.easeOut,
          child: Offstage(
            offstage: showKeypad,
            child: actionButton,
          ),
        ),
        AnimatedOpacity(
          duration: _kDuration,
          opacity: showKeypad ? 1.0 : 0.0,
          curve: Curves.easeOut,
          child: Offstage(
            offstage: !showKeypad,
            child: keypad,
          ),
        ),
      ],
    );
  }
}
