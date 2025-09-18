import 'package:flutter/material.dart';
import 'keypad_utils.dart';

class Kor6 extends StatefulWidget {
  final Function(String) onKeyTap;
  const Kor6({super.key, required this.onKeyTap});

  @override
  State<Kor6> createState() => _Kor6State();
}

class _Kor6State extends State<Kor6> with TickerProviderStateMixin {
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
      ['', '보', ''],
      ['버', 'back', '바'],
      ['', '부', '배'],
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
