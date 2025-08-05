import 'package:flutter/material.dart';

class MonthlyBillSection extends StatelessWidget {
  final TextEditingController nameController;
  final TextEditingController amountController;
  final TextEditingController durationController;
  final String? selectedType;
  final Function(String?) onTypeChanged;

  const MonthlyBillSection({
    super.key,
    required this.nameController,
    required this.amountController,
    required this.durationController,
    required this.selectedType,
    required this.onTypeChanged,
  });

  @override
  Widget build(BuildContext context) {
    final regularTypeOptions = ['월 주차'];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '정기 정산 입력',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),

        // 📌 정기 정산 이름 입력
        TextField(
          controller: nameController,
          decoration: const InputDecoration(
            labelText: '정기 정산 이름',
            hintText: '예: 월 정기권',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),

        // 📌 주차 타입 선택
        DropdownButtonFormField<String>(
          value: selectedType,
          decoration: const InputDecoration(
            labelText: '주차 타입',
            border: OutlineInputBorder(),
          ),
          items: regularTypeOptions.map((type) => DropdownMenuItem(value: type, child: Text(type))).toList(),
          onChanged: onTypeChanged,
        ),
        const SizedBox(height: 16),

        // 📌 주차 가능 시간 입력
        TextField(
          controller: durationController,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: '주차 가능 시간',
            hintText: '예: 720',
            suffixText: '시간',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),

        // 📌 정기 요금 입력
        TextField(
          controller: amountController,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: '정기 요금',
            hintText: '예: 10000',
            border: OutlineInputBorder(),
          ),
        ),
      ],
    );
  }
}
