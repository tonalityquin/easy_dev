import 'package:flutter/material.dart';

class TripleModifyStatusCustomSection extends StatelessWidget {
  final String customStatus;
  final VoidCallback onDelete;

  const TripleModifyStatusCustomSection({
    super.key,
    required this.customStatus,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 24),
        Text(
          '자동 불러온 상태 메모',
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w900,
            color: cs.onSurface,
          ) ??
              TextStyle(
                fontWeight: FontWeight.w900,
                color: cs.onSurface,
              ),
        ),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: cs.outlineVariant.withOpacity(0.85)),
                ),
                child: SelectableText(
                  customStatus,
                  style: TextStyle(
                    color: cs.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                    height: 1.35,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              onPressed: onDelete,
              icon: Icon(Icons.clear, color: cs.error),
              tooltip: '자동 메모 지우기',
            ),
          ],
        ),
      ],
    );
  }
}
