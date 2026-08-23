import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../../design_system/common_ui/common_ui_components.dart';
import '../../../../../design_system/common_ui/common_ui_theme.dart';

class ModifyVehicleIdentityWorkspace extends StatelessWidget {
  const ModifyVehicleIdentityWorkspace({
    super.key,
    required this.frontController,
    required this.middleController,
    required this.backController,
    required this.region,
    required this.regions,
    required this.pending,
    required this.onRegionChanged,
    required this.onApplied,
    required this.onExit,
  });

  final TextEditingController frontController;
  final TextEditingController middleController;
  final TextEditingController backController;
  final String region;
  final List<String> regions;
  final bool pending;
  final ValueChanged<String> onRegionChanged;
  final VoidCallback onApplied;
  final VoidCallback onExit;

  bool get _valid {
    final front = frontController.text.trim();
    final middle = middleController.text.trim();
    final back = backController.text.trim();
    return RegExp(r'^\d{2,3}$').hasMatch(front) &&
        RegExp(r'^[가-힣]$').hasMatch(middle) &&
        RegExp(r'^\d{4}$').hasMatch(back) &&
        region.trim().isNotEmpty;
  }

  InputDecoration _decoration({
    required String label,
    required IconData icon,
  }) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon),
      counterText: '',
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final regionOptions = <String>[
      if (!regions.contains(region)) region,
      ...regions,
    ];

    return Container(
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: tokens.borderSubtle),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 12, 8),
            child: Row(
              children: [
                CommonIconButton(
                  icon: Icons.arrow_back_rounded,
                  tooltip: '차량 정보로',
                  size: 36,
                  iconSize: 18,
                  onPressed: onExit,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '차량 식별정보',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              color: tokens.textPrimary,
                              fontWeight: FontWeight.w900,
                            ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '지역과 차량번호를 확인하고 필요한 부분만 수정합니다.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: tokens.textSecondary,
                              height: 1.3,
                            ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: tokens.borderSubtle),
          Expanded(
            child: SingleChildScrollView(
              physics: const ClampingScrollPhysics(),
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.fromLTRB(14, 16, 14, 18),
              child: AnimatedBuilder(
                animation: Listenable.merge(
                  <Listenable>[frontController, middleController, backController],
                ),
                builder: (context, _) {
                  final valid = _valid;
                  final plateText =
                      '${frontController.text.trim()}-${middleController.text.trim()}-${backController.text.trim()}';
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        '지역',
                        style: Theme.of(context).textTheme.labelMedium?.copyWith(
                              color: tokens.textSecondary,
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                      const SizedBox(height: 6),
                      DropdownButtonFormField<String>(
                        value: region,
                        decoration: const InputDecoration(
                          labelText: '등록 지역',
                          prefixIcon: Icon(Icons.map_rounded),
                        ),
                        items: regionOptions
                            .map(
                              (value) => DropdownMenuItem<String>(
                                value: value,
                                child: Text(value),
                              ),
                            )
                            .toList(growable: false),
                        onChanged: (value) {
                          if (value != null) onRegionChanged(value);
                        },
                      ),
                      const SizedBox(height: 18),
                      Text(
                        '차량번호',
                        style: Theme.of(context).textTheme.labelMedium?.copyWith(
                              color: tokens.textSecondary,
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Expanded(
                            flex: 3,
                            child: TextField(
                              controller: frontController,
                              keyboardType: TextInputType.number,
                              maxLength: 3,
                              textAlign: TextAlign.center,
                              inputFormatters: <TextInputFormatter>[
                                FilteringTextInputFormatter.digitsOnly,
                              ],
                              decoration: _decoration(
                                label: '앞자리',
                                icon: Icons.numbers_rounded,
                              ),
                            ),
                          ),
                          const SizedBox(width: 7),
                          Expanded(
                            flex: 2,
                            child: TextField(
                              controller: middleController,
                              keyboardType: TextInputType.text,
                              maxLength: 1,
                              textAlign: TextAlign.center,
                              inputFormatters: <TextInputFormatter>[
                                FilteringTextInputFormatter.allow(
                                  RegExp(r'[ㄱ-ㅎㅏ-ㅣ가-힣]'),
                                ),
                              ],
                              decoration: _decoration(
                                label: '문자',
                                icon: Icons.text_fields_rounded,
                              ),
                            ),
                          ),
                          const SizedBox(width: 7),
                          Expanded(
                            flex: 4,
                            child: TextField(
                              controller: backController,
                              keyboardType: TextInputType.number,
                              maxLength: 4,
                              textAlign: TextAlign.center,
                              inputFormatters: <TextInputFormatter>[
                                FilteringTextInputFormatter.digitsOnly,
                              ],
                              decoration: _decoration(
                                label: '뒷자리',
                                icon: Icons.pin_rounded,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      AnimatedContainer(
                        duration: reduceMotion
                            ? Duration.zero
                            : const Duration(milliseconds: 180),
                        curve: Curves.easeOutCubic,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 11,
                        ),
                        decoration: BoxDecoration(
                          color: valid
                              ? tokens.surfaceSelected
                              : tokens.warningContainer,
                          borderRadius:
                              BorderRadius.circular(CommonUiShapes.control),
                          border: Border.all(
                            color: valid ? tokens.accent : tokens.warning,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              valid
                                  ? Icons.directions_car_filled_rounded
                                  : Icons.warning_amber_rounded,
                              color: valid ? tokens.accent : tokens.warning,
                              size: 20,
                            ),
                            const SizedBox(width: 9),
                            Expanded(
                              child: AnimatedSwitcher(
                                duration: reduceMotion
                                    ? Duration.zero
                                    : const Duration(milliseconds: 150),
                                child: Text(
                                  valid
                                      ? '$region · $plateText'
                                      : '앞자리 2~3자리, 한글 1자, 뒷자리 4자리를 확인해 주세요.',
                                  key: ValueKey<String>('$valid|$region|$plateText'),
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodyMedium
                                      ?.copyWith(
                                        color: valid
                                            ? tokens.textPrimary
                                            : tokens.onWarningContainer,
                                        fontWeight: FontWeight.w800,
                                      ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
            decoration: BoxDecoration(
              color: tokens.surfaceRaised,
              border: Border(top: BorderSide(color: tokens.borderSubtle)),
            ),
            child: AnimatedBuilder(
              animation: Listenable.merge(
                <Listenable>[frontController, middleController, backController],
              ),
              builder: (context, _) {
                return CommonButton(
                  label: pending ? '변경 적용' : '변경 없음',
                  icon: pending ? Icons.check_rounded : Icons.done_rounded,
                  expand: true,
                  haptic: CommonHaptic.selection,
                  onPressed: pending && _valid ? onApplied : null,
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
