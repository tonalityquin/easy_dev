import 'dart:async';

import 'package:flutter/material.dart';

import '../../../design_system/prompt_ui/prompt_ui_components.dart';
import '../../../design_system/prompt_ui/prompt_ui_overlays.dart';
import '../../../design_system/prompt_ui/prompt_ui_theme.dart';

Future<bool> showBreakDurationBlockingDialog(
  BuildContext context, {
  required String message,
  Duration duration = const Duration(seconds: 5),
}) async {
  final result = await showPromptOverlayDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _BreakCancelableBlockingDialog(
      message: message,
      duration: duration,
    ),
  );
  return result ?? false;
}

class _BreakCancelableBlockingDialog extends StatefulWidget {
  const _BreakCancelableBlockingDialog({
    required this.message,
    required this.duration,
  });

  final String message;
  final Duration duration;

  @override
  State<_BreakCancelableBlockingDialog> createState() =>
      _BreakCancelableBlockingDialogState();
}

class _BreakCancelableBlockingDialogState
    extends State<_BreakCancelableBlockingDialog> {
  Timer? _timer;
  late int _remainingSeconds;

  @override
  void initState() {
    super.initState();
    _remainingSeconds = widget.duration.inSeconds;
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return;
      final next = _remainingSeconds - 1;
      if (next <= 0) {
        timer.cancel();
        Navigator.of(context).pop<bool>(true);
        return;
      }
      setState(() => _remainingSeconds = next);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _cancel() {
    _timer?.cancel();
    Navigator.of(context).pop<bool>(false);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = PromptUiTheme.of(context);
    final textTheme = Theme.of(context).textTheme;
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final totalSeconds = widget.duration.inSeconds <= 0
        ? 1
        : widget.duration.inSeconds;
    final progress = (_remainingSeconds / totalSeconds).clamp(0.0, 1.0);

    return PromptDialogFrame(
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 260, maxWidth: 380),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 72,
              height: 72,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  TweenAnimationBuilder<double>(
                    tween: Tween<double>(end: progress),
                    duration:
                        reduceMotion ? Duration.zero : PromptUiMotion.selection,
                    curve: PromptUiMotion.standard,
                    builder: (_, value, __) => CircularProgressIndicator(
                      value: value,
                      strokeWidth: 4,
                      color: tokens.warning,
                      backgroundColor: tokens.warningContainer,
                    ),
                  ),
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      color: tokens.warningContainer,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.schedule_rounded,
                      color: tokens.onWarningContainer,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            Text(
              widget.message,
              textAlign: TextAlign.center,
              style: textTheme.bodyMedium?.copyWith(
                color: tokens.textPrimary,
                height: 1.45,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 14),
            AnimatedContainer(
              duration: reduceMotion ? Duration.zero : PromptUiMotion.selection,
              curve: PromptUiMotion.standard,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: tokens.surfaceOverlay,
                borderRadius: BorderRadius.circular(PromptUiShapes.pill),
                border: Border.all(color: tokens.borderSubtle),
              ),
              child: AnimatedSwitcher(
                duration: reduceMotion ? Duration.zero : PromptUiMotion.instant,
                child: Text(
                  '자동 진행까지 약 $_remainingSeconds초',
                  key: ValueKey<int>(_remainingSeconds),
                  style: textTheme.labelMedium?.copyWith(
                    color: tokens.textSecondary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 18),
            PromptButton(
              label: '취소',
              icon: Icons.close_rounded,
              onPressed: _cancel,
              variant: PromptButtonVariant.tertiary,
              expand: true,
              haptic: PromptHaptic.selection,
            ),
          ],
        ),
      ),
    );
  }
}
