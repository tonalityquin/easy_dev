import 'package:flutter/material.dart';

/// ✅ 성공 Snackbar
void showSuccessSnackbar(BuildContext context, String message) {
  final overlay = Overlay.of(context, rootOverlay: true);

  final overlayEntry = OverlayEntry(
    builder: (context) => Positioned(
      top: MediaQuery.of(context).padding.top + 20,
      left: 20,
      right: 20,
      child: _SnackbarContainer(
        color: Colors.green,
        icon: Icons.check_circle_outline,
        message: message,
      ),
    ),
  );

  overlay.insert(overlayEntry);
  Future.delayed(const Duration(seconds: 2), () => overlayEntry.remove());
}

/// ✅ 실패 Snackbar
void showFailedSnackbar(BuildContext context, String message) {
  final overlay = Overlay.of(context, rootOverlay: true);

  final overlayEntry = OverlayEntry(
    builder: (context) => Positioned(
      top: MediaQuery.of(context).padding.top + 20,
      left: 20,
      right: 20,
      child: _SnackbarContainer(
        color: Colors.redAccent,
        icon: Icons.error_outline,
        message: message,
      ),
    ),
  );

  overlay.insert(overlayEntry);
  Future.delayed(const Duration(seconds: 2), () => overlayEntry.remove());
}

/// ✅ 선택 필요 Snackbar (노란색)
void showSelectedSnackbar(BuildContext context, String message) {
  final overlay = Overlay.of(context, rootOverlay: true);

  final overlayEntry = OverlayEntry(
    builder: (context) => Positioned(
      top: MediaQuery.of(context).padding.top + 20,
      left: 20,
      right: 20,
      child: _SnackbarContainer(
        color: Colors.yellow[800]!,
        icon: Icons.warning_amber_rounded,
        message: message,
      ),
    ),
  );

  overlay.insert(overlayEntry);
  Future.delayed(const Duration(seconds: 2), () => overlayEntry.remove());
}

/// ✅ 공통 Snackbar UI 컨테이너
class _SnackbarContainer extends StatelessWidget {
  final Color color;
  final IconData icon;
  final String message;

  const _SnackbarContainer({
    required this.color,
    required this.icon,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black26,
              blurRadius: 8,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Icon(icon, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(color: Colors.white, fontSize: 15),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
