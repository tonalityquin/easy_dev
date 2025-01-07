import 'package:flutter/material.dart';
import '../../utils/date_utils.dart'; // CustomDateUtils import
import '../../states/plate_state.dart'; // PlateRequest 가져오기


class PlateContainer extends StatefulWidget {
  final List<Map<String, dynamic>> data;
  final bool Function(Map<String, dynamic>) filterCondition;

  const PlateContainer({
    required this.data,
    required this.filterCondition,
    super.key,
  });

  @override
  _PlateContainerState createState() => _PlateContainerState();
}

class _PlateContainerState extends State<PlateContainer> {
  @override
  Widget build(BuildContext context) {
    final filteredData = widget.data.where(widget.filterCondition).toList();

    if (filteredData.isEmpty) {
      return const Center(
        child: Text(
          '데이터가 없습니다.',
          style: TextStyle(fontSize: 18, color: Colors.grey),
        ),
      );
    }

    return Column(
      children: filteredData.map((item) {
        // 로그용 데이터 출력
        debugPrint('로그 - 요청 시간: ${CustomDateUtils.formatTimestamp(item['request_time'])}');
        debugPrint('로그 - 경과 시간: ${CustomDateUtils.timeElapsed(item['request_time'])}');

        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 15, vertical: 8),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            boxShadow: [
              BoxShadow(
                color: Colors.grey.withAlpha((0.5 * 255).toInt()),
                spreadRadius: 2,
                blurRadius: 5,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Column(
            children: [
              // 상단 plate_number와 세로줄 (중앙 정렬)
              Row(
                children: [
                  Expanded(
                    flex: 7, // 좌측 7
                    child: Center(
                      child: Text(
                        '${item['plate_number']}',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                        textAlign: TextAlign.center, // 중앙 정렬
                      ),
                    ),
                  ),
                  Container(
                    width: 1, // 세로줄
                    height: 20,
                    color: Colors.grey,
                  ),
                  Expanded(
                    flex: 3, // 우측 3
                    child: Center(
                      child: Text(
                        item['type'] ?? '',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w400,
                        ),
                        textAlign: TextAlign.center, // 중앙 정렬
                      ),
                    ),
                  ),
                ],
              ),
              const Divider(thickness: 1, color: Colors.grey),

              // 중단 좌중우 (5:2:3 비율, 중앙 정렬)
              Row(
                children: [
                  Expanded(
                    flex: 5, // 좌측 5
                    child: Center(
                      child: Text(
                        '${item['location']}', // 위치를 중앙 정렬
                        style: const TextStyle(fontSize: 14),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                  Container(
                    width: 1, // 첫 번째 세로줄
                    height: 20,
                    color: Colors.grey,
                  ),
                  const Expanded(
                    flex: 2, // 중간 2 (공란)
                    child: Center(
                      child: Text(''), // 공란
                    ),
                  ),
                  Container(
                    width: 1, // 두 번째 세로줄
                    height: 20,
                    color: Colors.grey,
                  ),
                  Expanded(
                    flex: 3, // 우측 3
                    child: Center(
                      child: Text(
                        CustomDateUtils.formatTimeForUI(item['request_time']), // 요청 시간
                        style: const TextStyle(fontSize: 14, color: Colors.green),
                        textAlign: TextAlign.center, // 중앙 정렬
                      ),
                    ),
                  ),
                ],
              ),
              const Divider(thickness: 1, color: Colors.grey),

              // 하단 좌우 (7:3 비율, 중앙 정렬)
              Row(
                children: [
                  const Expanded(
                    flex: 7, // 좌측 7 (공란)
                    child: Center(
                      child: Text(''), // 공란
                    ),
                  ),
                  Container(
                    width: 1, // 세로줄
                    height: 20,
                    color: Colors.grey,
                  ),
                  Expanded(
                    flex: 3, // 우측 3
                    child: Center(
                      child: Text(
                        CustomDateUtils.timeElapsed(item['request_time']), // 경과 시간
                        style: const TextStyle(fontSize: 14, color: Colors.red),
                        textAlign: TextAlign.center, // 중앙 정렬
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}
