import 'package:flutter/material.dart';

/// **AdjustmentCustomBoxStyles**
/// - 사용자 정보를 표시하는 `AdjustmentCustomBox`의 스타일 설정
/// - 제목 스타일, 부제목 스타일, 공통 Divider 스타일 포함
class AdjustmentCustomBoxStyles {
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

class AdjustmentCustomBox extends StatelessWidget {
  // **필드 정의**
  final String leftText; // 왼쪽 텍스트
  final String centerTopText; // 중간 위 텍스트
  final String centerBottomText; // 중간 아래 텍스트
  final String rightTopText; // 오른쪽 위 텍스트
  final String rightBottomText; // 오른쪽 아래 텍스트
  final VoidCallback onTap; // 탭 이벤트 콜백
  final Color backgroundColor; // 배경색

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

  /// **행(Row) 생성**
  /// - 텍스트와 구분선을 포함하여 각 행 구성
  Widget buildRow({
    required String leftText,
    required String centerTopText,
    required String centerBottomText,
    required String rightText,
    required int leftFlex,
    required int centerTopFlex,
    required int centerBottomFlex,
    required int rightFlex,
    TextStyle? leftTextStyle,
    TextStyle? centerTextStyle,
    TextStyle? rightTextStyle,
  }) {
    return Expanded(
      flex: 1, // 행 높이 비율
      child: Row(
        children: [
          // 왼쪽 텍스트
          Expanded(
            flex: leftFlex,
            child: Center(
              child: Text(leftText, style: leftTextStyle ?? AdjustmentCustomBoxStyles.subtitleStyle),
            ),
          ),
          // 중앙 텍스트
          Expanded(
            flex: centerTopFlex,
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(centerTopText, style: centerTextStyle ?? AdjustmentCustomBoxStyles.subtitleStyle),
                  const SizedBox(height: 5),
                  Text(centerBottomText, style: centerTextStyle ?? AdjustmentCustomBoxStyles.subtitleStyle),
                ],
              ),
            ),
          ),
          // 오른쪽 텍스트
          Expanded(
            flex: rightFlex,
            child: Center(
              child: Text(rightText, style: rightTextStyle ?? AdjustmentCustomBoxStyles.subtitleStyle),
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
          color: backgroundColor, // 배경색 설정
          border: Border.all(color: Colors.black, width: 2.0), // 테두리 스타일
        ),
        child: Column(
          children: [
            // 첫 번째 행: 왼쪽 텍스트, 중앙 텍스트(상단), 오른쪽 텍스트
            buildRow(
              leftText: leftText,
              centerTopText: centerTopText,
              centerBottomText: centerBottomText,
              rightText: rightTopText,
              leftFlex: 3,
              centerTopFlex: 3,
              centerBottomFlex: 3,
              rightFlex: 4,
              leftTextStyle: AdjustmentCustomBoxStyles.titleStyle, // 왼쪽 텍스트 스타일
              centerTextStyle: AdjustmentCustomBoxStyles.subtitleStyle, // 중앙 텍스트 스타일
              rightTextStyle: AdjustmentCustomBoxStyles.subtitleStyle, // 오른쪽 텍스트 스타일
            ),
            const Divider(height: 1.0, color: Colors.black), // 구분선
            // 두 번째 행: 중앙 텍스트(하단), 오른쪽 텍스트
            buildRow(
              leftText: '',
              centerTopText: '',
              centerBottomText: centerBottomText,
              rightText: rightBottomText,
              leftFlex: 0,
              centerTopFlex: 6,
              centerBottomFlex: 6,
              rightFlex: 4,
              leftTextStyle: AdjustmentCustomBoxStyles.subtitleStyle,
              centerTextStyle: AdjustmentCustomBoxStyles.subtitleStyle,
              rightTextStyle: AdjustmentCustomBoxStyles.subtitleStyle,
            ),
          ],
        ),
      ),
    );
  }
}
