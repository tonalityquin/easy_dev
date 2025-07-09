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

            return Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(12),
              child: InkWell(
                onTap: () {
                  debugPrint('📌 탭된 차량: ${plate.plateNumber}');
                  onSelect(plate);
                },
                borderRadius: BorderRadius.circular(12),
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
                        /// 차량 번호 및 상태
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
                                color: Colors.blue.shade50,
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: Colors.blueAccent),
                              ),
                              child: Text(
                                typeLabel,
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Colors.blueAccent,
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

                        /// 위치
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
                                if (plate.billingType?.isNotEmpty ?? false)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: Text(
                                      '과금 유형: ${plate.billingType}',
                                      style: const TextStyle(fontSize: 13),
                                    ),
                                  ),
                                if (plate.customStatus?.isNotEmpty ?? false)
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
}
