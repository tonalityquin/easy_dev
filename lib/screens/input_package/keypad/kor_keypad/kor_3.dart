import 'package:flutter/material.dart';
import 'keypad_utils.dart';

class Kor3 extends StatefulWidget {
  final Function(String) onKeyTap;
  const Kor3({super.key, required this.onKeyTap});

  @override
  State<Kor3> createState() => _Kor3State();
}

class _Kor3State extends State<Kor3> with TickerProviderStateMixin {
  final Map<String, AnimationController> _controllers = {};
  final Map<String, bool> _isPressed = {};

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final keyRows = [
      ['', '도', ''],
      ['더', 'back', '다'],
      ['', '두', ''],
      ['', '', ''],
    ];
    return KorKeypadUtils.buildSubLayout(
      keyRows,
      widget.onKeyTap,
      state: this,
      controllers: _controllers,
      isPressed: _isPressed,
    );
  }
}
