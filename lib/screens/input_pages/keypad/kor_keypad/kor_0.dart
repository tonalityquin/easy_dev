import 'package:flutter/material.dart';
import 'keypad_utils.dart';

class Kor0 extends StatelessWidget {
  final Function(String) onKeyTap;

  const Kor0({super.key, required this.onKeyTap});

  @override
  Widget build(BuildContext context) {
    final keyRows = [
      ['', '호', '합'],
      ['허', 'back', '하'],
      ['', '', '해'],
      ['', '', ''],
    ];
    return KorKeypadUtils.buildSubLayout(keyRows, onKeyTap);
  }
}
