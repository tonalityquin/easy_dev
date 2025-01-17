import 'package:flutter/material.dart';
import '../../../utils/keypad_utils.dart';


class Kor2 extends StatelessWidget {
  final Function(String) onKeyTap;

  const Kor2({super.key, required this.onKeyTap});

  @override
  Widget build(BuildContext context) {
    final keyRows = [
      ['', '노', ''],
      ['너', 'back', '나'],
      ['', '누', ''],
      ['', '', ''],
    ];
    return KorKeypadUtils.buildSubLayout(keyRows, onKeyTap);
  }
}
