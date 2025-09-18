import 'package:flutter/material.dart';
import 'keypad_utils.dart';

class Kor7 extends StatefulWidget {
  final Function(String) onKeyTap;
  const Kor7({super.key, required this.onKeyTap});

  @override
  State<Kor7> createState() => _Kor7State();
}

class _Kor7State extends State<Kor7> with TickerProviderStateMixin {
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
      ['', '소', ''],
      ['서', 'back', '사'],
      ['', '수', ''],
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
