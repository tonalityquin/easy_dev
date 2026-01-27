import 'dart:async';
import 'package:flutter/material.dart';

/// 5초 동안 유지되는 취소 가능 blocking dialog
/// - [duration] 동안 카운트다운 후 자동으로 true 반환
/// - '취소' 버튼 누르면 false 반환
///
/// ✅ 리팩터링 포인트
/// - 하드코딩 팔레트 제거(Deep Blue 상수 제거)
/// - Theme(ColorScheme) 기반으로 primary/surface/outlineVariant 등을 사용
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
          Navigator.of(context).pop<bool>(true); // 자동 진행
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
    Navigator.of(context).pop<bool>(false); // 취소
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final textTheme = theme.textTheme;

    // ✅ Deep Blue 하드코딩 대신 테마 primary 계열로 통일
    final accent = cs.primary;
    final accentOn = cs.onPrimary;

    // dialog surface / border
    final surface = cs.surface;
    final border = cs.outlineVariant.withOpacity(0.6);

    // chip(남은 시간) 톤
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
              // 상단 아이콘 + 로딩 링 (테마 primary 톤)
              Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox(
                    width: 64,
                    height: 64,
                    child: CircularProgressIndicator(
                      strokeWidth: 3,
                      // ✅ 기존 _Palette.base → cs.primary
                      color: accent,
                    ),
                  ),
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      // ✅ 기존 _Palette.base.withOpacity(0.08) → primaryContainer 기반
                      color: cs.primaryContainer.withOpacity(0.45),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.schedule,
                      // ✅ 기존 _Palette.base → cs.primary
                      color: accent,
                    ),
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

              // 남은 시간 표시 (필칩 스타일)
              Container(
                padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
                decoration: BoxDecoration(
                  // ✅ 기존 _Palette.light.withOpacity(...) → primaryContainer/primary 기반
                  color: chipBg,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: chipBorder),
                ),
                child: Text(
                  '자동 진행까지 약 $_remainingSeconds초',
                  textAlign: TextAlign.center,
                  style: textTheme.bodySmall?.copyWith(
                    color: chipFg,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // 액션 버튼(취소)
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
                      // ✅ pressed overlay도 테마 기반
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
