import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Class : 번호판 뒷 네 자리(숫자) UI
class NumFieldBack4 extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback? onTap;
  final bool readOnly;
  final String labelText;
  final TextStyle? labelStyle;
  final String? hintText;
  final TextStyle? hintStyle;

  /// Constructor : 번호판 뒷 네 자리(숫자)의 생성자
  const NumFieldBack4({
    super.key,
    required this.controller,
    this.onTap,
    this.readOnly = false,
    this.labelText = '4-digit',
    this.labelStyle,
    this.hintText = 'Enter',
    this.hintStyle,
  });

  /// Method : 번호판 뒷 네 자리(숫자) 입력 필드 구현
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: MediaQuery.of(context).size.width * 0.4, // 동적 너비 적용
      child: TextField(
        controller: controller,
        keyboardType: TextInputType.number,
        textAlign: TextAlign.center,
        inputFormatters: [
          LengthLimitingTextInputFormatter(4),
          FilteringTextInputFormatter.digitsOnly,
        ],
        readOnly: readOnly,
        decoration: InputDecoration(
          labelText: labelText,
          labelStyle: labelStyle ??
              Theme.of(context).textTheme.bodyLarge?.copyWith(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.grey,
              ),
          hintText: hintText,
          hintStyle: hintStyle ??
              Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Colors.grey,
              ),
          contentPadding: const EdgeInsets.only(top: 20.0),
          enabledBorder: const UnderlineInputBorder(
            borderSide: BorderSide(color: Colors.black, width: 2.0),
          ),
          focusedBorder: const UnderlineInputBorder(
            borderSide: BorderSide(color: Colors.blue, width: 2.0),
          ),
          errorText: _validateInput(controller.text), // 유효성 검사 메시지
        ),
        style: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.bold,
        ),
        onTap: () {
          if (onTap != null) {
            onTap!();
          }
          // 입력 필드의 텍스트 초기화
          if (controller.text.isNotEmpty) {
            controller.clear();
          }
        },
        onChanged: (value) {
          // 입력값 변경 시 유효성 검사 실행
          _validateInput(value);
        },
      ),
    );
  }

  /// Method: 입력값 유효성 검사
  String? _validateInput(String value) {
    if (value.isEmpty) {
      return 'This field is required.';
    }
    if (value.length < 4) {
      return 'Enter exactly 4 digits.';
    }
    return null; // 유효한 입력값일 경우
  }
}
