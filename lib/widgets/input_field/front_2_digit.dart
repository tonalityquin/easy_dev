import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:easydev/widgets/common/common_field.dart';

/// Class : 번호판 앞 두 자리(숫자) UI
class NumFieldFront2 extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback? onTap;

  const NumFieldFront2({
    super.key,
    required this.controller,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return CommonField(
      controller: controller,
      maxLength: 2,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      labelText: '2-digit',
      hintText: 'Enter',
      onTap: onTap,
    );
  }
}
