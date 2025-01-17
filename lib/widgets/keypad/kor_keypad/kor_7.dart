import 'package:flutter/material.dart';
import '../../../utils/keypad_utils.dart';


class Kor7 extends StatelessWidget {
  final Function(String) onKeyTap;

  const Kor7({super.key, required this.onKeyTap});

  @override
  Widget build(BuildContext context) {
    final keyRows = [
      ['', '소', ''],
      ['서', 'back', '사'],
      ['', '수', ''],
      ['', '', ''],
    ];
    return KorKeypadUtils.buildSubLayout(keyRows, onKeyTap);
  }
}
