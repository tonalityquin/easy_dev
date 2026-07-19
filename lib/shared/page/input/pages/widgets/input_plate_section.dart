import 'package:flutter/material.dart';

import '../../../../../design_system/prompt_ui/prompt_ui_components.dart';
import '../../../../../design_system/prompt_ui/prompt_ui_theme.dart';
import '../prompt_input_ui.dart';

class InputPlateSection extends StatelessWidget {
  final String? selectedManufacturerName;
  final String? selectedModelName;

  const InputPlateSection({
    super.key,
    required this.selectedManufacturerName,
    required this.selectedModelName,
  });

  Widget _infoBox({
    required BuildContext context,
    required String label,
    required String? value,
    required IconData icon,
  }) {
    final tokens = PromptUiTheme.of(context);
    final displayValue = value == null || value.trim().isEmpty
        ? '미등록'
        : value.trim();
    return Container(
      constraints: const BoxConstraints(minHeight: 72),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: tokens.surfaceOverlay,
        border: Border.all(color: tokens.borderSubtle),
        borderRadius: BorderRadius.circular(PromptUiShapes.control),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: tokens.iconSecondary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: tokens.textSecondary,
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  displayValue,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: displayValue == '미등록'
                            ? tokens.textSecondary
                            : tokens.textPrimary,
                        fontWeight: FontWeight.w800,
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PromptAnimatedReveal(
      child: PromptInputSectionCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const PromptInputSectionTitle(
              icon: Icons.directions_car_filled_rounded,
              title: '차량 정보 입력',
              subtitle: '번호판 인식 결과에 연결된 차량 정보를 확인합니다.',
            ),
            const SizedBox(height: 14),
            LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxWidth < 420;
                final items = [
                  Expanded(
                    child: _infoBox(
                      context: context,
                      label: '제조사 명',
                      value: selectedManufacturerName,
                      icon: Icons.factory_rounded,
                    ),
                  ),
                  const SizedBox(width: 10, height: 10),
                  Expanded(
                    child: _infoBox(
                      context: context,
                      label: '차종 명',
                      value: selectedModelName,
                      icon: Icons.car_repair_rounded,
                    ),
                  ),
                ];
                if (!compact) return Row(children: items);
                return Column(
                  children: [
                    _infoBox(
                      context: context,
                      label: '제조사 명',
                      value: selectedManufacturerName,
                      icon: Icons.factory_rounded,
                    ),
                    const SizedBox(height: 10),
                    _infoBox(
                      context: context,
                      label: '차종 명',
                      value: selectedModelName,
                      icon: Icons.car_repair_rounded,
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
