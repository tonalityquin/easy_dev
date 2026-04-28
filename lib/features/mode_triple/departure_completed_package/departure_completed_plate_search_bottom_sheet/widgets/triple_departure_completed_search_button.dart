import 'package:flutter/material.dart';

class TripleDepartureCompletedSearchButton extends StatelessWidget {
  final bool isValid;
  final bool isLoading;
  final VoidCallback? onPressed;

  const TripleDepartureCompletedSearchButton({
    super.key,
    required this.isValid,
    required this.isLoading,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final enabled = isValid && !isLoading;

    final ButtonStyle style = ButtonStyle(
      elevation: MaterialStateProperty.all<double>(0),
      padding: MaterialStateProperty.all<EdgeInsets>(
        const EdgeInsets.symmetric(vertical: 14),
      ),
      shape: MaterialStateProperty.all<RoundedRectangleBorder>(
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      backgroundColor: MaterialStateProperty.resolveWith<Color?>((states) {
        if (states.contains(MaterialState.disabled)) {
          return cs.surfaceContainerHigh;
        }
        return cs.primary;
      }),
      foregroundColor: MaterialStateProperty.resolveWith<Color?>((states) {
        if (states.contains(MaterialState.disabled)) {
          return cs.onSurfaceVariant;
        }
        return cs.onPrimary;
      }),
      overlayColor: MaterialStateProperty.resolveWith<Color?>((states) {
        if (states.contains(MaterialState.pressed)) {
          return cs.onPrimary.withOpacity(0.12);
        }
        return null;
      }),
    );

    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: enabled ? onPressed : null,
        style: style,
        child: isLoading
            ? SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation<Color>(cs.onPrimary),
          ),
        )
            : const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search, size: 18),
            SizedBox(width: 8),
            Text('검색', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
          ],
        ),
      ),
    );
  }
}
