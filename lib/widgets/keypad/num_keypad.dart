import 'package:flutter/material.dart';

class NumKeypad extends StatelessWidget {
  final TextEditingController controller;
  final int maxLength;
  final VoidCallback? onComplete;
  final VoidCallback? onReset;
  final Color? backgroundColor;
  final TextStyle? textStyle;

  const NumKeypad({
    super.key,
    required this.controller,
    required this.maxLength,
    this.onComplete,
    this.onReset,
    this.backgroundColor,
    this.textStyle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: backgroundColor ?? const Color(0xFFFef7FF),
      padding: const EdgeInsets.symmetric(vertical: 10.0),
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
            margin: const EdgeInsets.all(4.0),
            padding: const EdgeInsets.symmetric(vertical: 16.0),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8.0),
              border: Border.all(color: Colors.grey),
            ),
            child: Center(
              child: Text(
                key,
                style: textStyle ?? const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
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
