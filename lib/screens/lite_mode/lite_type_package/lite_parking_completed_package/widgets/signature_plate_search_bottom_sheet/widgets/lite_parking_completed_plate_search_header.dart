import 'package:flutter/material.dart';

class LiteParkingCompletedPlateSearchHeader extends StatelessWidget {
  const LiteParkingCompletedPlateSearchHeader({super.key});

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;

    return Row(
      children: [
        Icon(Icons.directions_car, color: primary),
        const SizedBox(width: 8),
        const Text(
          '번호판 검색',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
