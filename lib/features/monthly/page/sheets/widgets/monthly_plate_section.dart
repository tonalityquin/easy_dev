import 'package:flutter/material.dart';

import '../../../application/monthly_plate_field.dart';
import '../monthly_region_bottom_sheet.dart';

const _plateInk = Color(0xFF101828);
const _plateMuted = Color(0xFF667085);
const _platePanel = Color(0xFFFFFFFF);
const _plateLine = Color(0xFFD8DEE8);
const _plateBlue = Color(0xFF2563EB);

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
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _platePanel,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _plateLine),
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
                child: const Icon(Icons.directions_car_filled_outlined, color: _plateBlue, size: 19),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '차량 식별',
                      style: TextStyle(color: _plateInk, fontWeight: FontWeight.w900, fontSize: 16),
                    ),
                    SizedBox(height: 2),
                    Text(
                      '지역과 번호판을 입력합니다.',
                      style: TextStyle(color: _plateMuted, fontWeight: FontWeight.w700, fontSize: 12),
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
                    border: Border.all(color: _plateLine),
                  ),
                  child: const Text(
                    '잠김',
                    style: TextStyle(color: _plateMuted, fontWeight: FontWeight.w900, fontSize: 12),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Semantics(
                button: true,
                enabled: !isEditMode,
                label: '번호판 지역 선택: $dropdownValue',
                child: InkWell(
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
                  borderRadius: BorderRadius.circular(14),
                  child: Container(
                    width: 112,
                    height: 54,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: isEditMode ? const Color(0xFFEFF2F7) : const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: _plateLine),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.place_outlined, color: _plateMuted, size: 18),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            dropdownValue,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: _plateInk, fontWeight: FontWeight.w900),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
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
          if (isEditMode) ...[
            const SizedBox(height: 10),
            const Text(
              '번호판 변경이 필요하면 기존 정기권을 삭제한 뒤 새로 등록하세요.',
              style: TextStyle(color: _plateMuted, fontWeight: FontWeight.w700, fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }
}
