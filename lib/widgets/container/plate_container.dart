import 'package:easydev/states/plate_state.dart';
import 'package:flutter/material.dart';
import 'custom_box.dart';
import '../../utils/date_utils.dart';

class PlateContainer extends StatefulWidget {
  final List<PlateRequest> data;
  final bool Function(PlateRequest)? filterCondition;

  const PlateContainer({
    required this.data,
    this.filterCondition,
    super.key,
  });

  @override
  State<PlateContainer> createState() => _PlateContainerState();
}

class _PlateContainerState extends State<PlateContainer> {
  String? _activePlate;

  List<PlateRequest> _filterData(List<PlateRequest> data) {
    return widget.filterCondition != null ? data.where(widget.filterCondition!).toList() : data;
  }

  @override
  Widget build(BuildContext context) {
    final filteredData = _filterData(widget.data);

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
        final isActive = _activePlate == item.plateNumber;

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
              backgroundColor: Colors.white,
              showOverlay: isActive,
              onTap: () {
                setState(() {
                  _activePlate = isActive ? null : item.plateNumber;
                });
              },
            ),
            const SizedBox(height: 5),
          ],
        );
      }).toList(),
    );
  }
}
