import 'package:flutter/material.dart';

class ModifyPlateSection extends StatelessWidget {
  final String? selectedManufacturerName;
  final String? selectedModelName;
  final VoidCallback onTapManufacturer;
  final VoidCallback onTapModel;

  const ModifyPlateSection({
    super.key,
    required this.selectedManufacturerName,
    required this.selectedModelName,
    required this.onTapManufacturer,
    required this.onTapModel,
  });

  Widget _buildSelectBox({
    required BuildContext context,
    required String label,
    required String value,
    required VoidCallback onTap,
  }) {
    final cs = Theme.of(context).colorScheme;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          height: 58,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: cs.surfaceContainerLow,
            border: Border.all(color: cs.outlineVariant.withOpacity(0.85)),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Expanded(
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
                      value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                        color: cs.onSurface,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Icon(Icons.expand_more, color: cs.onSurface),
            ],
          ),
        ),
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
              child: _buildSelectBox(
                context: context,
                label: '제조사 명',
                value: selectedManufacturerName ?? '선택',
                onTap: onTapManufacturer,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildSelectBox(
                context: context,
                label: '차종 명',
                value: selectedModelName ?? '선택',
                onTap: onTapModel,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
