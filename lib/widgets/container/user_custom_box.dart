import 'package:flutter/material.dart';

class UserCustomBoxStyles {
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

class UserCustomBox extends StatelessWidget {
  // **필드 정의**
  final String topLeftText;
  final String topRightText;
  final String midLeftText;
  final String midCenterText;
  final String midRightText;
  final VoidCallback onTap;
  final Color backgroundColor;

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
      flex: 2,
      child: Row(
        children: [
          Expanded(
            flex: leftFlex,
            child: Center(
              child: Text(leftText, style: leftTextStyle ?? UserCustomBoxStyles.subtitleStyle),
            ),
          ),
          if (centerText != null) ...[
            const VerticalDivider(width: 2.0, color: Colors.black),
            Expanded(
              flex: centerFlex,
              child: Center(
                child: Text(centerText, style: UserCustomBoxStyles.subtitleStyle),
              ),
            ),
          ],
          const VerticalDivider(width: 2.0, color: Colors.black),
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
      onTap: onTap,
      child: Container(
        width: double.infinity,
        height: 80,
        decoration: BoxDecoration(
          color: backgroundColor,
          border: Border.all(color: Colors.black, width: 2.0),
        ),
        child: Stack(
          children: [
            Column(
              children: [
                buildRow(
                  leftText: topLeftText,
                  rightText: topRightText,
                  leftFlex: 3,
                  centerFlex: 0,
                  rightFlex: 7,
                  leftTextStyle: UserCustomBoxStyles.titleStyle,
                ),
                const Divider(height: 1.0, color: Colors.black),
                buildRow(
                  leftText: midLeftText,
                  centerText: midCenterText,
                  rightText: midRightText,
                  leftFlex: 3,
                  centerFlex: 5,
                  rightFlex: 2,
                  leftTextStyle: UserCustomBoxStyles.titleStyle,
                  rightTextStyle: const TextStyle(color: Colors.black),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
