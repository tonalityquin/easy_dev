import 'package:flutter/material.dart';

class MinorParkingCompletedPlateSearchHeader extends StatelessWidget {
  const MinorParkingCompletedPlateSearchHeader({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Row(
      children: [
        Icon(Icons.directions_car, color: cs.primary),
        const SizedBox(width: 8),
        Text(
          '번호판 검색',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w900,
            color: cs.onSurface,
          ),
        ),
      ],
    );
  }
}
