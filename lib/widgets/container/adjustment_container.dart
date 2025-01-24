import 'package:flutter/material.dart';

/// **AdjustmentContainer**
/// - 정산 정보를 표시하는 컨테이너 위젯
/// -  등을 표시
/// - 선택 여부에 따라 스타일 변경 및 탭 이벤트 처리
class AdjustmentContainer extends StatelessWidget {
  final String countType; // 정산 유형
  final String basicStandard; // 기본 기준
  final String basicAmount; // 기본 금액
  final String addStandard; // 추가 기준
  final String addAmount; // 추가 금액
  final bool isSelected; // 선택 여부
  final VoidCallback onTap; // 탭 이벤트 콜백

  const AdjustmentContainer({
    Key? key,
    required this.countType,
    required this.basicStandard,
    required this.basicAmount,
    required this.addStandard,
    required this.addAmount,
    required this.isSelected,
    required this.onTap,
  }) : super(key: key);

  /// **_buildTextRow**
  /// - 레이블과 값을 한 줄에 표시하는 텍스트 위젯 생성
  /// - [label]: 레이블 텍스트
  /// - [value]: 값 텍스트
  Widget _buildTextRow(String label, String value) {
    return Text('$label: $value'); // 텍스트 형식으로 반환
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap, // 탭 이벤트 처리
      child: Container(
        padding: const EdgeInsets.all(16), // 내부 여백
        decoration: BoxDecoration(
          color: isSelected ? Colors.green : Colors.white, // 선택 여부에 따른 배경색
          border: Border.all(color: Colors.grey), // 테두리 색상 및 스타일
          borderRadius: BorderRadius.circular(8), // 둥근 모서리 처리
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start, // 왼쪽 정렬
          children: [
            _buildTextRow('CountType', countType), // 정산 유형 표시
            _buildTextRow('BasicStandard', basicStandard), // 기본 기준 표시
            _buildTextRow('BasicAmount', basicAmount), // 기본 금액 표시
            _buildTextRow('AddStandard', addStandard), // 추가 기준 표시
            _buildTextRow('AddAmount', addAmount), // 추가 금액 표시
          ],
        ),
      ),
    );
  }
}
