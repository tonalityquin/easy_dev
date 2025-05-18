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
  final bool isSelected;
  final Color? backgroundColor;

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
    required this.isSelected,
    this.backgroundColor,
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
    // ✅ bottomLeft 부분 텍스트 조합
    final combinedBottomLeftText = [
      bottomLeftLeftText,
      if (bottomLeftCenterText.isNotEmpty) bottomLeftCenterText
    ].join(' ');

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
        width: double.infinity,
        height: 120,
        alignment: Alignment.center,
        transformAlignment: Alignment.center,
        transform: isSelected ? (Matrix4.identity()..scale(0.95)) : Matrix4.identity(),
        decoration: BoxDecoration(
          color: backgroundColor ?? (isSelected ? Colors.blue.withOpacity(0.2) : Colors.white),
          border: Border.all(color: Colors.black, width: 2.0),
          borderRadius: BorderRadius.circular(10),
          boxShadow: [
            if (isSelected)
              BoxShadow(
                color: Colors.blue.withOpacity(0.3),
                blurRadius: 10,
                spreadRadius: 2,
              ),
          ],
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
                  leftText: combinedBottomLeftText, // ✅ 수정 적용
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
