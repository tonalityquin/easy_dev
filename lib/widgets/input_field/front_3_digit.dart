import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:easydev/widgets/common/common_field.dart';

/// Class : 번호판 앞 세 자리(숫자) UI
class NumFieldFront3 extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback? onTap;
  final bool readOnly;

  const NumFieldFront3({
    super.key,
    required this.controller,
    this.onTap,
    this.readOnly = false, // 기본값 설정
  });

  @override
  Widget build(BuildContext context) {
    return CommonField(
      controller: controller,
      maxLength: 3,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      labelText: '3-digit',
      hintText: 'Enter',
      readOnly: readOnly,
      // 전달
      onTap: onTap,
    );
  }
}
