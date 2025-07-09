import 'package:flutter/material.dart';

class SearchButton extends StatelessWidget {
  final bool isValid;
  final bool isLoading;
  final VoidCallback? onPressed;

  const SearchButton({
    super.key,
    required this.isValid,
    required this.isLoading,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final onPrimary = Theme.of(context).colorScheme.onPrimary;

    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: isValid && !isLoading ? onPressed : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: isValid ? primary : Colors.grey.shade300,
          foregroundColor: isValid ? onPrimary : Colors.black45,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          elevation: 0,
        ),
        child: isLoading
            ? const SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
          ),
        )
            : const Text(
          '검색',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
        ),
      ),
    );
  }
}
