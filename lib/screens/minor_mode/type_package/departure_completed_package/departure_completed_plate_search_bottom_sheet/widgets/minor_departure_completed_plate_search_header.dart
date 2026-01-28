import 'package:flutter/material.dart';

class MinorDepartureCompletedPlateSearchHeader extends StatelessWidget {
  const MinorDepartureCompletedPlateSearchHeader({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.directions_car, color: cs.primary),
            const SizedBox(width: 8),
            Text(
              '번호판 검색',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontSize: 18,
                fontWeight: FontWeight.w900,
                color: cs.onSurface,
              ) ??
                  TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: cs.onSurface,
                  ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          '차량 번호 4자리로 “입차 완료” 상태를 빠르게 찾습니다.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: cs.onSurfaceVariant,
          ) ??
              TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: cs.onSurfaceVariant,
              ),
        ),
      ],
    );
  }
}
