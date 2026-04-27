import 'dart:async';
import 'package:flutter/material.dart';




Future<bool> showDashboardDurationBlockingDialog(
    BuildContext context, {
      required String message,
      Duration duration = const Duration(seconds: 5),
    }) async {
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (dialogCtx) {
      return _CancelableBlockingDialog(
        message: message,
        duration: duration,
      );
    },
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
      setState(() {
        _remainingSeconds--;
      });
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
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
      backgroundColor: cs.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(
          color: cs.outlineVariant.withOpacity(0.85),
        ),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          minWidth: 260,
          maxWidth: 360,
        ),
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
                      valueColor: AlwaysStoppedAnimation<Color>(cs.primary),
                    ),
                  ),
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: cs.primary.withOpacity(0.10),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.schedule,
                      color: cs.primary,
                    ),
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
                padding: const EdgeInsets.symmetric(
                  vertical: 6,
                  horizontal: 12,
                ),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: cs.outlineVariant.withOpacity(0.85),
                  ),
                ),
                child: Text(
                  '자동 진행까지 약 $_remainingSeconds초',
                  textAlign: TextAlign.center,
                  style: textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),

              const SizedBox(height: 16),

              
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  TextButton(
                    onPressed: _handleCancel,
                    style: TextButton.styleFrom(
                      foregroundColor: cs.onSurface,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 10,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(999),
                        side: BorderSide(
                          color: cs.outlineVariant.withOpacity(0.85),
                        ),
                      ),
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
