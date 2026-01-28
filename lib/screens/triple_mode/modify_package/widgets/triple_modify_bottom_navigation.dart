import 'package:flutter/material.dart';

class _Brand {
  static Color border(ColorScheme cs) => cs.outlineVariant.withOpacity(0.85);
  static Color overlay(ColorScheme cs) => cs.outlineVariant.withOpacity(0.12);
}

class TripleModifyBottomNavigation extends StatelessWidget {
  final bool? showKeypad;
  final Widget? keypad;
  final Widget actionButton;
  final VoidCallback? onTap;
  final Color? backgroundColor;

  const TripleModifyBottomNavigation({
    super.key,
    this.showKeypad,
    this.keypad,
    required this.actionButton,
    this.onTap,
    this.backgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final bg = backgroundColor ?? cs.surface;

    return Material(
      color: bg,
      child: InkWell(
        onTap: onTap ?? () {},
        overlayColor: MaterialStateProperty.resolveWith<Color?>(
              (states) => states.contains(MaterialState.pressed) ? _Brand.overlay(cs) : null,
        ),
        child: Container(
          decoration: BoxDecoration(
            color: bg,
            border: Border(top: BorderSide(color: _Brand.border(cs), width: 1)),
          ),
          padding: const EdgeInsets.all(16.0),
          child: _buildContent(),
        ),
      ),
    );
  }

  Widget _buildContent() {
    if (showKeypad == true && keypad != null) {
      return keypad!;
    }
    return actionButton;
  }
}
