import 'package:flutter/material.dart';

class PlateCustomBoxStyles {
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
  static const TextStyle miniTitleStyle = TextStyle(
    fontWeight: FontWeight.bold,
    fontSize: 12,
    color: Colors.black,
  );
  static const Divider commonDivider = Divider(thickness: 1, color: Colors.grey);
}

class PlateCustomBox extends StatelessWidget {
  final String topLeftText;
  final String topRightUpText;
  final String topRightDownText;
  final String midLeftText;
  final String midCenterText;
  final String midRightText;
  final String bottomLeftLeftText;
  final String bottomLeftCenterText;
  final String bottomRightText;
  final VoidCallback onTap;
  final Color backgroundColor;

  const PlateCustomBox({
    super.key,
    required this.topLeftText,
    required this.topRightUpText,
    required this.topRightDownText,
    required this.midLeftText,
    required this.midCenterText,
    required this.midRightText,
    required this.bottomLeftLeftText,
    required this.bottomLeftCenterText,
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
              child: Text(leftText, style: leftTextStyle ?? PlateCustomBoxStyles.subtitleStyle),
            ),
          ),
          if (centerText != null) ...[
            const VerticalDivider(width: 2.0, color: Colors.black),
            Expanded(
              flex: centerFlex,
              child: Center(
                child: Text(centerText, style: PlateCustomBoxStyles.subtitleStyle),
              ),
            ),
          ],
          const VerticalDivider(width: 2.0, color: Colors.black),
          Expanded(
            flex: rightFlex,
            child: Center(
              child: Text(
                rightText,
                style: rightTextStyle ?? PlateCustomBoxStyles.subtitleStyle,
                textAlign: TextAlign.center,
              ),
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
                buildRow(
                  leftText: topLeftText,
                  rightText: "$topRightUpText\n$topRightDownText",
                  leftFlex: 7,
                  rightFlex: 3,
                  leftTextStyle: PlateCustomBoxStyles.titleStyle,
                  rightTextStyle: PlateCustomBoxStyles.miniTitleStyle.copyWith(
                    fontSize: 12,
                    height: 1.5,
                  ),
                ),
                const Divider(height: 1.0, color: Colors.black),
                buildRow(
                  leftText: midLeftText,
                  centerText: midCenterText,
                  rightText: midRightText,
                  leftFlex: 5,
                  centerFlex: 2,
                  rightFlex: 3,
                  leftTextStyle: PlateCustomBoxStyles.titleStyle,
                  rightTextStyle: const TextStyle(color: Colors.green),
                ),
                const Divider(height: 1.0, color: Colors.black),
                buildRow(
                  leftText: "$bottomLeftLeftText, $bottomLeftCenterText",
                  rightText: bottomRightText,
                  leftFlex: 7,
                  rightFlex: 3,
                  leftTextStyle: PlateCustomBoxStyles.miniTitleStyle,
                  rightTextStyle: const TextStyle(color: Colors.red),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
