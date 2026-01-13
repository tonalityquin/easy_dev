import 'package:flutter/material.dart';

/// ✅ "주행 중" 완전 차단(Blocking) 다이얼로그
/// - barrierDismissible: false -> 바깥 터치로 닫히지 않음
/// - PopScope(canPop: false) -> 시스템 뒤로가기/제스처로 닫히지 않음
/// - 모달 barrier가 아래 UI 터치를 모두 차단함(다른 곳 눌러도 아무 동작 없음)
Future<void> showDrivingBlockingDialog({
  required BuildContext context,
  required String message,
  required Future<void> Function() onComplete,
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
        onError: onError,
      ),
    ),
  );
}

class _DrivingBlockingDialog extends StatefulWidget {
  const _DrivingBlockingDialog({
    required this.message,
    required this.onComplete,
    required this.onError,
  });

  final String message;
  final Future<void> Function() onComplete;
  final Future<void> Function(Object err, StackTrace st)? onError;

  @override
  State<_DrivingBlockingDialog> createState() => _DrivingBlockingDialogState();
}

class _DrivingBlockingDialogState extends State<_DrivingBlockingDialog> {
  bool _busy = false;

  Future<void> _handleComplete() async {
    if (_busy) return;
    setState(() => _busy = true);

    try {
      await widget.onComplete();

      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
    } catch (e, st) {
      // ✅ 에러 시에도 '주행 중' 동안 하위 UI 조작은 불가(모달 barrier)
      //    무한 블로킹을 피하기 위해 다이얼로그는 닫고 에러 핸들러로 위임
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();
      }
      if (widget.onError != null) {
        await widget.onError!(e, st);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
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
            const SizedBox(height: 14),

            // ✅ 유일한 액션: 주행 완료
            SizedBox(
              width: double.infinity,
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
      ),
    );
  }
}
