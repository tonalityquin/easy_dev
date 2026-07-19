import 'package:flutter/material.dart';

import '../../../../../design_system/prompt_ui/prompt_ui_components.dart';
import '../../../../../design_system/prompt_ui/prompt_ui_theme.dart';
import '../../../application/monthly_plate_field.dart';
import '../../widgets/monthly_prompt_ui.dart';
import '../monthly_region_bottom_sheet.dart';

class MonthlyPlateSection extends StatelessWidget {
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

  @override
  Widget build(BuildContext context) {
    final tokens = PromptUiTheme.of(context);
    final textTheme = Theme.of(context).textTheme;

    return MonthlyPromptSection(
      title: '차량 식별',
      subtitle: '번호판 지역과 차량번호를 입력합니다.',
      icon: Icons.directions_car_filled_outlined,
      trailing: isEditMode
          ? const MonthlyPromptBadge(
              label: '잠김',
              icon: Icons.lock_outline_rounded,
              tone: MonthlyPromptMessageTone.warning,
            )
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(
                width: 116,
                child: PromptButton(
                  label: dropdownValue,
                  icon: Icons.place_outlined,
                  variant: PromptButtonVariant.secondary,
                  haptic: PromptHaptic.selection,
                  minHeight: 54,
                  onPressed: isEditMode
                      ? null
                      : () => monthlyRegionPickerBottomSheet(
                            context: context,
                            selectedRegion: dropdownValue,
                            regions: regions,
                            onConfirm: onRegionChanged,
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
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.info_outline_rounded,
                  size: 17,
                  color: tokens.iconSecondary,
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    '번호판을 바꾸려면 기존 정기권을 삭제한 뒤 새로 등록하세요.',
                    style: textTheme.bodySmall?.copyWith(
                      color: tokens.textSecondary,
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
