import 'package:flutter/material.dart';

class BillTypeInput extends StatelessWidget {
  final TextEditingController controller;

  const BillTypeInput({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      decoration: InputDecoration(
        labelText: '요금 종류',
        hintText: '예: 기본 요금',
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }
}
