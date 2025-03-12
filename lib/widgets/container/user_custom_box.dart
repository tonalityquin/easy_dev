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
  final bool isSelected; // ✅ 추가됨
  final Color backgroundColor;

  const UserCustomBox({
    super.key,
    required this.topLeftText,
    required this.topRightText,
    required this.midLeftText,
    required this.midCenterText,
    required this.midRightText,
    required this.onTap,
    required this.isSelected, // ✅ 필수 매개변수 추가
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
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300), // ✅ 애니메이션 지속 시간
        curve: Curves.easeInOut, // ✅ 부드러운 전환 애니메이션
        width: double.infinity,
        height: 80,
        alignment: Alignment.center, // ✅ 중앙 기준으로 정렬
        transformAlignment: Alignment.center, // ✅ 축소 시 중앙 기준 유지
        transform: isSelected
            ? (Matrix4.identity()..scale(0.95)) // ✅ 선택되면 95% 크기로 축소
            : Matrix4.identity(),
        decoration: BoxDecoration(
          color: isSelected ? Colors.blue.withOpacity(0.2) : backgroundColor, // ✅ 선택 시 배경색 변경
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
