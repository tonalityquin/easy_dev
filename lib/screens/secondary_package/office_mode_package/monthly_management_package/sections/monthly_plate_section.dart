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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '번호 입력',
          style: text.titleMedium?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // 지역 선택: 접근성/피드백/비활성화 반영
            Semantics(
              button: true,
              enabled: !isEditMode,
              label: '지역 선택: $dropdownValue',
              child: OutlinedButton(
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
                style: OutlinedButton.styleFrom(
                  foregroundColor: cs.primary,
                  side: BorderSide(color: cs.primary, width: 1),
                  backgroundColor: cs.surface,
                  padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 160),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Expanded(
                        child: Text(
                          dropdownValue,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: text.bodyLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: cs.primary,
                            letterSpacing: .2,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Icon(Icons.expand_more, size: 18, color: cs.primary),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            // 번호판 입력 필드
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
    );
  }
}
