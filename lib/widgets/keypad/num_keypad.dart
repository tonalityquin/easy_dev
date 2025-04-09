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
          _buildRow(['1', '2', '3']),
          _buildRow(['4', '5', '6']),
          _buildRow(['7', '8', '9']),
          _buildRow(['지우기', '0', 'Reset']),
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
    final isReset = key == 'Reset';
    final isErase = key == '지우기';

    return Expanded(
      child: Padding(
        padding: const EdgeInsets.all(4.0),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => _handleKeyTap(key),
            borderRadius: BorderRadius.circular(8.0),
            splashColor: Colors.purple.withValues(alpha: 0.2),
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
                      .copyWith(
                    color: isReset
                        ? Colors.red
                        : isErase
                        ? Colors.orange
                        : Colors.black,
                  ),
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

    if (key == '지우기') {
      if (controller.text.isNotEmpty) {
        controller.text = controller.text.substring(0, controller.text.length - 1);
        debugPrint('지우기: ${controller.text}');
      }
    } else if (key == 'Reset') {
      debugPrint('Reset 호출');
      if (onReset != null) onReset!();
    } else if (controller.text.length < maxLength) {
      controller.text += key;
      debugPrint('숫자 추가 후 텍스트: ${controller.text}');
      if (controller.text.length == maxLength) {
        Future.microtask(() {
          debugPrint('onComplete 호출 - 입력 완료 상태: ${controller.text}');
          if (onComplete != null) {
            onComplete!();
          }
        });
      }
    }
  }
}
