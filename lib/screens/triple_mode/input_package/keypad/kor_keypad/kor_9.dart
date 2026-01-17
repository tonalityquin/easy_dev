import 'package:flutter/material.dart';
import 'keypad_utils.dart';

class Kor9 extends StatefulWidget {
  final Function(String) onKeyTap;
  const Kor9({super.key, required this.onKeyTap});

  @override
  State<Kor9> createState() => _Kor9State();
}

class _Kor9State extends State<Kor9> with TickerProviderStateMixin {
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
      ['', '조', ''],
      ['저', 'back', '자'],
      ['', '주', ''],
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
