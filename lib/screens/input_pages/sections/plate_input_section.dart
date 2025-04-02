// 파일 위치: input_pages/sections/plate_input_section.dart

import 'package:flutter/material.dart';
import '../../../widgets/input_field/common_plate_field.dart';
import '../../../widgets/dialog/region_picker_dialog.dart';

class PlateInputSection extends StatelessWidget {
  final String dropdownValue;
  final List<String> regions;
  final TextEditingController controller3digit;
  final TextEditingController controller1digit;
  final TextEditingController controller4digit;
  final TextEditingController activeController;
  final ValueChanged<TextEditingController> onKeypadStateChanged;
  final ValueChanged<String> onRegionChanged;

  const PlateInputSection({
    super.key,
    required this.dropdownValue,
    required this.regions,
    required this.controller3digit,
    required this.controller1digit,
    required this.controller4digit,
    required this.activeController,
    required this.onKeypadStateChanged,
    required this.onRegionChanged,
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
              onTap: () {
                showRegionPickerDialog(
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
                    Text(dropdownValue, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: CommonPlateInput(
                frontDigitCount: 3,
                hasMiddleChar: true,
                backDigitCount: 4,
                frontController: controller3digit,
                middleController: controller1digit,
                backController: controller4digit,
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
