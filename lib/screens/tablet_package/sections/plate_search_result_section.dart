import 'package:easydev/enums/plate_type.dart';
import 'package:flutter/material.dart';
import '../../../../../../models/plate_model.dart';

class PlateSearchResultSection extends StatelessWidget {
  final List<PlateModel> results;
  final void Function(PlateModel) onSelect;
  final VoidCallback? onRefresh;

  const PlateSearchResultSection({
    super.key,
    required this.results,
    required this.onSelect,
    this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '검색 결과',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: results.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            final plate = results[index];
            final typeLabel = plate.typeEnum?.label ?? plate.type;

            final backgroundColor = plate.isSelected ? Colors.green.shade50 : Colors.white;
            final borderColor = plate.isSelected ? Colors.green : Colors.grey.shade300;

            final labelColor = _getLabelColor(plate.typeEnum);
            final labelBgColor = _getLabelBackground(plate.typeEnum);

            final typeChip = _buildChip(
              text: typeLabel,
              fg: labelColor,
              bg: labelBgColor,
              borderColor: labelColor,
            );

            return GestureDetector(
              onTap: () => onSelect(plate),
              child: Card(
                elevation: 1,
                color: backgroundColor,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: borderColor),
                ),
                margin: EdgeInsets.zero,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      const Icon(Icons.directions_car, size: 20, color: Colors.blueAccent),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          plate.plateNumber,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      typeChip,
                    ],
                  ),
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  Color _getLabelColor(PlateType? type) {
    switch (type) {
      case PlateType.parkingRequests:
        return Colors.blueAccent;
      case PlateType.parkingCompleted:
        return Colors.green;
      case PlateType.departureRequests:
        return Colors.orange;
      case PlateType.departureCompleted:
        return Colors.grey;
      default:
        return Colors.blueAccent;
    }
  }

  Color _getLabelBackground(PlateType? type) {
    switch (type) {
      case PlateType.parkingRequests:
        return Colors.blue.shade50;
      case PlateType.parkingCompleted:
        return Colors.green.shade50;
      case PlateType.departureRequests:
        return Colors.orange.shade50;
      case PlateType.departureCompleted:
        return Colors.grey.shade200;
      default:
        return Colors.blue.shade50;
    }
  }

  // 공통 칩 위젯 헬퍼
  Widget _buildChip({
    required String text,
    required Color fg,
    required Color bg,
    required Color borderColor,
    IconData? icon,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: fg),
            const SizedBox(width: 4),
          ],
          Text(
            text,
            style: TextStyle(
              fontSize: 12,
              color: fg,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
