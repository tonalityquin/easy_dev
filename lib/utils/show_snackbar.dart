import 'package:flutter/material.dart';

void showSnackbar(BuildContext context, String message) {
  final overlay = Overlay.of(context);

  final overlayEntry = OverlayEntry(
    builder: (context) => Positioned(
      top: MediaQuery.of(context).padding.top + 20, // 상태바 아래 20px
      left: 20,
      right: 20,
      child: Material(
        color: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.black87,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            message,
            style: const TextStyle(color: Colors.white, fontSize: 16),
            textAlign: TextAlign.center,
          ),
        ),
      ),
    ),
  );

  overlay.insert(overlayEntry);

  // 1초 후 자동 삭제
  Future.delayed(const Duration(seconds: 1), () {
    overlayEntry.remove();
  });
}
