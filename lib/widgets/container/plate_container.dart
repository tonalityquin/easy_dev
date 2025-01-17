import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/plate_request.dart';
import '../../utils/date_utils.dart';
import '../../states/user_state.dart';
import 'plate_custom_box.dart';

class PlateContainer extends StatelessWidget {
  final List<PlateRequest> data;
  final bool Function(PlateRequest)? filterCondition;
  final String? activePlate;
  final void Function(String plateNumber, String area) onPlateTap;
  final String? drivingPlate;

  const PlateContainer({
    required this.data,
    required this.onPlateTap,
    this.filterCondition,
    this.activePlate,
    this.drivingPlate,
    super.key,
  });

  List<PlateRequest> _filterData(List<PlateRequest> data) {
    final seenIds = <String>{};
    return data.where((request) {
      if (seenIds.contains(request.id)) {
        return false; // 중복 제거
      }
      seenIds.add(request.id);
      return filterCondition == null || filterCondition!(request); // 필터 조건 활용
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final userName = Provider.of<UserState>(context).name;
    final filteredData = _filterData(data);

    if (filteredData.isEmpty) {
      return Center(
        child: const Text(
          '현재 조건에 맞는 데이터가 없습니다.',
          style: TextStyle(fontSize: 18, color: Colors.grey),
        ),
      );
    }

    return Column(
      children: filteredData.map((item) {
        final backgroundColor = activePlate == '${item.plateNumber}_${item.area}' ? Colors.greenAccent : Colors.white;

        return Column(
          children: [
            PlateCustomBox(
              topLeftText: item.plateNumber,
              topRightText: "정산 영역",
              midLeftText: item.location,
              midCenterText: userName,
              midRightText: CustomDateUtils.formatTimeForUI(item.requestTime),
              bottomLeftText: "주의사항",
              bottomRightText: CustomDateUtils.timeElapsed(item.requestTime),
              backgroundColor: backgroundColor,
              onTap: () => onPlateTap(item.plateNumber, item.area),
            ),
            const SizedBox(height: 5),
          ],
        );
      }).toList(),
    );
  }
}
