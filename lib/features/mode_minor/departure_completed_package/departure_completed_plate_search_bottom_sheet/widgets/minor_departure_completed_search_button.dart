import 'package:flutter/material.dart';

class MinorDepartureCompletedSearchButton extends StatelessWidget {
  final bool isValid;
  final bool isLoading;
  final VoidCallback? onPressed;

  const MinorDepartureCompletedSearchButton({
    super.key,
    required this.isValid,
    required this.isLoading,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final enabled = isValid && !isLoading;

    final Color bg = enabled ? cs.primary : cs.surfaceVariant;
    final Color fg = enabled ? cs.onPrimary : cs.onSurfaceVariant;

    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: enabled ? onPressed : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: bg,
          foregroundColor: fg,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          elevation: 0,
        ),
        child: isLoading
            ? SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation<Color>(enabled ? cs.onPrimary : cs.onSurfaceVariant),
          ),
        )
            : const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search, size: 18),
            SizedBox(width: 8),
            Text(
              '검색',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
            ),
          ],
        ),
      ),
    );
  }
}
