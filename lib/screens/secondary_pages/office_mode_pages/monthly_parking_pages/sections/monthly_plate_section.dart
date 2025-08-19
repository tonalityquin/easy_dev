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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('번호 입력', style: TextStyle(fontSize: 18.0, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            GestureDetector(
              onTap: isEditMode
                  ? null
                  : () {
                monthlyRegionPickerBottomSheet(
                  context: context,
                  selectedRegion: dropdownValue,
                  regions: regions,
                  onConfirm: onRegionChanged,
                );
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.transparent),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      dropdownValue,
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 16),
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

