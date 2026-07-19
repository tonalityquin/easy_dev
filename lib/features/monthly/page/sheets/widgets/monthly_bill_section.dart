import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../../design_system/prompt_ui/prompt_ui_theme.dart';
import '../../../domain/monthly_parking_options.dart';
import '../../widgets/monthly_prompt_ui.dart';

class MonthlyBillSection extends StatelessWidget {
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

  final TextEditingController nameController;
  final TextEditingController amountController;
  final TextEditingController durationController;
  final String? selectedType;
  final ValueChanged<String?> onTypeChanged;
  final String selectedPeriodUnit;
  final ValueChanged<String?> onPeriodUnitChanged;
  final ValueChanged<String>? onDurationChanged;
  final bool isEditMode;

  @override
  Widget build(BuildContext context) {
    final tokens = PromptUiTheme.of(context);
    final textTheme = Theme.of(context).textTheme;
    final regularTypeOptions = MonthlyParkingOptions.regularTypes;

    return MonthlyPromptSection(
      title: '상품과 정산',
      subtitle: '정기권 이름, 타입, 요금과 적용 기간을 설정합니다.',
      icon: Icons.receipt_long_outlined,
      delay: const Duration(milliseconds: 55),
      trailing: isEditMode
          ? const MonthlyPromptBadge(
              label: '수정',
              icon: Icons.edit_outlined,
            )
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: nameController,
            readOnly: isEditMode,
            enabled: !isEditMode,
            style: textTheme.bodyLarge?.copyWith(
              color: isEditMode ? tokens.textDisabled : tokens.textPrimary,
              fontWeight: FontWeight.w700,
            ),
            decoration: monthlyPromptInputDecoration(
              context,
              label: '정기 정산 이름',
              enabled: !isEditMode,
              suffixIcon: isEditMode
                  ? Icon(Icons.lock_outline_rounded, color: tokens.iconDisabled)
                  : null,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: regularTypeOptions.contains(selectedType)
                      ? selectedType
                      : null,
                  decoration: monthlyPromptInputDecoration(
                    context,
                    label: '주차 타입',
                  ),
                  dropdownColor: tokens.surfaceRaised,
                  iconEnabledColor: tokens.iconSecondary,
                  style: textTheme.bodyLarge?.copyWith(
                    color: tokens.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                  items: regularTypeOptions
                      .map(
                        (type) => DropdownMenuItem<String>(
                          value: type,
                          child: Text(type),
                        ),
                      )
                      .toList(),
                  onChanged: onTypeChanged,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: InputDecorator(
                  decoration: monthlyPromptInputDecoration(
                    context,
                    label: '기간 단위',
                    enabled: false,
                    suffixIcon: Icon(
                      Icons.lock_outline_rounded,
                      color: tokens.iconDisabled,
                      size: 18,
                    ),
                  ),
                  child: Text(
                    selectedPeriodUnit,
                    style: textTheme.bodyLarge?.copyWith(
                      color: tokens.textPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
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
                  style: textTheme.bodyLarge?.copyWith(
                    color: tokens.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                  decoration: monthlyPromptInputDecoration(
                    context,
                    label: '기간',
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
                  style: textTheme.bodyLarge?.copyWith(
                    color: tokens.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                  decoration: monthlyPromptInputDecoration(
                    context,
                    label: '정기 요금',
                    suffixText: '원',
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            isEditMode
                ? '차량번호와 정산 이름은 수정 화면에서 변경할 수 없습니다.'
                : '상품을 선택하면 기간 단위와 종료일이 자동 계산됩니다.',
            style: textTheme.bodySmall?.copyWith(
              color: tokens.textSecondary,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }
}
