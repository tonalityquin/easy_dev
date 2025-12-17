import 'package:flutter/material.dart';

class _SvcColors {
  static const base = Color(0xFF0D47A1);
  static const dark = Color(0xFF09367D);
  static const light = Color(0xFF5472D3);
}

class MonthlyBillSection extends StatelessWidget {
  final TextEditingController nameController;
  final TextEditingController amountController;
  final TextEditingController durationController;
  final String? selectedType;
  final Function(String?) onTypeChanged;
  final String selectedPeriodUnit;
  final Function(String?) onPeriodUnitChanged;

  /// ✅ 수정 모드: 이름(정기 정산 이름) 수정 불가
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
    this.isEditMode = false,
  });

  InputDecoration _svcInputDecoration(
      BuildContext context, {
        required String label,
        String? hint,
        String? suffixText,
        Widget? suffixIcon,
        bool disabledTone = false,
      }) {
    final cs = Theme.of(context).colorScheme;

    return InputDecoration(
      labelText: label,
      hintText: hint,
      suffixText: suffixText,
      suffixIcon: suffixIcon,
      floatingLabelStyle: const TextStyle(
        color: _SvcColors.dark,
        fontWeight: FontWeight.w700,
      ),
      filled: true,
      fillColor: disabledTone
          ? cs.surfaceVariant.withOpacity(.55)
          : _SvcColors.light.withOpacity(.06),
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: _SvcColors.light.withOpacity(.45)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _SvcColors.base, width: 1.2),
      ),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: cs.error.withOpacity(.8)),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: cs.error, width: 1.4),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    final regularTypeOptions = ['월 주차', '주간권', '야간권', '주말권'];
    final periodUnitOptions = ['일', '주', '월'];

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outlineVariant.withOpacity(.55)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 헤더
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: _SvcColors.light.withOpacity(.18),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: _SvcColors.light.withOpacity(.40)),
                ),
                child: const Icon(Icons.receipt_long_outlined, color: _SvcColors.dark),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '정기 정산 입력',
                  style: text.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: _SvcColors.dark,
                  ),
                ),
              ),
              if (isEditMode)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: cs.surfaceVariant.withOpacity(.7),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: cs.outlineVariant.withOpacity(.7)),
                  ),
                  child: Text(
                    '수정 모드',
                    style: text.bodySmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: cs.onSurface.withOpacity(.65),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),

          // ✅ 이름(수정 모드 잠금)
          TextField(
            controller: nameController,
            readOnly: isEditMode,
            enabled: !isEditMode,
            decoration: _svcInputDecoration(
              context,
              label: '정기 정산 이름',
              hint: '예: 월 정기권',
              disabledTone: isEditMode,
              suffixIcon: isEditMode
                  ? const Icon(Icons.lock_outline, color: _SvcColors.dark)
                  : null,
            ),
          ),
          const SizedBox(height: 12),

          // 주차 타입
          DropdownButtonFormField<String>(
            value: regularTypeOptions.contains(selectedType) ? selectedType : null,
            decoration: _svcInputDecoration(context, label: '주차 타입'),
            items: regularTypeOptions
                .map((type) => DropdownMenuItem(value: type, child: Text(type)))
                .toList(),
            onChanged: onTypeChanged,
            iconEnabledColor: _SvcColors.base,
            dropdownColor: cs.surface,
          ),
          const SizedBox(height: 12),

          // 기간 단위
          DropdownButtonFormField<String>(
            value: selectedPeriodUnit,
            decoration: _svcInputDecoration(context, label: '기간 단위'),
            items: periodUnitOptions
                .map((unit) => DropdownMenuItem(value: unit, child: Text(unit)))
                .toList(),
            onChanged: onPeriodUnitChanged,
            iconEnabledColor: _SvcColors.base,
            dropdownColor: cs.surface,
          ),
          const SizedBox(height: 12),

          // 기간
          TextField(
            controller: durationController,
            keyboardType: TextInputType.number,
            decoration: _svcInputDecoration(
              context,
              label: '주차 가능 시간',
              hint: selectedPeriodUnit == '월'
                  ? '예: 1 → 1개월'
                  : selectedPeriodUnit == '주'
                  ? '예: 2 → 2주'
                  : '예: 3 → 3일',
              suffixText: selectedPeriodUnit,
            ),
          ),
          const SizedBox(height: 12),

          // 금액
          TextField(
            controller: amountController,
            keyboardType: TextInputType.number,
            decoration: _svcInputDecoration(
              context,
              label: '정기 요금',
              hint: '예: 10000',
            ),
          ),

          const SizedBox(height: 8),
          Text(
            isEditMode ? '이름/번호판은 수정할 수 없습니다.' : '입력 후 하단 버튼으로 생성하세요.',
            style: text.bodySmall?.copyWith(
              color: Colors.black.withOpacity(.55),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
