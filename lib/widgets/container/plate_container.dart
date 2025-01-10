import 'package:flutter/material.dart';
import 'package:provider/provider.dart'; // Provider 패키지 추가
import '../../utils/date_utils.dart'; // 날짜 관련 유틸리티
import '../../states/plate_state.dart'; // PlateRequest 관련 상태 관리
import '../../states/user_state.dart'; // 유저 상태 관리
import 'custom_box.dart'; // CustomBox 위젯

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

  /// 필터 조건에 따라 데이터를 필터링
  List<PlateRequest> _filterData(List<PlateRequest> data) {
    return filterCondition != null ? data.where(filterCondition!).toList() : data;
  }

  @override
  Widget build(BuildContext context) {
    // UserState에서 유저 이름 가져오기
    final userName = Provider.of<UserState>(context).userName ?? "담당자 없음";

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
        // 배경색 설정 로직
        final backgroundColor = activePlate == item.plateNumber
            ? Colors.greenAccent // 클릭 시 초록색
            : Colors.white; // 기본 상태: 하얀색

        return Column(
          children: [
            CustomBox(
              topLeftText: item.plateNumber, // 차량 번호
              topRightText: "정산 영역", // 오른쪽 상단 텍스트
              midLeftText: item.location, // 위치 정보
              midCenterText: userName, // "담당자"에 유저 이름 표시
              midRightText: CustomDateUtils.formatTimeForUI(item.requestTime), // 요청 시간
              bottomLeftText: "주의사항", // 하단 왼쪽 텍스트
              bottomRightText: CustomDateUtils.timeElapsed(item.requestTime), // 경과 시간
              backgroundColor: backgroundColor, // 배경색 설정
              onTap: () => onPlateTap(item.plateNumber), // Plate 클릭 동작
            ),
            const SizedBox(height: 5),
          ],
        );
      }).toList(),
    );
  }
}
