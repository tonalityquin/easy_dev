import 'package:flutter/material.dart';
import 'keypad_utils.dart';

class Kor0 extends StatefulWidget {
  final Function(String) onKeyTap;
  const Kor0({super.key, required this.onKeyTap});

  @override
  State<Kor0> createState() => _Kor0State();
}

class _Kor0State extends State<Kor0> with TickerProviderStateMixin {
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
      ['', '호', '합'],
      ['허', 'back', '하'],
      ['', '', '해'],
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
