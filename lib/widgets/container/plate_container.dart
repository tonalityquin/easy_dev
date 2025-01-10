import 'package:flutter/material.dart';
import 'custom_box.dart';
import '../../utils/date_utils.dart';
import '../../states/plate_state.dart';

class PlateContainer extends StatelessWidget {
  final List<PlateRequest> data;
  final bool Function(PlateRequest)? filterCondition;
  final String? activePlate; // 현재 활성 상태 Plate
  final void Function(String plateNumber) onPlateTap; // 눌림 동작 콜백
  final String? drivingPlate; // 현재 운전 중인 차량 Plate 추가

  const PlateContainer({
    required this.data,
    required this.onPlateTap, // 필수 콜백 추가
    this.filterCondition,
    this.activePlate,
    this.drivingPlate, // 운전 중 상태 전달
    super.key,
  });

  List<PlateRequest> _filterData(List<PlateRequest> data) {
    return filterCondition != null ? data.where(filterCondition!).toList() : data;
  }

  @override
  Widget build(BuildContext context) {
    final filteredData = _filterData(data);

    if (filteredData.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('데이터가 없습니다.', style: TextStyle(fontSize: 18, color: Colors.grey)),
            ElevatedButton(
              onPressed: () => debugPrint('데이터 새로고침'),
              child: const Text('새로고침'),
            ),
          ],
        ),
      );
    }

    return Column(
      children: filteredData.map((item) {
        // 배경색 설정 로직 수정
        final backgroundColor = activePlate == item.plateNumber
            ? Colors.greenAccent // 클릭 시 초록색
            : Colors.white; // 기본 상태: 하얀색

        return Column(
          children: [
            CustomBox(
              topLeftText: item.plateNumber,
              topRightText: "정산 영역",
              midLeftText: item.location,
              midCenterText: "담당자",
              midRightText: CustomDateUtils.formatTimeForUI(item.requestTime),
              bottomLeftText: "주의사항",
              bottomRightText: CustomDateUtils.timeElapsed(item.requestTime),
              backgroundColor: backgroundColor,
              // 수정된 배경색 설정
              onTap: () => onPlateTap(item.plateNumber), // 외부 콜백 호출
            ),
            const SizedBox(height: 5),
          ],
        );
      }).toList(),
    );
  }
}
