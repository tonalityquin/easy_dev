import 'package:flutter/material.dart';

class UserCustomBoxStyles {
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

class UserCustomBox extends StatelessWidget {
  // 필드 정의
  final String topLeftText; // 번호판 숫자
  final String topRightText; // 번호판 상태
  final String midLeftText; // 주차 구역
  final String midCenterText; // 중앙 텍스트 (옵션)
  final String midRightText; // 입차 요청 시간
  final VoidCallback onTap; // 탭 이벤트 콜백
  final Color backgroundColor; // 배경색

  const UserCustomBox({
    super.key,
    required this.topLeftText,
    required this.topRightText,
    required this.midLeftText,
    required this.midCenterText,
    required this.midRightText,
    required this.onTap,
    this.backgroundColor = Colors.white,
  });

  Widget buildRow({
    required String leftText,
    String? centerText,
    required String rightText,
    required int leftFlex,
    required int centerFlex,
    required int rightFlex,
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
              child: Text(leftText, style: leftTextStyle ?? UserCustomBoxStyles.subtitleStyle),
            ),
          ),
          // 중앙 텍스트 (옵션)
          if (centerText != null) ...[
            const VerticalDivider(width: 2.0, color: Colors.black), // 구분선
            Expanded(
              flex: centerFlex,
              child: Center(
                child: Text(centerText, style: UserCustomBoxStyles.subtitleStyle),
              ),
            ),
          ],
          // 오른쪽 텍스트
          const VerticalDivider(width: 2.0, color: Colors.black), // 구분선
          Expanded(
            flex: rightFlex,
            child: Center(
              child: Text(rightText, style: rightTextStyle ?? UserCustomBoxStyles.subtitleStyle),
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
        height: 80, // 고정된 높이 (조정됨)
        decoration: BoxDecoration(
          color: backgroundColor, // 배경색
          border: Border.all(color: Colors.black, width: 2.0), // 테두리 스타일
        ),
        child: Stack(
          children: [
            Column(
              children: [
                // 첫 번째 행: 번호판 숫자와 상태 (3:7 비율)
                buildRow(
                  leftText: topLeftText,
                  rightText: topRightText,
                  leftFlex: 3,
                  centerFlex: 0,
                  // 중앙 텍스트 없음
                  rightFlex: 7,
                  leftTextStyle: UserCustomBoxStyles.titleStyle, // 번호판 숫자 bold
                ),
                const Divider(height: 1.0, color: Colors.black), // 구분선
                // 두 번째 행: 주차 구역, 중앙 텍스트, 입차 요청 시간 (3:5:2 비율)
                buildRow(
                  leftText: midLeftText,
                  centerText: midCenterText,
                  rightText: midRightText,
                  leftFlex: 3,
                  centerFlex: 5,
                  rightFlex: 2,
                  leftTextStyle: UserCustomBoxStyles.titleStyle,
                  // 주차 구역 bold
                  rightTextStyle: const TextStyle(color: Colors.black), // 입차 요청 시간 초록색
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
