import 'package:flutter/material.dart';

class BillErrorMessageTextSection extends StatelessWidget {
  final String? message;

  const BillErrorMessageTextSection({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    if (message == null) return const SizedBox.shrink();

    final cs = Theme.of(context).colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: cs.errorContainer.withOpacity(.55),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: cs.error.withOpacity(.35)),
      ),
      child: Text(
        message!,
        style: TextStyle(
          color: cs.onErrorContainer,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
