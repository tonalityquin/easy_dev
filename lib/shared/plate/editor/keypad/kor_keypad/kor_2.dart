import 'package:flutter/material.dart';
import 'keypad_utils.dart';

class Kor2 extends StatefulWidget {
  final Function(String) onKeyTap;
  const Kor2({super.key, required this.onKeyTap});

  @override
  State<Kor2> createState() => _Kor2State();
}

class _Kor2State extends State<Kor2> with TickerProviderStateMixin {
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
      ['', '노', ''],
      ['너', 'back', '나'],
      ['', '누', ''],
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
