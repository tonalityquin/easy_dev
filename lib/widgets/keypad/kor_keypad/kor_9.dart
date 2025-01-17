import 'package:flutter/material.dart';
import '../../../utils/keypad_utils.dart';


class Kor9 extends StatelessWidget {
  final Function(String) onKeyTap;

  const Kor9({super.key, required this.onKeyTap});

  @override
  Widget build(BuildContext context) {
    final keyRows = [
      ['', '조', ''],
      ['저', 'back', '자'],
      ['', '주', ''],
      ['', '', ''],
    ];
    return KorKeypadUtils.buildSubLayout(keyRows, onKeyTap);
  }
}
