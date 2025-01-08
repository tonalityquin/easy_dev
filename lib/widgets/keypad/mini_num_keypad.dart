import 'package:flutter/material.dart';

class MiniNumKeypad extends StatelessWidget {
  final TextEditingController controller; // 입력 컨트롤러
  final int maxLength; // 최대 입력 길이
  final VoidCallback? onComplete; // 입력 완료 콜백
  final VoidCallback? onReset; // 리셋 콜백
  final Color? backgroundColor; // 키패드 배경색
  final TextStyle? textStyle; // 버튼 텍스트 스타일
  final double buttonPadding; // 버튼 내부 여백
  final double buttonMargin; // 버튼 간 여백
  final double buttonFontSize; // 버튼 텍스트 크기
  final double containerHeight; // 키패드 전체 높이
  final double buttonBorderRadius; // 버튼 테두리 둥글기

  const MiniNumKeypad({
    super.key,
    required this.controller,
    required this.maxLength,
    this.onComplete,
    this.onReset,
    this.backgroundColor,
    this.textStyle,
    this.buttonPadding = 8.0, // 버튼 내부 여백 기본값
    this.buttonMargin = 3.0, // 버튼 간 여백 기본값
    this.buttonFontSize = 14.0, // 버튼 텍스트 크기 기본값
    this.containerHeight = 196.0, // 키패드 전체 높이 기본값
    this.buttonBorderRadius = 8.0, // 버튼 테두리 둥글기 기본값
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: backgroundColor ?? const Color(0xFFFef7FF), // 키패드 배경색
      height: containerHeight, // 키패드 전체 높이
      padding: const EdgeInsets.symmetric(vertical: 10.0), // 컨테이너 패딩
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          buildRow(['1', '2', '3']),
          buildRow(['4', '5', '6']),
          buildRow(['7', '8', '9']),
          buildRow(['지우기', '0', 'Reset']),
        ],
      ),
    );
  }

  Widget buildRow(List<String> keys) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: keys.map((key) => buildKeyButton(key)).toList(),
    );
  }

  Widget buildKeyButton(String key) {
    return Expanded(
      child: GestureDetector(
        onTap: () => _handleKeyTap(key),
        child: Semantics(
          label: '키패드 버튼: $key',
          child: Container(
            margin: EdgeInsets.all(buttonMargin), // 버튼 간 여백
            padding: EdgeInsets.symmetric(vertical: buttonPadding), // 버튼 내부 여백
            decoration: BoxDecoration(
              color: Colors.white, // 버튼 배경색
              borderRadius: BorderRadius.circular(buttonBorderRadius), // 버튼 모서리 둥글기
              border: Border.all(color: Colors.grey), // 버튼 테두리
            ),
            child: Center(
              child: Text(
                key,
                style: textStyle ??
                    TextStyle(
                      fontSize: buttonFontSize, // 버튼 텍스트 크기
                      fontWeight: FontWeight.bold,
                    ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _handleKeyTap(String key) {
    print('키 입력: $key, 현재 텍스트: ${controller.text}');
    if (key == '지우기') {
      if (controller.text.isNotEmpty) {
        controller.text = controller.text.substring(0, controller.text.length - 1);
        print('지우기: ${controller.text}');
      }
    } else if (key == 'Reset') {
      print('Reset 호출');
      if (onReset != null) onReset!();
    } else if (controller.text.length < maxLength) {
      controller.text += key;
      print('숫자 추가 후 텍스트: ${controller.text}');
      if (controller.text.length == maxLength) {
        Future.microtask(() {
          print('onComplete 호출 - 입력 완료 상태: ${controller.text}');
          if (onComplete != null) {
            onComplete!();
          }
        });
      }
    }
  }
}
