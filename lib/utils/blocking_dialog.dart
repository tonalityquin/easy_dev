import 'package:flutter/material.dart';
import 'app_navigator.dart'; // ✅ 전역 navigatorKey 사용

Future<T> runWithBlockingDialog<T>({
  required BuildContext context,
  required Future<T> Function() task,
  String message = '처리 중입니다...',
}) async {
  // 1) 닫을 수 없는 모달 표시 (뒤로가기/바깥터치 모두 차단)
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) => PopScope( // WillPopScope 대체 위젯(Flutter 3.12+)
      canPop: false,          // ← 안드로이드 뒤로가기로도 닫히지 않음
      child: Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 24, height: 24,
                child: CircularProgressIndicator(strokeWidth: 2.8),
              ),
              const SizedBox(width: 16),
              Flexible(child: Text(message, style: const TextStyle(fontSize: 16))),
            ],
          ),
        ),
      ),
    ),
  );

  try {
    // 2) 실제 작업 수행 (⚠️ 여기선 라우팅하지 않음)
    final result = await task();
    return result;
  } finally {
    // 3) 모달 닫기 — 화면 전환으로 context가 unmounted여도 안전하게 닫힘
    final nav = AppNavigator.nav;
    if (nav?.canPop() ?? false) {
      nav!.pop();
    } else if (context.mounted) {
      final rnav = Navigator.of(context, rootNavigator: true);
      if (rnav.canPop()) rnav.pop();
    }
  }
}
