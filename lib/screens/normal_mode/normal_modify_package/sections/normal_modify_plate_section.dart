import 'package:flutter/material.dart';
import '../utils/normal_modify_plate_field.dart';
import '../widgets/normal_modify_region_picker_bottom_sheet.dart';

class NormalModifyPlateSection extends StatelessWidget {
  final String dropdownValue;
  final List<String> regions;
  final TextEditingController controllerFrontdigit;
  final TextEditingController controllerMidDigit;
  final TextEditingController controllerBackDigit;
  final bool isEditable;
  final ValueChanged<String> onRegionChanged;

  const NormalModifyPlateSection({
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '번호 입력',
          style: TextStyle(fontSize: 18.0, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            GestureDetector(
              onTap: () {
                normalModifyRegionPickerBottomSheet(
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
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Align(
                alignment: Alignment.center,
                child: NormalModifyPlateInput(
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
