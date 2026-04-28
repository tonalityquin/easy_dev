
import 'package:flutter/material.dart';






class HqSwitchFab extends StatelessWidget {
  const HqSwitchFab({
    super.key,
    required this.label,
    required this.icon,
    required this.onPressed,
    this.backgroundColor,   
    this.foregroundColor,   
    this.tooltip,
    this.wideThreshold = 520,
  });

  final String label;
  final IconData icon;
  final VoidCallback onPressed;
  final Color? backgroundColor;
  final Color? foregroundColor;
  final String? tooltip;
  final double wideThreshold;

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width >= wideThreshold;

    
    final Color bg = backgroundColor ?? _HqPalette.hrBase;   
    final Color fg = foregroundColor ?? Colors.white;        

    final Widget fabChild = isWide
        ? FloatingActionButton.extended(
      onPressed: onPressed,
      label: Text(label),
      icon: Icon(icon),
      backgroundColor: bg,
      foregroundColor: fg,
    )
        : FloatingActionButton(
      onPressed: onPressed,
      backgroundColor: bg,
      foregroundColor: fg,
      child: Icon(icon),
    );

    return Tooltip(
      message: tooltip ?? label,
      child: Semantics(
        button: true,
        label: label,
        child: fabChild,
      ),
    );
  }
}


class _HqPalette {
  
  static const Color hrBase  = Color(0xFF1565C0); 
}
