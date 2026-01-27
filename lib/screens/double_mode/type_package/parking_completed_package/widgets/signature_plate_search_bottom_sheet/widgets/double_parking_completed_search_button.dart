import 'package:flutter/material.dart';

class DoubleParkingCompletedSearchButton extends StatelessWidget {
  final bool isValid;
  final bool isLoading;
  final VoidCallback? onPressed;

  const DoubleParkingCompletedSearchButton({
    super.key,
    required this.isValid,
    required this.isLoading,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final enabled = isValid && !isLoading;

    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: enabled ? onPressed : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: enabled ? cs.primary : cs.surfaceContainerLow,
          foregroundColor: enabled ? cs.onPrimary : cs.onSurfaceVariant,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          elevation: 0,
          side: enabled
              ? BorderSide(color: cs.primary.withOpacity(0.25))
              : BorderSide(color: cs.outlineVariant.withOpacity(0.85)),
        ).copyWith(
          overlayColor: MaterialStateProperty.resolveWith<Color?>(
                (states) => states.contains(MaterialState.pressed)
                ? (enabled ? cs.onPrimary.withOpacity(0.10) : cs.outlineVariant.withOpacity(0.12))
                : null,
          ),
        ),
        child: isLoading
            ? SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation<Color>(
              enabled ? cs.onPrimary : cs.onSurfaceVariant,
            ),
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
