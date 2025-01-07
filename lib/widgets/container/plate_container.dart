import 'package:flutter/material.dart';
import '../../utils/date_utils.dart';
import '../../states/plate_state.dart';

class PlateContainer extends StatelessWidget {
  final List<PlateRequest> data;
  final bool Function(PlateRequest)? filterCondition;

  const PlateContainer({
    required this.data,
    this.filterCondition,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final filteredData = (filterCondition != null)
        ? data.where(filterCondition!).toList()
        : data;

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
        debugPrint('로그 - 요청 시간: ${CustomDateUtils.formatTimestamp(item.requestTime)}');
        debugPrint('로그 - 경과 시간: ${CustomDateUtils.timeElapsed(item.requestTime)}');

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
              Row(
                children: [
                  Expanded(
                    flex: 7,
                    child: Center(
                      child: Text(
                        item.plateNumber,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                  Container(
                    width: 1,
                    height: 20,
                    color: Colors.grey,
                  ),
                  Expanded(
                    flex: 3,
                    child: Center(
                      child: Text(
                        item.type,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w400,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                ],
              ),
              const Divider(thickness: 1, color: Colors.grey),
              Row(
                children: [
                  Expanded(
                    flex: 5,
                    child: Center(
                      child: Text(
                        item.location,
                        style: const TextStyle(fontSize: 14),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                  Container(
                    width: 1,
                    height: 20,
                    color: Colors.grey,
                  ),
                  const Expanded(
                    flex: 2,
                    child: Center(
                      child: Text(''),
                    ),
                  ),
                  Container(
                    width: 1,
                    height: 20,
                    color: Colors.grey,
                  ),
                  Expanded(
                    flex: 3,
                    child: Center(
                      child: Text(
                        CustomDateUtils.formatTimeForUI(item.requestTime),
                        style: const TextStyle(fontSize: 14, color: Colors.green),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                ],
              ),
              const Divider(thickness: 1, color: Colors.grey),
              Row(
                children: [
                  const Expanded(
                    flex: 7,
                    child: Center(
                      child: Text(''),
                    ),
                  ),
                  Container(
                    width: 1,
                    height: 20,
                    color: Colors.grey,
                  ),
                  Expanded(
                    flex: 3,
                    child: Center(
                      child: Text(
                        CustomDateUtils.timeElapsed(item.requestTime),
                        style: const TextStyle(fontSize: 14, color: Colors.red),
                        textAlign: TextAlign.center,
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
