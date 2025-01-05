import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:easydev/widgets/common/common_field.dart';


/// Class : 번호판 뒷 네 자리(숫자) UI
class NumFieldBack4 extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback? onTap;
  final bool readOnly;

  const NumFieldBack4({
    super.key,
    required this.controller,
    this.onTap,
    this.readOnly = false, // 기본값 설정
  });

  @override
  Widget build(BuildContext context) {
    return CommonField(
      controller: controller,
      maxLength: 4,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      labelText: '4-digit',
      hintText: 'Enter',
      readOnly: readOnly, // 전달
      onTap: onTap,
    );
  }
}
