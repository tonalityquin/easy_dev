import 'package:flutter/material.dart';

import '../utils/double_input_plate_field.dart';
import '../widgets/double_input_region_bottom_sheet.dart';

class DoubleInputPlateSection extends StatelessWidget {
  final String dropdownValue;
  final List<String> regions;
  final TextEditingController controllerFrontDigit;
  final TextEditingController controllerMidDigit;
  final TextEditingController controllerBackDigit;
  final TextEditingController activeController;
  final ValueChanged<TextEditingController> onKeypadStateChanged;
  final ValueChanged<String> onRegionChanged;
  final bool isThreeDigit;

  const DoubleInputPlateSection({
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
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '번호 입력',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w900,
            color: cs.onSurface,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () {
                  doubleInputRegionPickerBottomSheet(
                    context: context,
                    selectedRegion: dropdownValue,
                    regions: regions,
                    onConfirm: onRegionChanged,
                  );
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerLow,
                    border: Border.all(color: cs.outlineVariant.withOpacity(0.85)),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        dropdownValue,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                          color: cs.onSurface,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Icon(Icons.expand_more, color: cs.onSurfaceVariant),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: DoubleInputPlateField(
                frontDigitCount: isThreeDigit ? 3 : 2,
                hasMiddleChar: true,
                backDigitCount: 4,
                frontController: controllerFrontDigit,
                middleController: controllerMidDigit,
                backController: controllerBackDigit,
                activeController: activeController,
                onKeypadStateChanged: onKeypadStateChanged,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
