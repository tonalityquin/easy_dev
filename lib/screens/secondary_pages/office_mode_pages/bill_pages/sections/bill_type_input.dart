import 'package:flutter/material.dart';

class BillTypeInput extends StatelessWidget {
  final TextEditingController controller;

  const BillTypeInput({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      decoration: InputDecoration(
        labelText: '일반 정산 유형',
        hintText: '예: 기본 요금',
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }
}
