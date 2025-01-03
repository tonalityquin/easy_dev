import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Class : 번호판 앞 두 자리(숫자) UI
class NumFieldFront2 extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback? onTap;
  final bool readOnly;
  final String labelText; // 라벨 텍스트
  final TextStyle? labelStyle; // 라벨 텍스트 스타일
  final String? hintText; // 힌트 텍스트
  final TextStyle? hintStyle; // 힌트 텍스트 스타일

  /// Constructor : 번호판 앞 두 자리(숫자)의 생성자
  const NumFieldFront2({
    super.key,
    required this.controller,
    this.onTap,
    this.readOnly = false,
    this.labelText = '2-digit', // 기본값 설정
    this.labelStyle,
    this.hintText = 'Enter', // 기본 힌트 텍스트
    this.hintStyle,
  });

  /// Method : 번호판 앞 두 자리(숫자) 입력 필드 구현
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 100,
      child: TextField(
        controller: controller,
        keyboardType: TextInputType.number,
        textAlign: TextAlign.center,
        inputFormatters: [
          LengthLimitingTextInputFormatter(2),
          FilteringTextInputFormatter.digitsOnly,
        ],
        readOnly: readOnly,
        decoration: InputDecoration(
          labelText: labelText,
          labelStyle: labelStyle ??
              const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.grey,
              ),
          hintText: hintText,
          hintStyle: hintStyle ?? const TextStyle(color: Colors.grey),
          contentPadding: const EdgeInsets.only(top: 20.0),
          enabledBorder: const UnderlineInputBorder(
            borderSide: BorderSide(color: Colors.black, width: 2.0),
          ),
          focusedBorder: const UnderlineInputBorder(
            borderSide: BorderSide(color: Colors.blue, width: 2.0),
          ),
        ),
        style: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.bold,
        ),
        onTap: () {
          print('2-digit field tapped, current content: ${controller.text}, clearing now.');
          if (onTap != null) {
            onTap!();
          }

          if (controller.text.isNotEmpty) {
            controller.clear();
            print('2-digit field tapped, cleared content.');
          }
        },
      ),
    );
  }
}
