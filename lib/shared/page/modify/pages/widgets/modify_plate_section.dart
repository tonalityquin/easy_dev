import 'package:flutter/material.dart';

class ModifyPlateSection extends StatelessWidget {
  final String? selectedManufacturerName;
  final String? selectedModelName;

  const ModifyPlateSection({
    super.key,
    required this.selectedManufacturerName,
    required this.selectedModelName,
  });

  Widget _buildReadOnlyInfoBox({
    required BuildContext context,
    required String label,
    required String? value,
  }) {
    final cs = Theme.of(context).colorScheme;
    final displayValue =
        value == null || value.trim().isEmpty ? '미등록' : value.trim();
    final isEmptyValue = displayValue == '미등록';

    return Container(
      height: 58,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        border: Border.all(color: cs.outlineVariant.withOpacity(0.85)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            displayValue,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w900,
              color: isEmptyValue ? cs.onSurfaceVariant : cs.onSurface,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '차량 정보 수정',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w900,
                color: cs.onSurface,
              ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _buildReadOnlyInfoBox(
                context: context,
                label: '제조사 명',
                value: selectedManufacturerName,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildReadOnlyInfoBox(
                context: context,
                label: '차종 명',
                value: selectedModelName,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
