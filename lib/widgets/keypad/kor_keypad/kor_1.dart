import 'package:flutter/material.dart';
import '../../../utils/keypad_utils.dart';


class Kor1 extends StatelessWidget {
  final Function(String) onKeyTap;

  const Kor1({super.key, required this.onKeyTap});

  @override
  Widget build(BuildContext context) {
    final keyRows = [
      ['', '고', ''],
      ['거', 'back', '가'],
      ['공', '구', '국'],
      ['', '', ''],
    ];
    return KorKeypadUtils.buildSubLayout(keyRows, onKeyTap);
  }
}
