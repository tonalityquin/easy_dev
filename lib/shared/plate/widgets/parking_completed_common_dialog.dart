import 'package:flutter/material.dart';

import '../../../design_system/common_ui/common_ui_components.dart';
import '../../../design_system/common_ui/common_ui_overlays.dart';
import '../../../design_system/common_ui/common_ui_theme.dart';

enum ParkingCompletedOverrideChoice {
  proceed,
  goBilling,
  cancel,
}

Future<ParkingCompletedOverrideChoice?> showParkingCompletedOverrideDialog({
  required BuildContext context,
  required String destinationLabel,
}) {
  return showCommonOverlayDialog<ParkingCompletedOverrideChoice>(
    context: context,
    barrierDismissible: true,
    builder: (_) => _ParkingCompletedOverrideDialog(
      destinationLabel: destinationLabel,
    ),
  );
}

class _ParkingCompletedOverrideDialog extends StatelessWidget {
  const _ParkingCompletedOverrideDialog({
    required this.destinationLabel,
  });

  final String destinationLabel;

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final textTheme = Theme.of(context).textTheme;
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;

    return CommonDialogFrame(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 430),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: tokens.warningContainer,
                    borderRadius:
                        BorderRadius.circular(CommonUiShapes.control),
                    border: Border.all(
                      color: tokens.warning.withOpacity(
                        tokens.isDark ? .58 : .36,
                      ),
                    ),
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    Icons.warning_amber_rounded,
                    color: tokens.warning,
                    size: 26,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '정산 없이 $destinationLabel',
                    style: textTheme.titleMedium?.copyWith(
                      color: tokens.textPrimary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            AnimatedContainer(
              duration: reduceMotion ? Duration.zero : CommonUiMotion.selection,
              curve: CommonUiMotion.standard,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: tokens.warningContainer,
                borderRadius: BorderRadius.circular(CommonUiShapes.control),
                border: Border.all(
                  color: tokens.warning.withOpacity(
                    tokens.isDark ? .56 : .34,
                  ),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '현재 차량은 정산이 완료되지 않았습니다.',
                    style: textTheme.bodyMedium?.copyWith(
                      color: tokens.onWarningContainer,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '정산을 먼저 진행하거나, 업무상 필요한 경우 정산 없이 상태를 변경할 수 있습니다.',
                    style: textTheme.bodySmall?.copyWith(
                      color: tokens.onWarningContainer,
                      height: 1.45,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            CommonButton(
              label: '정산 화면으로 이동',
              icon: Icons.receipt_long_rounded,
              onPressed: () => Navigator.of(context).pop(
                ParkingCompletedOverrideChoice.goBilling,
              ),
              variant: CommonButtonVariant.primary,
              expand: true,
              haptic: CommonHaptic.selection,
            ),
            const SizedBox(height: 10),
            CommonButton(
              label: '정산 없이 $destinationLabel',
              icon: Icons.warning_amber_rounded,
              onPressed: () => Navigator.of(context).pop(
                ParkingCompletedOverrideChoice.proceed,
              ),
              variant: CommonButtonVariant.destructive,
              expand: true,
              haptic: CommonHaptic.medium,
            ),
            const SizedBox(height: 8),
            CommonButton(
              label: '취소',
              onPressed: () => Navigator.of(context).pop(
                ParkingCompletedOverrideChoice.cancel,
              ),
              variant: CommonButtonVariant.tertiary,
              expand: true,
              haptic: CommonHaptic.selection,
            ),
          ],
        ),
      ),
    );
  }
}
