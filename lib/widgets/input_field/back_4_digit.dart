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
      width: 150,
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
              const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.grey,
              ),
          hintText: hintText,
          hintStyle: hintStyle ??
              const TextStyle(
                color: Colors.grey,
              ),
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
          print('4-digit field tapped, current content: ${controller.text}, clearing now.');
          if (onTap != null) {
            onTap!();
          }

          if (controller.text.isNotEmpty) {
            controller.clear();
            print('4-digit field tapped, cleared content.');
          }
        },
      ),
    );
  }
}
