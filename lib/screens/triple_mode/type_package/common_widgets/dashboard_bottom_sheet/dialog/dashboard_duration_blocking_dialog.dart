import 'dart:async';
import 'package:flutter/material.dart';

/// 5초 동안 유지되는 취소 가능 blocking dialog
/// - [duration] 동안 카운트다운 후 자동으로 true 반환
/// - '취소' 버튼 누르면 false 반환
///
/// ✅ 리팩터링 포인트
/// - 하드코딩 팔레트 제거
/// - Theme(ColorScheme) 기반(primary/surface/outlineVariant 등)으로 브랜드 톤 통일
Future<bool> showDashboardDurationBlockingDialog(
    BuildContext context, {
      required String message,
      Duration duration = const Duration(seconds: 5),
    }) async {
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => _CancelableBlockingDialog(message: message, duration: duration),
  );

  return result ?? false;
}

class _CancelableBlockingDialog extends StatefulWidget {
  const _CancelableBlockingDialog({
    required this.message,
    required this.duration,
  });

  final String message;
  final Duration duration;

  @override
  State<_CancelableBlockingDialog> createState() => _CancelableBlockingDialogState();
}

class _CancelableBlockingDialogState extends State<_CancelableBlockingDialog> {
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
        if (mounted) Navigator.of(context).pop<bool>(true);
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
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final textTheme = theme.textTheme;

    final accent = cs.primary;

    final surface = cs.surface;
    final border = cs.outlineVariant.withOpacity(0.6);

    final chipBg = cs.primaryContainer.withOpacity(0.35);
    final chipBorder = cs.primary.withOpacity(0.35);
    final chipFg = cs.onPrimaryContainer;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
      backgroundColor: surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: border),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 260, maxWidth: 360),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
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
                      color: accent,
                    ),
                  ),
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: cs.primaryContainer.withOpacity(0.45),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.schedule, color: accent),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              Text(
                widget.message,
                textAlign: TextAlign.center,
                style: textTheme.bodyMedium?.copyWith(
                  color: cs.onSurface,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 12),

              Container(
                padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
                decoration: BoxDecoration(
                  color: chipBg,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: chipBorder),
                ),
                child: Text(
                  '자동 진행까지 약 $_remainingSeconds초',
                  style: textTheme.bodySmall?.copyWith(
                    color: chipFg,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),

              const SizedBox(height: 16),

              TextButton(
                onPressed: _handleCancel,
                style: TextButton.styleFrom(
                  foregroundColor: cs.onSurface,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(999),
                    side: BorderSide(color: cs.outlineVariant.withOpacity(0.9)),
                  ),
                  overlayColor: cs.outlineVariant.withOpacity(0.12),
                ),
                child: const Text('취소'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
