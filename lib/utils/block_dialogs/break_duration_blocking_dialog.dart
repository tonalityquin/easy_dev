import 'dart:async';
import 'package:flutter/material.dart';

Future<bool> showBreakDurationBlockingDialog(
    BuildContext context, {
      required String message,
      Duration duration = const Duration(seconds: 5),
    }) async {
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _BreakCancelableBlockingDialog(
      message: message,
      duration: duration,
    ),
  );
  return result ?? false;
}

@immutable
class _DialogTokens {
  const _DialogTokens({
    required this.dialogBg,
    required this.dialogBorder,
    required this.accent,
    required this.accentSoftBg,
    required this.text,
    required this.mutedText,
    required this.chipBg,
    required this.chipBorder,
    required this.buttonBorder,
  });

  final Color dialogBg;
  final Color dialogBorder;

  final Color accent;
  final Color accentSoftBg;

  final Color text;
  final Color mutedText;

  final Color chipBg;
  final Color chipBorder;

  final Color buttonBorder;

  factory _DialogTokens.of(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return _DialogTokens(
      dialogBg: cs.surface,
      dialogBorder: cs.outlineVariant.withOpacity(0.7),
      // ✅ break도 primary(=독립 프리셋 highlight)로 통일 → 독립 프리셋에서도 일관
      accent: cs.primary,
      accentSoftBg: cs.primary.withOpacity(0.10),
      text: cs.onSurface,
      mutedText: cs.onSurfaceVariant,
      chipBg: cs.primaryContainer.withOpacity(0.25),
      chipBorder: cs.outlineVariant.withOpacity(0.7),
      buttonBorder: cs.outlineVariant.withOpacity(0.7),
    );
  }
}

class _BreakCancelableBlockingDialog extends StatefulWidget {
  const _BreakCancelableBlockingDialog({
    required this.message,
    required this.duration,
  });

  final String message;
  final Duration duration;

  @override
  State<_BreakCancelableBlockingDialog> createState() => _BreakCancelableBlockingDialogState();
}

class _BreakCancelableBlockingDialogState extends State<_BreakCancelableBlockingDialog> {
  Timer? _timer;
  late int _remainingSeconds;

  @override
  void initState() {
    super.initState();
    _remainingSeconds = widget.duration.inSeconds;

    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      setState(() => _remainingSeconds--);

      if (_remainingSeconds <= 0) {
        t.cancel();
        if (mounted) {
          Navigator.of(context).pop<bool>(true);
        }
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _handleCancel() {
    _timer?.cancel();
    Navigator.of(context).pop<bool>(false);
  }

  @override
  Widget build(BuildContext context) {
    final t = _DialogTokens.of(context);
    final textTheme = Theme.of(context).textTheme;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
      backgroundColor: t.dialogBg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: t.dialogBorder),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 260, maxWidth: 360),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox(
                    width: 64,
                    height: 64,
                    child: CircularProgressIndicator(
                      strokeWidth: 3,
                      color: t.accent,
                    ),
                  ),
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: t.accentSoftBg,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.schedule, color: t.accent),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              Text(
                widget.message,
                textAlign: TextAlign.center,
                style: textTheme.bodyMedium?.copyWith(
                  color: t.text,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 12),

              Container(
                padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
                decoration: BoxDecoration(
                  color: t.chipBg,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: t.chipBorder),
                ),
                child: Text(
                  '자동 진행까지 약 $_remainingSeconds초',
                  textAlign: TextAlign.center,
                  style: textTheme.bodySmall?.copyWith(
                    color: t.mutedText,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),

              const SizedBox(height: 16),

              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  OutlinedButton(
                    onPressed: _handleCancel,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: t.accent,
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
                      side: BorderSide(color: t.buttonBorder),
                    ),
                    child: const Text('취소'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
