import 'package:flutter/material.dart';
import '../utils/double_modify_plate_field.dart';
import '../widgets/double_modify_region_picker_bottom_sheet.dart';

class DoubleModifyPlateSection extends StatelessWidget {
  final String dropdownValue;
  final List<String> regions;
  final TextEditingController controllerFrontdigit;
  final TextEditingController controllerMidDigit;
  final TextEditingController controllerBackDigit;
  final bool isEditable;
  final ValueChanged<String> onRegionChanged;

  const DoubleModifyPlateSection({
    super.key,
    required this.dropdownValue,
    required this.regions,
    required this.controllerFrontdigit,
    required this.controllerMidDigit,
    required this.controllerBackDigit,
    this.isEditable = false,
    required this.onRegionChanged,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '번호 입력',
          style: TextStyle(fontSize: 18.0, fontWeight: FontWeight.w900, color: cs.onSurface),
        ),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            GestureDetector(
              onTap: () {
                doubleModifyRegionPickerBottomSheet(
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
            const SizedBox(width: 16),
            Expanded(
              child: Align(
                alignment: Alignment.center,
                child: DoubleModifyPlateInput(
                  frontDigitCount: 3,
                  hasMiddleChar: true,
                  backDigitCount: 4,
                  frontController: controllerFrontdigit,
                  middleController: controllerMidDigit,
                  backController: controllerBackDigit,
                  isEditable: isEditable,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
