import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:easydev/widgets/common/common_field.dart';


/// Class : 번호판 중간 한 자리(한글) UI
class KorFieldMiddle1 extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback? onTap;
  final bool readOnly;

  const KorFieldMiddle1({
    super.key,
    required this.controller,
    this.onTap,
    this.readOnly = false, // 기본값 설정
  });

  @override
  Widget build(BuildContext context) {
    return CommonField(
      controller: controller,
      maxLength: 1,
      keyboardType: TextInputType.text,
      inputFormatters: [FilteringTextInputFormatter.singleLineFormatter],
      labelText: '1-digit',
      hintText: 'Enter',
      readOnly: readOnly, // 전달
      onTap: onTap,
    );
  }
}
