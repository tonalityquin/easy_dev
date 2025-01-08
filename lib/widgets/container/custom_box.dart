import 'package:flutter/material.dart';

class custombox {
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
  final String topLeftText;
  final String topRightText;
  final String midLeftText;
  final String midCenterText;
  final String midRightText; // 입차 요청 시간
  final String bottomLeftText;
  final String bottomRightText; // 누적 시간
  final VoidCallback onTap;
  final Color backgroundColor;
  final bool showOverlay;

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
    this.showOverlay = false,
  });

  Widget buildRow({
    required String leftText,
    String? centerText,
    required String rightText,
    int leftFlex = 7,
    int centerFlex = 2,
    int rightFlex = 3,
  }) {
    return Expanded(
      flex: 2,
      child: Row(
        children: [
          Expanded(
            flex: leftFlex,
            child: Center(
              child: Text(leftText, style: custombox.subtitleStyle),
            ),
          ),
          if (centerText != null) ...[
            const VerticalDivider(width: 2.0, color: Colors.black),
            Expanded(
              flex: centerFlex,
              child: Center(
                child: Text(centerText, style: custombox.subtitleStyle),
              ),
            ),
          ],
          const VerticalDivider(width: 2.0, color: Colors.black),
          Expanded(
            flex: rightFlex,
            child: Center(
              child: Text(rightText, style: custombox.subtitleStyle),
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
                buildRow(leftText: topLeftText, rightText: topRightText, leftFlex: 7, rightFlex: 3),
                const Divider(height: 1.0, color: Colors.black),
                buildRow(
                  leftText: midLeftText,
                  centerText: midCenterText,
                  rightText: midRightText,
                  leftFlex: 5,
                  // 중단의 경우 기존 비율 유지
                  centerFlex: 2,
                  rightFlex: 3,
                ),
                const Divider(height: 1.0, color: Colors.black),
                // bottomleft, bottomright 비율 7:3
                buildRow(leftText: bottomLeftText, rightText: bottomRightText, leftFlex: 7, rightFlex: 3),
              ],
            ),
            if (showOverlay)
              Align(
                alignment: Alignment.centerRight,
                child: Container(
                  width: MediaQuery.of(context).size.width * 0.285,
                  color: Colors.white,
                  child: const Center(
                    child: Icon(Icons.directions_car, size: 40, color: Colors.black),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
