import 'package:flutter/material.dart';
import 'keypad_utils.dart';

class Kor6 extends StatelessWidget {
  final Function(String) onKeyTap;

  const Kor6({super.key, required this.onKeyTap});

  @override
  Widget build(BuildContext context) {
    final keyRows = [
      ['', '보', ''],
      ['버', 'back', '바'],
      ['', '부', '배'],
      ['', '', ''],
    ];
    return KorKeypadUtils.buildSubLayout(keyRows, onKeyTap);
  }
}
