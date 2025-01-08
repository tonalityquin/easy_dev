// Flutter 및 외부 파일에서 필요한 모듈/상태/유틸리티 임포트
import 'package:flutter/material.dart';
import '../../utils/date_utils.dart';
import '../../states/plate_state.dart';

/// PlateContainer 위젯
/// 데이터를 기반으로 차량 번호판 정보를 표시하며, 필터 조건을 적용할 수 있음.
/// - `data`: PlateRequest 객체 목록
/// - `filterCondition`: 특정 조건에 맞는 데이터를 필터링하는 함수
class PlateContainer extends StatelessWidget {
  // 차량 번호판 정보를 포함한 데이터 목록
  final List<PlateRequest> data;

  // 데이터를 필터링하는 조건 함수 (선택적)
  final bool Function(PlateRequest)? filterCondition;

  const PlateContainer({
    required this.data,
    this.filterCondition,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    // 필터 조건이 있는 경우 해당 조건에 맞는 데이터만 필터링
    final filteredData = (filterCondition != null) ? data.where(filterCondition!).toList() : data;

    // 필터링된 데이터가 비어 있으면 사용자에게 알림 표시
    if (filteredData.isEmpty) {
      return const Center(
        child: Text(
          '데이터가 없습니다.', // 빈 데이터를 처리하는 경우 메시지
          style: TextStyle(fontSize: 18, color: Colors.grey),
        ),
      );
    }

    // 데이터를 Column으로 렌더링
    return Column(
      // 각 데이터 항목에 대해 위젯 생성
      children: filteredData.map((item) {
        // 디버깅을 위한 로그 출력: 요청 시간과 경과 시간
        debugPrint('로그 - 요청 시간: ${CustomDateUtils.formatTimestamp(item.requestTime)}');
        debugPrint('로그 - 경과 시간: ${CustomDateUtils.timeElapsed(item.requestTime)}');

        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 15, vertical: 8), // 외부 여백 설정
          padding: const EdgeInsets.all(10), // 내부 여백 설정
          decoration: BoxDecoration(
            color: Colors.white, // 박스 배경색
            borderRadius: BorderRadius.circular(8), // 박스 테두리 모서리 둥글게 처리
            boxShadow: [
              BoxShadow(
                color: Colors.grey.withAlpha((0.5 * 255).toInt()), // 그림자 색상 및 투명도
                spreadRadius: 2, // 그림자 확산 정도
                blurRadius: 5, // 그림자 블러 정도
                offset: const Offset(0, 3), // 그림자 위치
              ),
            ],
          ),
          // 박스 내부 레이아웃 구성
          child: Column(
            children: [
              // 첫 번째 Row: 차량 번호판
              Row(
                children: [
                  Expanded(
                    flex: 7, // 차량 번호판에 대한 비율
                    child: Center(
                      child: Text(
                        item.plateNumber, // 차량 번호판 텍스트
                        style: const TextStyle(
                          fontWeight: FontWeight.bold, // 텍스트 굵게
                          fontSize: 16, // 텍스트 크기
                        ),
                        textAlign: TextAlign.center, // 중앙 정렬
                      ),
                    ),
                  ),
                  // 구분선
                  Container(
                    width: 1, // 구분선 너비
                    height: 20, // 구분선 높이
                    color: Colors.grey, // 구분선 색상
                  ),
                  Expanded(
                    flex: 3, // 타입 정보에 대한 비율
                    child: Center(
                      child: Text(
                        '', // 차량 타입 텍스트
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
              const Divider(thickness: 1, color: Colors.grey), // 구분선

              // 두 번째 Row: 위치 및 요청 시간 정보
              Row(
                children: [
                  Expanded(
                    flex: 5, // 위치 정보에 대한 비율
                    child: Center(
                      child: Text(
                        item.location, // 위치 텍스트
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
                      child: Text(''), // 비어 있는 공간
                    ),
                  ),
                  Container(
                    width: 1,
                    height: 20,
                    color: Colors.grey,
                  ),
                  Expanded(
                    flex: 3, // 요청 시간 정보에 대한 비율
                    child: Center(
                      child: Text(
                        CustomDateUtils.formatTimeForUI(item.requestTime), // 요청 시간 포맷
                        style: const TextStyle(fontSize: 14, color: Colors.green), // 요청 시간 텍스트 스타일
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                ],
              ),
              const Divider(thickness: 1, color: Colors.grey), // 구분선

              // 세 번째 Row: 경과 시간 정보
              Row(
                children: [
                  const Expanded(
                    flex: 7,
                    child: Center(
                      child: Text(''), // 비어 있는 공간
                    ),
                  ),
                  Container(
                    width: 1,
                    height: 20,
                    color: Colors.grey,
                  ),
                  Expanded(
                    flex: 3, // 경과 시간에 대한 비율
                    child: Center(
                      child: Text(
                        CustomDateUtils.timeElapsed(item.requestTime), // 경과 시간 텍스트
                        style: const TextStyle(fontSize: 14, color: Colors.red), // 경과 시간 텍스트 스타일
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
