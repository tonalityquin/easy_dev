import 'package:flutter/material.dart';

class NumKeypad extends StatelessWidget {
  final TextEditingController controller;
  final int maxLength;
  final VoidCallback? onComplete;
  final ValueChanged<bool>? onChangeDigitMode;
  final Color? backgroundColor;
  final TextStyle? textStyle;
  final bool enableDigitModeSwitch; // ✅ 앞/뒷자리용 여부 구분

  const NumKeypad({
    super.key,
    required this.controller,
    required this.maxLength,
    this.onComplete,
    this.onChangeDigitMode,
    this.backgroundColor,
    this.textStyle,
    this.enableDigitModeSwitch = true, // ✅ 기본값: 앞자리용
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: backgroundColor ?? const Color(0xFFFef7FF),
      padding: const EdgeInsets.symmetric(vertical: 10.0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildRow(['1', '2', '3']),
          _buildRow(['4', '5', '6']),
          _buildRow(['7', '8', '9']),
          enableDigitModeSwitch
              ? _buildRow(['두자리', '0', '세자리']) // 앞자리: 자리 수 선택 포함
              : _buildRow(['', '0', '']),          // 뒷자리: 숫자만
        ],
      ),
    );
  }

  Widget _buildRow(List<String> keys) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: keys.map((key) => _buildKeyButton(key)).toList(),
    );
  }

  Widget _buildKeyButton(String key) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.all(4.0),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: key.isNotEmpty ? () => _handleKeyTap(key) : null,
            borderRadius: BorderRadius.circular(8.0),
            splashColor: Colors.purple.withAlpha(50),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 16.0),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8.0),
                border: Border.all(color: Colors.grey),
              ),
              child: Center(
                child: Text(
                  key,
                  style: (textStyle ??
                      const TextStyle(fontSize: 20, fontWeight: FontWeight.bold))
                      .copyWith(color: Colors.black),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _handleKeyTap(String key) {
    debugPrint('키 입력: $key, 현재 텍스트: ${controller.text}');

    if (key == '두자리') {
      onChangeDigitMode?.call(false); // 두자리 모드
      return;
    } else if (key == '세자리') {
      onChangeDigitMode?.call(true); // 세자리 모드
      return;
    }

    if (controller.text.length < maxLength) {
      controller.text += key;
      debugPrint('숫자 추가 후 텍스트: ${controller.text}');
      if (controller.text.length == maxLength) {
        Future.microtask(() {
          debugPrint('onComplete 호출 - 입력 완료 상태: ${controller.text}');
          onComplete?.call();
        });
      }
    }
  }
}
