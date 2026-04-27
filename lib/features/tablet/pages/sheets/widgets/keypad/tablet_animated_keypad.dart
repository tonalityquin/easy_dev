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
    final cs = Theme.of(context).colorScheme;
    final theme = Theme.of(context);

    final keypad = Container(
      
      padding: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        
        color: cs.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        boxShadow: [
          BoxShadow(
            
            color: theme.shadowColor.withOpacity(0.12),
            blurRadius: 6,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      
      constraints: fullHeight
          ? const BoxConstraints() 
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
        
            ? SizedBox.expand(child: keypad)
            : keypad,
      ),
    );
  }
}
