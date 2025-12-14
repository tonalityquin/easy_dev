import 'package:flutter/material.dart';
import 'keypad_utils.dart';

class Kor4 extends StatefulWidget {
  final Function(String) onKeyTap;
  const Kor4({super.key, required this.onKeyTap});

  @override
  State<Kor4> createState() => _Kor4State();
}

class _Kor4State extends State<Kor4> with TickerProviderStateMixin {
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
      ['', '로', ''],
      ['러', 'back', '라'],
      ['', '루', ''],
      ['', '', ''],
    ];
    return KorKeypadUtils.buildSubLayout(
      keyRows,
      widget.onKeyTap,
      state: this,
      setState: setState,
      controllers: _controllers,
      isPressed: _isPressed,
    );
  }
}
