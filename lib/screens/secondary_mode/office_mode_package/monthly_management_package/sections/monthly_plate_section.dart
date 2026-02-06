import 'package:flutter/material.dart';
import '../utils/monthly_plate_field.dart';
import '../widgets/monthly_region_bottom_sheet.dart';

class MonthlyPlateSection extends StatelessWidget {
  final String dropdownValue;
  final List<String> regions;

  final TextEditingController controllerFrontDigit;
  final TextEditingController controllerMidDigit;
  final TextEditingController controllerBackDigit;

  final TextEditingController activeController;
  final ValueChanged<TextEditingController> onKeypadStateChanged;
  final ValueChanged<String> onRegionChanged;

  final bool isThreeDigit;
  final bool isEditMode;

  const MonthlyPlateSection({
    super.key,
    required this.dropdownValue,
    required this.regions,
    required this.controllerFrontDigit,
    required this.controllerMidDigit,
    required this.controllerBackDigit,
    required this.activeController,
    required this.onKeypadStateChanged,
    required this.onRegionChanged,
    required this.isThreeDigit,
    this.isEditMode = false,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outlineVariant.withOpacity(.55)),
        boxShadow: [
          BoxShadow(
            color: cs.shadow.withOpacity(.06),
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
                  color: cs.primaryContainer.withOpacity(.60),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: cs.outlineVariant.withOpacity(.55)),
                ),
                child: Icon(Icons.directions_car_outlined, color: cs.primary),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '번호 입력',
                  style: text.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: cs.onSurface,
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
                      color: cs.onSurfaceVariant.withOpacity(.85),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),

          Text(
            '지역을 선택하고 번호판을 입력하세요.',
            style: text.bodyMedium?.copyWith(
              color: cs.onSurfaceVariant.withOpacity(.78),
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),

          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // 지역 선택
              Semantics(
                button: true,
                enabled: !isEditMode,
                label: '지역 선택: $dropdownValue',
                child: OutlinedButton.icon(
                  onPressed: isEditMode
                      ? null
                      : () {
                    monthlyRegionPickerBottomSheet(
                      context: context,
                      selectedRegion: dropdownValue,
                      regions: regions,
                      onConfirm: onRegionChanged,
                    );
                  },
                  icon: const Icon(Icons.place_outlined, size: 18),
                  label: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 160),
                    child: Text(
                      dropdownValue,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w800),
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: cs.primary,
                    side: BorderSide(color: cs.primary.withOpacity(.45)),
                    backgroundColor: cs.surfaceVariant.withOpacity(.35),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),

              // 번호판 입력
              Expanded(
                child: MonthlyPlateField(
                  frontDigitCount: isThreeDigit ? 3 : 2,
                  hasMiddleChar: true,
                  backDigitCount: 4,
                  frontController: controllerFrontDigit,
                  middleController: controllerMidDigit,
                  backController: controllerBackDigit,
                  activeController: activeController,
                  onKeypadStateChanged: onKeypadStateChanged,
                  isEditMode: isEditMode,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
