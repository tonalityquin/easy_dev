import 'package:flutter/material.dart';

class TabletPlateSearchHeaderSection extends StatelessWidget {
  const TabletPlateSearchHeaderSection({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Row(
      children: [
        Icon(Icons.directions_car, color: cs.primary),
        const SizedBox(width: 8),
        Text(
          '번호판 검색',
          style: (text.titleMedium ?? const TextStyle()).copyWith(
            fontWeight: FontWeight.w700,
            color: cs.onSurface,
          ),
        ),
      ],
    );
  }
}
