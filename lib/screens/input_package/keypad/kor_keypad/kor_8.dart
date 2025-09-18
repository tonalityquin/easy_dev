import 'package:flutter/material.dart';
import 'keypad_utils.dart';

class Kor8 extends StatefulWidget {
  final Function(String) onKeyTap;
  const Kor8({super.key, required this.onKeyTap});

  @override
  State<Kor8> createState() => _Kor8State();
}

class _Kor8State extends State<Kor8> with TickerProviderStateMixin {
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
      ['', '오', ''],
      ['어', 'back', '아'],
      ['임', '우', '육'],
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
