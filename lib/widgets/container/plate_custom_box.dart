import 'package:flutter/material.dart';

/// **PlateCustomBox**
/// - 번호판 정보를 정리된 UI로 표시하는 위젯
/// - 다양한 텍스트 정보(번호판, 주차 구역, 상태 등)를 표시하며,
///   탭 이벤트와 스타일 커스터마이징 기능 제공
class PlateCustomBoxStyles {
  /// 제목 텍스트 스타일 (굵고 큰 텍스트)
  static const TextStyle titleStyle = TextStyle(
    fontWeight: FontWeight.bold,
    fontSize: 16,
    color: Colors.black,
  );

  /// 부제목 텍스트 스타일 (보통 크기)
  static const TextStyle subtitleStyle = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w400,
    color: Colors.black,
  );

  /// 공통 Divider 스타일 (회색, 두께 1)
  static const Divider commonDivider = Divider(thickness: 1, color: Colors.grey);
}

class PlateCustomBox extends StatelessWidget {
  // **필드 정의**
  final String topLeftText; // 번호판 숫자
  final String topRightText; // 번호판 상태
  final String midLeftText; // 주차 구역
  final String midCenterText; // 중앙 텍스트
  final String midRightText; // 입차 요청 시간
  final String bottomLeftText; // 추가 정보
  final String bottomRightText; // 누적 시간
  final VoidCallback onTap; // 탭 이벤트 콜백
  final Color backgroundColor; // 배경색

  const PlateCustomBox({
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

  /// **행(Row) 생성**
  /// - 텍스트 간 구분선과 정렬을 포함하여 표시
  Widget buildRow({
    required String leftText,
    String? centerText,
    required String rightText,
    int leftFlex = 7,
    int centerFlex = 2,
    int rightFlex = 3,
    TextStyle? leftTextStyle,
    TextStyle? rightTextStyle,
  }) {
    return Expanded(
      flex: 2, // 기본 행 높이 비율
      child: Row(
        children: [
          // 왼쪽 텍스트
          Expanded(
            flex: leftFlex,
            child: Center(
              child: Text(leftText, style: leftTextStyle ?? PlateCustomBoxStyles.subtitleStyle),
            ),
          ),
          // 중앙 텍스트 (옵션)
          if (centerText != null) ...[
            const VerticalDivider(width: 2.0, color: Colors.black), // 구분선
            Expanded(
              flex: centerFlex,
              child: Center(
                child: Text(centerText, style: PlateCustomBoxStyles.subtitleStyle),
              ),
            ),
          ],
          // 오른쪽 텍스트
          const VerticalDivider(width: 2.0, color: Colors.black), // 구분선
          Expanded(
            flex: rightFlex,
            child: Center(
              child: Text(rightText, style: rightTextStyle ?? PlateCustomBoxStyles.subtitleStyle),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap, // 탭 이벤트 처리
      child: Container(
        width: double.infinity, // 부모 크기에 맞춤
        height: 120, // 고정된 높이
        decoration: BoxDecoration(
          color: backgroundColor, // 배경색
          border: Border.all(color: Colors.black, width: 2.0), // 테두리
        ),
        child: Stack(
          children: [
            Column(
              children: [
                // 첫 번째 행: 번호판 숫자와 상태
                buildRow(
                  leftText: topLeftText,
                  rightText: topRightText,
                  leftFlex: 7,
                  rightFlex: 3,
                  leftTextStyle: PlateCustomBoxStyles.titleStyle, // 번호판 bold 스타일
                ),
                const Divider(height: 1.0, color: Colors.black), // 구분선
                // 두 번째 행: 주차 구역, 중앙 텍스트, 입차 요청 시간
                buildRow(
                  leftText: midLeftText,
                  centerText: midCenterText,
                  rightText: midRightText,
                  leftFlex: 5,
                  centerFlex: 2,
                  rightFlex: 3,
                  leftTextStyle: PlateCustomBoxStyles.titleStyle,
                  rightTextStyle: const TextStyle(color: Colors.green), // 초록색 시간
                ),
                const Divider(height: 1.0, color: Colors.black), // 구분선
                // 세 번째 행: 추가 정보와 누적 시간
                buildRow(
                  leftText: bottomLeftText,
                  rightText: bottomRightText,
                  leftFlex: 7,
                  rightFlex: 3,
                  rightTextStyle: const TextStyle(color: Colors.red), // 붉은색 누적 시간
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
