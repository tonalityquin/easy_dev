import 'package:flutter/material.dart';

/// **UserCustomBoxStyles**
/// - 사용자 정보를 표시하는 `UserCustomBox`의 스타일 설정
/// - 제목 스타일, 부제목 스타일, 공통 Divider 스타일 포함
class UserCustomBoxStyles {
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

/// **UserCustomBox**
/// - 사용자 정보를 UI로 표시하는 위젯
/// - 여러 텍스트와 스타일 옵션 제공
/// - 탭 이벤트 및 배경색 설정 가능
class UserCustomBox extends StatelessWidget {
  // **필드 정의**
  final String topLeftText; // 상단 왼쪽 텍스트 (주요 정보)
  final String topRightText; // 상단 오른쪽 텍스트 (상태 정보)
  final String midLeftText; // 중간 왼쪽 텍스트
  final String midCenterText; // 중간 중앙 텍스트 (옵션)
  final String midRightText; // 중간 오른쪽 텍스트
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

  /// **행(Row) 생성**
  /// - 텍스트와 구분선을 포함하여 각 행 구성
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
      flex: 2, // 행 높이 비율
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
      onTap: onTap, // 탭 이벤트 처리
      child: Container(
        width: double.infinity, // 부모 크기에 맞춤
        height: 80, // 고정된 높이
        decoration: BoxDecoration(
          color: backgroundColor, // 배경색 설정
          border: Border.all(color: Colors.black, width: 2.0), // 테두리 스타일
        ),
        child: Stack(
          children: [
            Column(
              children: [
                // 첫 번째 행: 상단 왼쪽 텍스트와 오른쪽 텍스트
                buildRow(
                  leftText: topLeftText,
                  rightText: topRightText,
                  leftFlex: 3,
                  centerFlex: 0, // 중앙 텍스트 없음
                  rightFlex: 7,
                  leftTextStyle: UserCustomBoxStyles.titleStyle, // bold 스타일 적용
                ),
                const Divider(height: 1.0, color: Colors.black), // 구분선
                // 두 번째 행: 중간 왼쪽 텍스트, 중앙 텍스트, 오른쪽 텍스트
                buildRow(
                  leftText: midLeftText,
                  centerText: midCenterText,
                  rightText: midRightText,
                  leftFlex: 3,
                  centerFlex: 5,
                  rightFlex: 2,
                  leftTextStyle: UserCustomBoxStyles.titleStyle, // 중간 왼쪽 bold
                  rightTextStyle: const TextStyle(color: Colors.black), // 기본 텍스트 스타일
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
