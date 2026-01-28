import 'package:flutter/material.dart';

class MinorModifyStatusCustomSection extends StatelessWidget {
  final String customStatus;
  final VoidCallback onDelete;

  const MinorModifyStatusCustomSection({
    super.key,
    required this.customStatus,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = customStatus.trim();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 24),
        Text(
          '자동 불러온 상태 메모',
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: cs.surfaceVariant.withOpacity(0.35),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: cs.outlineVariant.withOpacity(0.55)),
          ),
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: SelectableText(
                  text.isEmpty ? '-' : text,
                  style: TextStyle(
                    color: cs.onSurface.withOpacity(0.70),
                    fontWeight: FontWeight.w700,
                    height: 1.35,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                onPressed: onDelete,
                icon: const Icon(Icons.clear),
                color: Colors.redAccent,
                tooltip: '자동 메모 지우기',
              ),
            ],
          ),
        ),
      ],
    );
  }
}
