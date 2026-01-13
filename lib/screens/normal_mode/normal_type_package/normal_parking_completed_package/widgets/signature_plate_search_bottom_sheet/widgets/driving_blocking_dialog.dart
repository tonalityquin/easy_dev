import 'package:flutter/material.dart';

/// ✅ "주행 중" 완전 차단(Blocking) 다이얼로그
/// - barrierDismissible: false -> 바깥 터치로 닫히지 않음
/// - PopScope(canPop: false) -> 시스템 뒤로가기/제스처로 닫히지 않음
/// - 모달 barrier가 아래 UI 터치를 모두 차단함(다른 곳 눌러도 아무 동작 없음)
///
/// ✅ 추가 요구사항 반영
/// 1) "주행 취소" 버튼 추가
/// 2) canCancel=false이면 "주행 취소" 비활성화(선점자만 취소 가능)
Future<void> showDrivingBlockingDialog({
  required BuildContext context,
  required String message,
  required Future<void> Function() onComplete,
  required Future<void> Function() onCancel,
  required bool canCancel, // ✅ 선점자만 취소 가능
  String? cancelDisabledHint, // ✅ 취소 불가 시 안내문구(옵션)
  Future<void> Function(Object err, StackTrace st)? onError,
}) async {
  await showDialog<void>(
    context: context,
    useRootNavigator: true,
    barrierDismissible: false,
    barrierColor: Colors.black.withOpacity(0.55),
    builder: (_) => PopScope(
      canPop: false,
      child: _DrivingBlockingDialog(
        message: message,
        onComplete: onComplete,
        onCancel: onCancel,
        canCancel: canCancel,
        cancelDisabledHint: cancelDisabledHint,
        onError: onError,
      ),
    ),
  );
}

class _DrivingBlockingDialog extends StatefulWidget {
  const _DrivingBlockingDialog({
    required this.message,
    required this.onComplete,
    required this.onCancel,
    required this.canCancel,
    required this.cancelDisabledHint,
    required this.onError,
  });

  final String message;
  final Future<void> Function() onComplete;
  final Future<void> Function() onCancel;

  /// ✅ selectedBy == me 일 때만 true
  final bool canCancel;

  /// ✅ 취소 버튼 비활성화 사유 표시(옵션)
  final String? cancelDisabledHint;

  final Future<void> Function(Object err, StackTrace st)? onError;

  @override
  State<_DrivingBlockingDialog> createState() => _DrivingBlockingDialogState();
}

class _DrivingBlockingDialogState extends State<_DrivingBlockingDialog> {
  bool _busy = false;

  Future<void> _run(Future<void> Function() fn) async {
    if (_busy) return;
    setState(() => _busy = true);

    try {
      await fn();

      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
    } catch (e, st) {
      // ✅ 에러 시에도 '주행 중' 동안 하위 UI 조작은 불가(모달 barrier)
      //    무한 블로킹 방지를 위해 다이얼로그는 닫고 onError로 위임
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();
      }
      if (widget.onError != null) {
        await widget.onError!(e, st);
      }
    }
  }

  Future<void> _handleComplete() async {
    await _run(widget.onComplete);
  }

  Future<void> _handleCancel() async {
    // ✅ UI에서 비활성화하더라도, 로직 레벨에서도 한번 더 방어
    if (!widget.canCancel) return;
    await _run(widget.onCancel);
  }

  @override
  Widget build(BuildContext context) {
    final hint = (widget.canCancel)
        ? null
        : (widget.cancelDisabledHint ?? '선점자만 주행 취소가 가능합니다.');

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 30,
              height: 30,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                valueColor: AlwaysStoppedAnimation<Color>(
                  _busy ? Colors.grey : Colors.blueAccent,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              widget.message,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
            ),
            if (hint != null) ...[
              const SizedBox(height: 10),
              Text(
                hint,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Colors.red.shade700,
                ),
              ),
            ],
            const SizedBox(height: 14),

            // ✅ 2개 버튼: 주행 취소 / 주행 완료
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: (_busy || !widget.canCancel) ? null : _handleCancel,
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      side: const BorderSide(color: Colors.black12),
                      textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
                      foregroundColor: Colors.black87,
                    ),
                    child: Text(_busy ? '처리 중...' : '주행 취소'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton(
                    onPressed: _busy ? null : _handleComplete,
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
                    ),
                    child: Text(_busy ? '처리 중...' : '주행 완료'),
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
