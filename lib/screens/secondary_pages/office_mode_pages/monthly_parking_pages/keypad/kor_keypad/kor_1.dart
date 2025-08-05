import 'package:flutter/material.dart';
import 'keypad_utils.dart';

class Kor1 extends StatefulWidget {
  final Function(String) onKeyTap;

  const Kor1({super.key, required this.onKeyTap});

  @override
  State<Kor1> createState() => _Kor1State();
}

class _Kor1State extends State<Kor1> with TickerProviderStateMixin {
  final Map<String, AnimationController> _controllers = {};
  final Map<String, bool> _isPressed = {};

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final keyRows = [
      ['', '고', ''],
      ['거', 'back', '가'],
      ['공', '구', '국'],
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
