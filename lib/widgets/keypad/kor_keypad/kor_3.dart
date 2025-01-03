import 'package:flutter/material.dart';
import 'package:easydev/utils/keypad_utils.dart';


class Kor3 extends StatelessWidget {
  final Function(String) onKeyTap;

  const Kor3({super.key, required this.onKeyTap});

  @override
  Widget build(BuildContext context) {
    final keyRows = [
      ['', '도', ''],
      ['더', 'back', '다'],
      ['', '두', ''],
      ['', '', ''],
    ];
    return KorKeypadUtils.buildSubLayout(keyRows, onKeyTap);
  }
}
