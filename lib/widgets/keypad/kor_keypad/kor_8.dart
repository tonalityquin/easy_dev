import 'package:flutter/material.dart';
import '../../../utils/keypad_utils.dart';

class Kor8 extends StatelessWidget {
  final Function(String) onKeyTap;

  const Kor8({super.key, required this.onKeyTap});

  @override
  Widget build(BuildContext context) {
    final keyRows = [
      ['', '오', ''],
      ['어', 'back', '아'],
      ['임', '우', '육'],
      ['', '', ''],
    ];
    return KorKeypadUtils.buildSubLayout(keyRows, onKeyTap);
  }
}
