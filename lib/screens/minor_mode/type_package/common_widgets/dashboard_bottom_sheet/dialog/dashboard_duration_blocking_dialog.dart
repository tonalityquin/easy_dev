import 'dart:async';
import 'package:flutter/material.dart';

/// 5초 동안 유지되는 취소 가능 blocking dialog
/// - [duration] 동안 카운트다운 후 자동으로 true 반환
/// - '취소' 버튼 누르면 false 반환
///
/// ✅ 리팩터링 포인트
/// - 하드코딩 팔레트 제거 → Theme(ColorScheme) 기반
/// - pop 중복 방지(타이머/버튼 동시 호출 방어)
/// - duration이 0 이하인 경우 즉시 true 반환(안전)
Future<bool> showDashboardDurationBlockingDialog(
    BuildContext context, {
      required String message,
      Duration duration = const Duration(seconds: 5),
    }) async {
  // ✅ duration 방어: 0초 이하이면 즉시 자동 진행
  if (duration.inSeconds <= 0) return true;

  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) {
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

  bool _popped = false; // ✅ pop 중복 방지

  @override
  void initState() {
    super.initState();

    _remainingSeconds = widget.duration.inSeconds;
    if (_remainingSeconds <= 0) {
      // (이론상 showDashboardDurationBlockingDialog에서 걸러지지만 안전망)
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _safePop(true);
      });
      return;
    }

    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;

      setState(() {
        _remainingSeconds -= 1;
      });

      if (_remainingSeconds <= 0) {
        t.cancel();
        _safePop(true); // 자동 진행
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _safePop(bool value) {
    if (_popped) return;
    _popped = true;

    _timer?.cancel();
    if (!mounted) return;

    Navigator.of(context).pop<bool>(value);
  }

  void _handleCancel() {
    _safePop(false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final textTheme = theme.textTheme;

    // ✅ 브랜드(Theme) 기반 토큰
    final Color accent = cs.primary;
    final Color border = cs.outlineVariant.withOpacity(0.6);

    final Color chipBg = cs.primaryContainer.withOpacity(0.35);
    final Color chipBorder = cs.primary.withOpacity(0.35);
    final Color chipFg = cs.onPrimaryContainer;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
      backgroundColor: cs.surface,
      surfaceTintColor: Colors.transparent, // ✅ M3 tint 방지
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
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // 상단 아이콘 + 로딩 링 (Theme primary)
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

              // 메시지
              Text(
                widget.message,
                textAlign: TextAlign.center,
                style: textTheme.bodyMedium?.copyWith(
                  color: cs.onSurface,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 12),

              // 남은 시간 표시(칩)
              Container(
                padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
                decoration: BoxDecoration(
                  color: chipBg,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: chipBorder),
                ),
                child: Text(
                  '자동 진행까지 약 $_remainingSeconds초',
                  textAlign: TextAlign.center,
                  style: textTheme.bodySmall?.copyWith(
                    color: chipFg,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // 취소 버튼
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
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
            ],
          ),
        ),
      ),
    );
  }
}
