import 'package:flutter/material.dart';
class MonthlyBillSection extends StatelessWidget {
  final TextEditingController nameController;
  final TextEditingController amountController;
  final TextEditingController durationController;
  final String? selectedType;
  final Function(String?) onTypeChanged;
  final String selectedPeriodUnit;
  final Function(String?) onPeriodUnitChanged;

  const MonthlyBillSection({
    super.key,
    required this.nameController,
    required this.amountController,
    required this.durationController,
    required this.selectedType,
    required this.onTypeChanged,
    required this.selectedPeriodUnit,
    required this.onPeriodUnitChanged,
  });

  @override
  Widget build(BuildContext context) {
    final regularTypeOptions = ['월 주차', '주간권', '야간권', '주말권'];
    final periodUnitOptions = ['일', '주', '월'];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '정기 정산 입력',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),

        TextField(
          controller: nameController,
          decoration: const InputDecoration(
            labelText: '정기 정산 이름',
            hintText: '예: 월 정기권',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),

        DropdownButtonFormField<String>(
          value: regularTypeOptions.contains(selectedType) ? selectedType : null,
          decoration: const InputDecoration(
            labelText: '주차 타입',
            border: OutlineInputBorder(),
          ),
          items: regularTypeOptions
              .map((type) => DropdownMenuItem(value: type, child: Text(type)))
              .toList(),
          onChanged: onTypeChanged,
        ),
        const SizedBox(height: 16),

        DropdownButtonFormField<String>(
          value: selectedPeriodUnit,
          decoration: const InputDecoration(
            labelText: '기간 단위',
            border: OutlineInputBorder(),
          ),
          items: periodUnitOptions
              .map((unit) => DropdownMenuItem(value: unit, child: Text(unit)))
              .toList(),
          onChanged: onPeriodUnitChanged,
        ),
        const SizedBox(height: 16),

        TextField(
          controller: durationController,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            labelText: '주차 가능 시간',
            hintText: selectedPeriodUnit == '월'
                ? '예: 1 → 1개월'
                : selectedPeriodUnit == '주'
                ? '예: 2 → 2주'
                : '예: 3 → 3일',
            suffixText: selectedPeriodUnit,
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),

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
