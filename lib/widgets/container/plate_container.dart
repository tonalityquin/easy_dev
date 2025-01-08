// Flutter 및 외부 파일에서 필요한 모듈/상태/유틸리티 임포트
import 'package:flutter/material.dart';
import '../../utils/date_utils.dart';
import '../../states/plate_state.dart';

/// 공통 스타일 클래스
/// - 제목과 부제목 텍스트 스타일 및 공통 Divider 정의
class CommonStyles {
  static const TextStyle titleStyle = TextStyle(
    fontWeight: FontWeight.bold,
    fontSize: 16,
    color: Colors.black,
  );

  static const TextStyle subtitleStyle = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w400,
    color: Colors.black,
  );

  static const Divider commonDivider = Divider(thickness: 1, color: Colors.grey);
}

/// PlateContainer 위젯
/// - 데이터를 필터링하고 각 항목을 CustomBox로 표시
class PlateContainer extends StatelessWidget {
  final List<PlateRequest> data; // 차량 번호판 데이터를 포함한 리스트
  final bool Function(PlateRequest)? filterCondition; // 데이터 필터 조건 (선택적)

  const PlateContainer({
    required this.data,
    this.filterCondition,
    super.key,
  });

  /// 데이터를 필터링하는 메서드
  /// - filterCondition이 있으면 조건에 맞는 데이터만 반환
  /// - 없으면 전체 데이터를 반환
  List<PlateRequest> _filterData(List<PlateRequest> data) {
    return filterCondition != null ? data.where(filterCondition!).toList() : data;
  }

  @override
  Widget build(BuildContext context) {
    final filteredData = _filterData(data); // 필터링된 데이터 목록

    // 데이터가 비어 있을 경우 화면에 "데이터가 없습니다" 메시지 표시
    if (filteredData.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              '데이터가 없습니다.', // 데이터가 없을 때 표시되는 메시지
              style: TextStyle(fontSize: 18, color: Colors.grey),
            ),
            ElevatedButton(
              onPressed: () => debugPrint('데이터 새로고침'), // 새로고침 로직 호출
              child: const Text('새로고침'),
            ),
          ],
        ),
      );
    }

    // 필터링된 데이터를 기반으로 CustomBox를 생성
    return Column(
      children: filteredData.map((item) {
        return Column(
          children: [
            // CustomBox 생성
            CustomBox(
              topLeftText: item.plateNumber,
              // 차량 번호판
              topRightText: "정산 영역",
              // 정산 정보
              midLeftText: item.location,
              // 주차 위치
              midCenterText: "담당자",
              // 담당자
              midRightText: CustomDateUtils.formatTimeForUI(item.requestTime),
              // 입차 요청 시간
              bottomLeftText: "주의사항",
              // 주의사항
              bottomRightText: CustomDateUtils.timeElapsed(item.requestTime),
              // 누적 시간
              onTap: () => debugPrint('${item.plateNumber} 탭됨'),
              // 탭 이벤트 처리
              backgroundColor: Colors.white, // 박스 배경색
            ),
            const SizedBox(
              height: 5, // CustomBox 아래 간격
            ),
          ],
        );
      }).toList(),
    );
  }
}

/// CustomBox 위젯
/// - 데이터를 표시하는 단일 박스
/// - 상단, 중단, 하단 3개의 Row로 구성
class CustomBox extends StatelessWidget {
  final String topLeftText; // 상단 좌측 텍스트 (차량 번호판)
  final String topRightText; // 상단 우측 텍스트 (정산 정보)
  final String midLeftText; // 중단 좌측 텍스트 (주차 위치)
  final String midCenterText; // 중단 중앙 텍스트 (담당자)
  final String midRightText; // 중단 우측 텍스트 (입차 요청 시간)
  final String bottomLeftText; // 하단 좌측 텍스트 (주의사항)
  final String bottomRightText; // 하단 우측 텍스트 (누적 시간)
  final VoidCallback onTap; // 전체 박스의 탭 이벤트
  final Color backgroundColor; // 박스 배경색

  const CustomBox({
    super.key,
    required this.topLeftText,
    required this.topRightText,
    required this.midLeftText,
    required this.midCenterText,
    required this.midRightText,
    required this.bottomLeftText,
    required this.bottomRightText,
    required this.onTap,
    this.backgroundColor = Colors.white,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap, // 탭 이벤트 처리
      child: Container(
        width: double.infinity, // 박스의 너비를 화면에 꽉 차도록 설정
        height: 100, // 박스 높이
        decoration: BoxDecoration(
          color: backgroundColor, // 박스 배경색
          border: Border.all(color: Colors.black, width: 2.0), // 박스 테두리
        ),
        child: Column(
          children: [
            // Top Row (7:3)
            Expanded(
              flex: 2,
              child: Row(
                children: [
                  Expanded(
                    flex: 7, // 상단 좌측 비율
                    child: Center(
                      child: Text(topLeftText, style: CommonStyles.titleStyle), // 차량 번호판
                    ),
                  ),
                  const VerticalDivider(width: 2.0, color: Colors.black), // 세로 구분선
                  Expanded(
                    flex: 3, // 상단 우측 비율
                    child: Center(
                      child: Text(topRightText, style: CommonStyles.subtitleStyle), // 정산 정보
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1.0, color: Colors.black), // 가로 구분선
            // Mid Row (5:2:3)
            Expanded(
              flex: 2,
              child: Row(
                children: [
                  Expanded(
                    flex: 5, // 중단 좌측 비율
                    child: Center(
                      child: Text(midLeftText, style: CommonStyles.subtitleStyle), // 주차 위치
                    ),
                  ),
                  const VerticalDivider(width: 2.0, color: Colors.black), // 세로 구분선
                  Expanded(
                    flex: 2, // 중단 중앙 비율
                    child: Center(
                      child: Text(midCenterText, style: CommonStyles.subtitleStyle), // 담당자
                    ),
                  ),
                  const VerticalDivider(width: 2.0, color: Colors.black), // 세로 구분선
                  Expanded(
                    flex: 3, // 중단 우측 비율
                    child: Center(
                      child: Text(
                        midRightText, // 입차 요청 시간
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w400,
                          color: Colors.green, // 초록색
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1.0, color: Colors.black), // 가로 구분선
            // Bottom Row (7:3)
            Expanded(
              flex: 2,
              child: Row(
                children: [
                  Expanded(
                    flex: 7, // 하단 좌측 비율
                    child: Center(
                      child: Text(bottomLeftText, style: CommonStyles.subtitleStyle), // 주의사항
                    ),
                  ),
                  const VerticalDivider(width: 2.0, color: Colors.black), // 세로 구분선
                  Expanded(
                    flex: 3, // 하단 우측 비율
                    child: Center(
                      child: Text(
                        bottomRightText, // 누적 시간
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w400,
                          color: Colors.red, // 붉은색
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
