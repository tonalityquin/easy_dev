import 'package:flutter/material.dart';

/// **AdjustmentCustomBoxStyles**
/// - 사용자 정보를 표시하는 `AdjustmentCustomBox`의 스타일 설정
class AdjustmentCustomBoxStyles {
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
  static const VerticalDivider verticalDivider = VerticalDivider(
    width: 1,
    thickness: 1,
    color: Colors.grey,
  );
}

class AdjustmentCustomBox extends StatelessWidget {
  final String leftText;
  final String centerTopText;
  final String centerBottomText;
  final String rightTopText;
  final String rightBottomText;
  final VoidCallback onTap;
  final Color backgroundColor;

  const AdjustmentCustomBox({
    super.key,
    required this.leftText,
    required this.centerTopText,
    required this.centerBottomText,
    required this.rightTopText,
    required this.rightBottomText,
    required this.onTap,
    this.backgroundColor = Colors.white,
  });

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
        child: Row(
          children: [
            // Left Section
            Expanded(
              flex: 3,
              child: Center(
                child: Text(
                  leftText,
                  style: AdjustmentCustomBoxStyles.titleStyle,
                  textAlign: TextAlign.center,
                ),
              ),
            ),
            // Divider between left and right sections
            AdjustmentCustomBoxStyles.verticalDivider,
            // Right Section (Center Top + Bottom and Right Top + Bottom)
            Expanded(
              flex: 7,
              child: Column(
                children: [
                  // Top Row: Basic Standard (Left) and Basic Amount (Right)
                  Expanded(
                    child: Row(
                      children: [
                        Expanded(
                          flex: 6,
                          child: Center(
                            child: Text(
                              centerTopText, // 기본 기준
                              style: AdjustmentCustomBoxStyles.subtitleStyle,
                            ),
                          ),
                        ),
                        AdjustmentCustomBoxStyles.verticalDivider,
                        Expanded(
                          flex: 4,
                          child: Center(
                            child: Text(
                              centerBottomText, // 기본 금액
                              style: AdjustmentCustomBoxStyles.subtitleStyle,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  AdjustmentCustomBoxStyles.commonDivider, // Divider between top and bottom rows
                  // Bottom Row: Add Standard (Left) and Add Amount (Right)
                  Expanded(
                    child: Row(
                      children: [
                        Expanded(
                          flex: 6,
                          child: Center(
                            child: Text(
                              rightTopText, // 추가 기준
                              style: AdjustmentCustomBoxStyles.subtitleStyle,
                            ),
                          ),
                        ),
                        AdjustmentCustomBoxStyles.verticalDivider,
                        Expanded(
                          flex: 4,
                          child: Center(
                            child: Text(
                              rightBottomText, // 추가 금액
                              style: AdjustmentCustomBoxStyles.subtitleStyle,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
