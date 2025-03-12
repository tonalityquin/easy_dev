import 'package:flutter/material.dart';
import '../../../utils/keypad_utils.dart';

class Kor4 extends StatelessWidget {
  final Function(String) onKeyTap;

  const Kor4({super.key, required this.onKeyTap});

  @override
  Widget build(BuildContext context) {
    final keyRows = [
      ['', '로', ''],
      ['러', 'back', '라'],
      ['', '루', ''],
      ['', '', ''],
    ];
    return KorKeypadUtils.buildSubLayout(keyRows, onKeyTap);
  }
}
