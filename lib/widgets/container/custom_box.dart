import 'package:flutter/material.dart';

/// **Custombox 클래스**
/// - 공통 스타일 및 Divider를 제공하는 클래스
class Custombox {
  // 제목 텍스트 스타일 (굵고 큰 텍스트)
  static const TextStyle titleStyle = TextStyle(
    fontWeight: FontWeight.bold,
    fontSize: 16,
    color: Colors.black,
  );

  // 부제목 텍스트 스타일 (보통 크기의 텍스트)
  static const TextStyle subtitleStyle = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w400,
    color: Colors.black,
  );

  // 공통 Divider 스타일 (회색, 두께 1)
  static const Divider commonDivider = Divider(thickness: 1, color: Colors.grey);
}

/// **CustomBox 위젯**
/// - 주차 요청 또는 완료 정보를 표시하는 위젯
class CustomBox extends StatelessWidget {
  // 필드 정의
  final String topLeftText; // 번호판 숫자
  final String topRightText; // 번호판 상태
  final String midLeftText; // 주차 구역
  final String midCenterText; // 중앙 텍스트 (옵션)
  final String midRightText; // 입차 요청 시간
  final String bottomLeftText; // 추가 정보
  final String bottomRightText; // 누적 시간
  final VoidCallback onTap; // 탭 이벤트 콜백
  final Color backgroundColor; // 배경색

  /// **CustomBox 생성자**
  /// - [topLeftText]: 번호판 숫자
  /// - [topRightText]: 번호판 상태
  /// - [midLeftText]: 주차 구역
  /// - [midCenterText]: 중앙 텍스트
  /// - [midRightText]: 입차 요청 시간
  /// - [bottomLeftText]: 추가 정보
  /// - [bottomRightText]: 누적 시간
  /// - [onTap]: 탭 이벤트 콜백
  /// - [backgroundColor]: 배경색 (기본값: 흰색)
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

  /// **행(Row) 빌드 메서드**
  /// - [leftText]: 왼쪽 텍스트
  /// - [centerText]: 중앙 텍스트 (선택적)
  /// - [rightText]: 오른쪽 텍스트
  /// - [leftFlex]: 왼쪽 영역 비율 (기본값: 7)
  /// - [centerFlex]: 중앙 영역 비율 (기본값: 2)
  /// - [rightFlex]: 오른쪽 영역 비율 (기본값: 3)
  /// - [leftTextStyle]: 왼쪽 텍스트 스타일 (선택적)
  /// - [rightTextStyle]: 오른쪽 텍스트 스타일 (선택적)
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
              child: Text(leftText, style: leftTextStyle ?? Custombox.subtitleStyle),
            ),
          ),
          // 중앙 텍스트 (옵션)
          if (centerText != null) ...[
            const VerticalDivider(width: 2.0, color: Colors.black), // 구분선
            Expanded(
              flex: centerFlex,
              child: Center(
                child: Text(centerText, style: Custombox.subtitleStyle),
              ),
            ),
          ],
          // 오른쪽 텍스트
          const VerticalDivider(width: 2.0, color: Colors.black), // 구분선
          Expanded(
            flex: rightFlex,
            child: Center(
              child: Text(rightText, style: rightTextStyle ?? Custombox.subtitleStyle),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap, // 탭 이벤트
      child: Container(
        width: double.infinity, // 가로 길이를 부모에 맞춤
        height: 120, // 고정된 높이
        decoration: BoxDecoration(
          color: backgroundColor, // 배경색
          border: Border.all(color: Colors.black, width: 2.0), // 테두리 스타일
        ),
        child: Stack(
          children: [
            Column(
              children: [
                // 첫 번째 행: 번호판 숫자와 상태 (7:3 비율)
                buildRow(
                  leftText: topLeftText,
                  rightText: topRightText,
                  leftFlex: 7,
                  rightFlex: 3,
                  leftTextStyle: Custombox.titleStyle, // 번호판 숫자 bold
                ),
                const Divider(height: 1.0, color: Colors.black), // 구분선
                // 두 번째 행: 주차 구역과 입차 요청 시간
                buildRow(
                  leftText: midLeftText, // 주차 구역 bold
                  centerText: midCenterText,
                  rightText: midRightText,
                  leftFlex: 5,
                  centerFlex: 2,
                  rightFlex: 3,
                  leftTextStyle: Custombox.titleStyle, // 주차 구역 bold 스타일 적용
                  rightTextStyle: const TextStyle(color: Colors.green), // 입차 요청 시간 초록색
                ),
                const Divider(height: 1.0, color: Colors.black), // 구분선
                // 세 번째 행: 추가 정보와 누적 시간
                buildRow(
                  leftText: bottomLeftText,
                  rightText: bottomRightText,
                  leftFlex: 7,
                  rightFlex: 3,
                  rightTextStyle: const TextStyle(color: Colors.red), // 누적 시간 붉은색
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
