import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../repositories/plate_repository.dart';
import '../../utils/date_utils.dart'; // 날짜 관련 유틸리티
import '../../states/user_state.dart'; // 사용자 상태 관리
import 'plate_custom_box.dart'; // 커스텀 박스 위젯

/// PlateContainer
/// - 번호판 데이터를 기반으로 필터링 및 UI를 생성하는 위젯
/// - 선택된 번호판, 필터 조건, 클릭 이벤트 등을 처리
class PlateContainer extends StatelessWidget {
  final List<PlateModel> data; // 번호판 데이터 리스트
  final bool Function(PlateModel)? filterCondition; // 데이터 필터 조건
  final String? activePlate; // 현재 활성화된 번호판
  final void Function(String plateNumber, String area) onPlateTap; // 번호판 클릭 이벤트
  final String? drivingPlate; // 운행 중인 번호판

  const PlateContainer({
    required this.data,
    required this.onPlateTap,
    this.filterCondition,
    this.activePlate,
    this.drivingPlate,
    super.key,
  });

  /// 데이터 필터링 및 중복 제거
  /// - [data]: 원본 데이터 리스트
  /// - 필터 조건이 있을 경우 이를 적용
  List<PlateModel> _filterData(List<PlateModel> data) {
    final seenIds = <String>{};
    return data.where((request) {
      if (seenIds.contains(request.id)) {
        return false; // 중복 제거
      }
      seenIds.add(request.id);
      return filterCondition == null || filterCondition!(request); // 필터 조건 적용
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final userName = Provider.of<UserState>(context).name; // 사용자 이름 가져오기
    final filteredData = _filterData(data); // 데이터 필터링

    // 데이터가 없을 경우 표시할 UI
    if (filteredData.isEmpty) {
      return Center(
        child: const Text(
          '현재 조건에 맞는 데이터가 없습니다.',
          style: TextStyle(fontSize: 18, color: Colors.grey),
        ),
      );
    }

    // 필터링된 데이터를 기반으로 UI 생성
    return Column(
      children: filteredData.map((item) {
        final backgroundColor = activePlate == '${item.plateNumber}_${item.area}'
            ? Colors.greenAccent // 활성화된 번호판의 배경색
            : Colors.white; // 비활성화된 번호판의 배경색

        return Column(
          children: [
            PlateCustomBox(
              topLeftText: item.plateNumber,
              // 상단 왼쪽 텍스트
              topRightText: "정산 영역",
              // 상단 오른쪽 텍스트
              midLeftText: item.location,
              // 중간 왼쪽 텍스트
              midCenterText: userName,
              // 중간 중앙 텍스트
              midRightText: CustomDateUtils.formatTimeForUI(item.requestTime),
              // 중간 오른쪽 텍스트
              bottomLeftText: "주의사항",
              // 하단 왼쪽 텍스트
              bottomRightText: CustomDateUtils.timeElapsed(item.requestTime),
              // 하단 오른쪽 텍스트
              backgroundColor: backgroundColor,
              // 배경색
              onTap: () => onPlateTap(item.plateNumber, item.area), // 클릭 이벤트 처리
            ),
            const SizedBox(height: 5), // 간격 추가
          ],
        );
      }).toList(),
    );
  }
}
