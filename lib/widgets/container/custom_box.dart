import 'package:flutter/material.dart';

class Custombox {
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

class CustomBox extends StatelessWidget {
  final String topLeftText; // 번호판 숫자
  final String topRightText;
  final String midLeftText; // 주차 구역
  final String midCenterText;
  final String midRightText; // 입차 요청 시간
  final String bottomLeftText;
  final String bottomRightText; // 누적 시간
  final VoidCallback onTap;
  final Color backgroundColor;

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

  Widget buildRow({
    required String leftText,
    String? centerText,
    required String rightText,
    int leftFlex = 7,
    int centerFlex = 2,
    int rightFlex = 3,
    TextStyle? leftTextStyle, // 왼쪽 텍스트 스타일 추가
    TextStyle? rightTextStyle, // 오른쪽 텍스트 스타일 추가
  }) {
    return Expanded(
      flex: 2,
      child: Row(
        children: [
          Expanded(
            flex: leftFlex,
            child: Center(
              child: Text(leftText, style: leftTextStyle ?? Custombox.subtitleStyle),
            ),
          ),
          if (centerText != null) ...[
            const VerticalDivider(width: 2.0, color: Colors.black),
            Expanded(
              flex: centerFlex,
              child: Center(
                child: Text(centerText, style: Custombox.subtitleStyle),
              ),
            ),
          ],
          const VerticalDivider(width: 2.0, color: Colors.black),
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
      onTap: onTap,
      child: Container(
        width: double.infinity,
        height: 120,
        decoration: BoxDecoration(
          color: backgroundColor,
          border: Border.all(color: Colors.black, width: 2.0),
        ),
        child: Stack(
          children: [
            Column(
              children: [
                // topleft, topright 비율 7:3
                buildRow(
                  leftText: topLeftText,
                  rightText: topRightText,
                  leftFlex: 7,
                  rightFlex: 3,
                  leftTextStyle: Custombox.titleStyle, // 번호판 숫자 bold
                ),
                const Divider(height: 1.0, color: Colors.black),
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
                const Divider(height: 1.0, color: Colors.black),
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
