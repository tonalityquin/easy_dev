import 'package:easydev/enums/plate_type.dart';
import 'package:flutter/material.dart';
import '../../../../models/plate_model.dart';

class PlateSearchResults extends StatelessWidget {
  final List<PlateModel> results;
  final void Function(PlateModel) onSelect;

  const PlateSearchResults({
    super.key,
    required this.results,
    required this.onSelect,
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
            final formattedTime = _formatTime(plate.requestTime);

            final backgroundColor = plate.isSelected ? Colors.green.shade50 : Colors.white;
            final borderColor = plate.isSelected ? Colors.green : Colors.grey.shade300;

            final labelColor = _getLabelColor(plate.typeEnum);
            final labelBgColor = _getLabelBackground(plate.typeEnum);

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
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      /// 차량 번호 및 상태 (type)
                      Row(
                        children: [
                          const Icon(Icons.directions_car, size: 20, color: Colors.blueAccent),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '${plate.area} ${plate.plateFourDigit}',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: labelBgColor,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: labelColor),
                            ),
                            child: Text(
                              typeLabel,
                              style: TextStyle(
                                fontSize: 12,
                                color: labelColor,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      /// 요청 시간
                      Row(
                        children: [
                          const Icon(Icons.access_time, size: 16, color: Colors.grey),
                          const SizedBox(width: 6),
                          Text(
                            '요청 시간: $formattedTime',
                            style: const TextStyle(fontSize: 13),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),

                      /// 위치 강조
                      Row(
                        children: [
                          const Icon(Icons.location_on, size: 16, color: Colors.redAccent),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              plate.location,
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: Colors.black87,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),

                      /// 기타 정보
                      if (plate.isSelected ||
                          (plate.selectedBy?.isNotEmpty ?? false) ||
                          (plate.billingType?.isNotEmpty ?? false) ||
                          (plate.customStatus?.isNotEmpty ?? false))
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (plate.isSelected)
                                Text(
                                  '✅ 선택됨',
                                  style: const TextStyle(fontSize: 13, color: Colors.green),
                                ),
                              if (plate.selectedBy != null && plate.selectedBy!.isNotEmpty)
                                Row(
                                  children: [
                                    const Icon(Icons.person, size: 16, color: Colors.deepPurple),
                                    const SizedBox(width: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: Colors.deepPurple.shade50,
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(color: Colors.deepPurple),
                                      ),
                                      child: Text(
                                        '선택자: ${plate.selectedBy}',
                                        style: const TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                          color: Colors.deepPurple,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              if (plate.billingType != null && plate.billingType!.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: Text(
                                    '과금 유형: ${plate.billingType}',
                                    style: const TextStyle(fontSize: 13),
                                  ),
                                ),
                              if (plate.customStatus != null && plate.customStatus!.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: Text(
                                    '커스텀 상태: ${plate.customStatus}',
                                    style: const TextStyle(fontSize: 13),
                                  ),
                                ),
                            ],
                          ),
                        ),
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

  String _formatTime(DateTime time) {
    return '${time.year}-${time.month.toString().padLeft(2, '0')}-${time.day.toString().padLeft(2, '0')} '
        '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}:${time.second.toString().padLeft(2, '0')}';
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
}
