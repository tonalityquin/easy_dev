import 'dart:async';

import 'package:flutter/material.dart';

import '../../../design_system/prompt_ui/prompt_ui_components.dart';
import '../../../design_system/prompt_ui/prompt_ui_theme.dart';

class ConfirmCancelFeeDialog extends StatefulWidget {
  const ConfirmCancelFeeDialog({super.key});

  @override
  State<ConfirmCancelFeeDialog> createState() => _ConfirmCancelFeeDialogState();
}

class _ConfirmCancelFeeDialogState extends State<ConfirmCancelFeeDialog> {
  Timer? _timer;
  int _remainingSeconds = 5;

  bool get _enabled => _remainingSeconds == 0;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      if (_remainingSeconds <= 1) {
        timer.cancel();
        setState(() => _remainingSeconds = 0);
      } else {
        setState(() => _remainingSeconds -= 1);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = PromptUiTheme.of(context);
    final textTheme = Theme.of(context).textTheme;
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;

    return PromptDialogFrame(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: tokens.dangerContainer,
                    borderRadius:
                        BorderRadius.circular(PromptUiShapes.control),
                    border: Border.all(
                      color: tokens.danger.withOpacity(
                        tokens.isDark ? 0.58 : 0.36,
                      ),
                    ),
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    Icons.receipt_long_rounded,
                    color: tokens.danger,
                    size: 25,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '정산 취소 확인',
                    style: textTheme.titleMedium?.copyWith(
                      color: tokens.textPrimary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: tokens.surfaceOverlay,
                borderRadius: BorderRadius.circular(PromptUiShapes.control),
                border: Border.all(color: tokens.borderSubtle),
              ),
              child: Text(
                '정산을 취소하시겠습니까?\n\n취소 후에는 요금이 변경될 수 있습니다.',
                textAlign: TextAlign.center,
                style: textTheme.bodyMedium?.copyWith(
                  color: tokens.textSecondary,
                  height: 1.45,
                ),
              ),
            ),
            const SizedBox(height: 14),
            AnimatedSwitcher(
              duration: reduceMotion ? Duration.zero : PromptUiMotion.selection,
              child: Container(
                key: ValueKey<int>(_remainingSeconds),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: _enabled
                      ? tokens.successContainer
                      : tokens.warningContainer,
                  borderRadius: BorderRadius.circular(PromptUiShapes.control),
                ),
                child: Text(
                  _enabled
                      ? '정산 취소 버튼이 활성화되었습니다.'
                      : '$_remainingSeconds초 뒤 정산 취소 버튼이 활성화됩니다.',
                  textAlign: TextAlign.center,
                  style: textTheme.labelMedium?.copyWith(
                    color: _enabled
                        ? tokens.onSuccessContainer
                        : tokens.onWarningContainer,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: PromptButton(
                    label: '아니오',
                    onPressed: () => Navigator.of(context).pop(false),
                    variant: PromptButtonVariant.tertiary,
                    expand: true,
                    haptic: PromptHaptic.selection,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: PromptButton(
                    label: '예, 취소합니다',
                    icon: Icons.cancel_outlined,
                    onPressed:
                        _enabled ? () => Navigator.of(context).pop(true) : null,
                    variant: PromptButtonVariant.destructive,
                    expand: true,
                    haptic: PromptHaptic.medium,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
