import 'package:flutter/material.dart';

void showCustomSnackbar({
  required BuildContext context,
  required String message,
  required Color backgroundColor,
  required IconData icon,
  Color iconColor = Colors.white,
  Duration duration = const Duration(seconds: 2),
  VoidCallback? onTap,
}) {
  final overlay = Overlay.of(context, rootOverlay: true);

  late final OverlayEntry overlayEntry;

  overlayEntry = OverlayEntry(
    builder: (context) => Positioned(
      top: MediaQuery.of(context).padding.top + 20,
      left: 20,
      right: 20,
      child: GestureDetector(
        onTap: () {
          overlayEntry.remove();
          onTap?.call();
        },
        child: _SnackbarContainer(
          color: backgroundColor,
          icon: icon,
          iconColor: iconColor,
          message: message,
        ),
      ),
    ),
  );

  overlay.insert(overlayEntry);

  Future.delayed(duration, () {
    if (overlayEntry.mounted) overlayEntry.remove();
  });
}

void showSuccessSnackbar(BuildContext context, String message) {
  showCustomSnackbar(
    context: context,
    message: message,
    backgroundColor: Colors.green,
    icon: Icons.check_circle_outline,
  );
}

void showFailedSnackbar(BuildContext context, String message) {
  showCustomSnackbar(
    context: context,
    message: message,
    backgroundColor: Colors.redAccent,
    icon: Icons.error_outline,
  );
}

void showSelectedSnackbar(BuildContext context, String message) {
  showCustomSnackbar(
    context: context,
    message: message,
    backgroundColor: Colors.yellow[800]!,
    icon: Icons.warning_amber_rounded,
    iconColor: Colors.black,
  );
}

class _SnackbarContainer extends StatelessWidget {
  final Color color;
  final IconData icon;
  final String message;
  final Color iconColor;

  const _SnackbarContainer({
    required this.color,
    required this.icon,
    required this.message,
    this.iconColor = Colors.white,
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
            Icon(icon, color: iconColor),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
