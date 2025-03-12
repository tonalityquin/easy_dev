import 'package:flutter/material.dart';
import '../../../utils/keypad_utils.dart';

class Kor5 extends StatelessWidget {
  final Function(String) onKeyTap;

  const Kor5({super.key, required this.onKeyTap});

  @override
  Widget build(BuildContext context) {
    final keyRows = [
      ['', '모', ''],
      ['머', 'back', '마'],
      ['', '무', ''],
      ['', '', ''],
    ];
    return KorKeypadUtils.buildSubLayout(keyRows, onKeyTap);
  }
}
