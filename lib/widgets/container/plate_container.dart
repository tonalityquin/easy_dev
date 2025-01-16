import 'package:flutter/material.dart';
import 'package:provider/provider.dart'; // Provider 패키지 추가
import '../../utils/date_utils.dart'; // 날짜 관련 유틸리티
import '../../states/plate_state.dart'; // PlateRequest 관련 상태 관리
import '../../states/user_state.dart'; // 유저 상태 관리
import 'plate_custom_box.dart'; // CustomBox 위젯

/// **PlateContainer 클래스**
/// - 차량 번호판 관련 데이터를 표시하는 컨테이너
/// - 필터링된 데이터를 리스트 형태로 출력하며, 유저 상태와 연동
class PlateContainer extends StatelessWidget {
  final List<PlateRequest> data; // PlateRequest 데이터 리스트
  final bool Function(PlateRequest)? filterCondition; // 필터 조건 (선택적)
  final String? activePlate; // 현재 활성 상태 Plate 번호
  final void Function(String plateNumber, String area) onPlateTap; // Plate 클릭 콜백 함수
  final String? drivingPlate; // 현재 운전 중인 차량 Plate 번호

  /// **PlateContainer 생성자**
  /// - [data]: PlateRequest 데이터 리스트
  /// - [onPlateTap]: Plate 클릭 시 호출되는 콜백 함수
  /// - 선택적 매개변수로 필터 조건(filterCondition), 활성 Plate(activePlate), 운전 중 Plate(drivingPlate)를 설정
  const PlateContainer({
    required this.data,
    required this.onPlateTap,
    this.filterCondition,
    this.activePlate,
    this.drivingPlate,
    super.key,
  });

  /// **필터 조건에 따라 데이터를 필터링**
  /// - [data]: PlateRequest 데이터 리스트
  /// - 반환값: 필터링된 PlateRequest 리스트
  List<PlateRequest> _filterData(List<PlateRequest> data) {
    final seenIds = <String>{};
    return data.where((request) {
      if (seenIds.contains(request.id)) {
        return false; // 중복 데이터 제거
      }
      seenIds.add(request.id);
      return true;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    // UserState에서 유저 이름 가져오기
    final userName = Provider.of<UserState>(context).name; // null 체크 제거

    // 필터링된 데이터 가져오기
    final filteredData = _filterData(data);

    // 필터링 결과가 비어 있는 경우 처리
    if (filteredData.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              '데이터가 없습니다.',
              style: TextStyle(fontSize: 18, color: Colors.grey),
            ),
            ElevatedButton(
              onPressed: () => debugPrint('데이터 새로고침'),
              child: const Text('새로고침'),
            ),
          ],
        ),
      );
    }

    // 필터링된 데이터를 기반으로 UI 구성
    return Column(
      children: filteredData.map((item) {
        // **배경색 설정 로직**
        final backgroundColor = activePlate == '${item.plateNumber}_${item.area}'
            ? Colors.greenAccent // 활성화된 Plate: 초록색
            : Colors.white; // 기본 상태: 하얀색


        return Column(
          children: [
            // CustomBox 위젯으로 Plate 데이터 표시
            PlateCustomBox(
              topLeftText: item.plateNumber,
              // 차량 번호판
              topRightText: "정산 영역",
              // 상단 오른쪽 텍스트
              midLeftText: item.location,
              // 위치 정보
              midCenterText: userName,
              // 유저 이름
              midRightText: CustomDateUtils.formatTimeForUI(item.requestTime),
              // 요청 시간
              bottomLeftText: "주의사항",
              // 하단 왼쪽 텍스트
              bottomRightText: CustomDateUtils.timeElapsed(item.requestTime),
              // 경과 시간
              backgroundColor: backgroundColor,
              // 배경색 설정
              onTap: () => onPlateTap(item.plateNumber, item.area), // Plate 클릭 동작
            ),
            const SizedBox(height: 5), // 각 Plate 간 간격 추가
          ],
        );
      }).toList(),
    );
  }
}
