import 'package:flutter/material.dart';
import 'keypad_utils.dart';

class Kor5 extends StatefulWidget {
  final Function(String) onKeyTap;
  const Kor5({super.key, required this.onKeyTap});

  @override
  State<Kor5> createState() => _Kor5State();
}

class _Kor5State extends State<Kor5> with TickerProviderStateMixin {
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
      ['', '모', ''],
      ['머', 'back', '마'],
      ['', '무', ''],
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
