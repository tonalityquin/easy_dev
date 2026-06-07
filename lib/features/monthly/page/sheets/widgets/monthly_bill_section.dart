import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

const _billInk = Color(0xFF101828);
const _billMuted = Color(0xFF667085);
const _billPanel = Color(0xFFFFFFFF);
const _billLine = Color(0xFFD8DEE8);
const _billBlue = Color(0xFF2563EB);

class MonthlyBillSection extends StatelessWidget {
  final TextEditingController nameController;
  final TextEditingController amountController;
  final TextEditingController durationController;
  final String? selectedType;
  final Function(String?) onTypeChanged;
  final String selectedPeriodUnit;
  final Function(String?) onPeriodUnitChanged;
  final ValueChanged<String>? onDurationChanged;
  final bool isEditMode;

  const MonthlyBillSection({
    super.key,
    required this.nameController,
    required this.amountController,
    required this.durationController,
    required this.selectedType,
    required this.onTypeChanged,
    required this.selectedPeriodUnit,
    required this.onPeriodUnitChanged,
    this.onDurationChanged,
    this.isEditMode = false,
  });

  InputDecoration _inputDecoration({
    required String label,
    String? hint,
    String? suffixText,
    Widget? suffixIcon,
    bool disabledTone = false,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      suffixText: suffixText,
      suffixIcon: suffixIcon,
      labelStyle: const TextStyle(color: _billMuted, fontWeight: FontWeight.w800),
      floatingLabelStyle: const TextStyle(color: _billBlue, fontWeight: FontWeight.w900),
      filled: true,
      fillColor: disabledTone ? const Color(0xFFEFF2F7) : const Color(0xFFF8FAFC),
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 13, vertical: 14),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: _billLine),
      ),
      disabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: _billLine),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: _billBlue, width: 1.4),
      ),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final regularTypeOptions = ['월 주차', '주간권', '야간권', '주말권'];
    final periodUnitOptions = ['일', '주', '월'];

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _billPanel,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _billLine),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: const Color(0xFFEFF6FF),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.receipt_long_outlined, color: _billBlue, size: 19),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '상품과 정산',
                      style: TextStyle(color: _billInk, fontWeight: FontWeight.w900, fontSize: 16),
                    ),
                    SizedBox(height: 2),
                    Text(
                      '정기권 이름, 타입, 요금, 기간을 입력합니다.',
                      style: TextStyle(color: _billMuted, fontWeight: FontWeight.w700, fontSize: 12),
                    ),
                  ],
                ),
              ),
              if (isEditMode)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: _billLine),
                  ),
                  child: const Text(
                    '수정',
                    style: TextStyle(color: _billMuted, fontWeight: FontWeight.w900, fontSize: 12),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          TextField(
            controller: nameController,
            readOnly: isEditMode,
            enabled: !isEditMode,
            style: const TextStyle(color: _billInk, fontWeight: FontWeight.w900),
            decoration: _inputDecoration(
              label: '정기 정산 이름',
              hint: '예: 월 정기권',
              disabledTone: isEditMode,
              suffixIcon: isEditMode ? const Icon(Icons.lock_outline, color: _billMuted) : null,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: regularTypeOptions.contains(selectedType) ? selectedType : null,
                  decoration: _inputDecoration(label: '주차 타입'),
                  dropdownColor: _billPanel,
                  iconEnabledColor: _billMuted,
                  style: const TextStyle(color: _billInk, fontWeight: FontWeight.w900),
                  items: regularTypeOptions.map((type) {
                    return DropdownMenuItem<String>(
                      value: type,
                      child: Text(type),
                    );
                  }).toList(),
                  onChanged: onTypeChanged,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: selectedPeriodUnit,
                  decoration: _inputDecoration(label: '기간 단위'),
                  dropdownColor: _billPanel,
                  iconEnabledColor: _billMuted,
                  style: const TextStyle(color: _billInk, fontWeight: FontWeight.w900),
                  items: periodUnitOptions.map((unit) {
                    return DropdownMenuItem<String>(
                      value: unit,
                      child: Text(unit),
                    );
                  }).toList(),
                  onChanged: onPeriodUnitChanged,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: durationController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  onChanged: onDurationChanged,
                  style: const TextStyle(color: _billInk, fontWeight: FontWeight.w900),
                  decoration: _inputDecoration(
                    label: '기간',
                    hint: selectedPeriodUnit == '월' ? '1개월' : selectedPeriodUnit == '주' ? '2주' : '3일',
                    suffixText: selectedPeriodUnit,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: amountController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  style: const TextStyle(color: _billInk, fontWeight: FontWeight.w900),
                  decoration: _inputDecoration(
                    label: '정기 요금',
                    hint: '100000',
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            isEditMode ? '차량번호와 정산 이름은 수정 모드에서 잠깁니다.' : '요금과 기간을 입력하면 기간 섹션에서 종료일이 자동 계산됩니다.',
            style: const TextStyle(color: _billMuted, fontWeight: FontWeight.w700, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
