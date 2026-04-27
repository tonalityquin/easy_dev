import 'package:flutter/material.dart';
import '../../../utils/init/app_navigator.dart';

Future<T> runWithBlockingDialog<T>({
  required BuildContext context,
  required Future<T> Function() task,
  String message = '처리 중입니다...',
}) async {
  
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) => PopScope( 
      canPop: false,          
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
    
    final result = await task();
    return result;
  } finally {
    
    final nav = AppNavigator.nav;
    if (nav?.canPop() ?? false) {
      nav!.pop();
    } else if (context.mounted) {
      final rnav = Navigator.of(context, rootNavigator: true);
      if (rnav.canPop()) rnav.pop();
    }
  }
}
