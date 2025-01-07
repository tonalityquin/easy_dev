import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:easydev/widgets/common/common_field.dart';

class KorFieldMiddle1 extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback? onTap;
  final bool readOnly;

  const KorFieldMiddle1({
    super.key,
    required this.controller,
    this.onTap,
    this.readOnly = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CommonField(
          controller: controller,
          maxLength: 1,
          keyboardType: TextInputType.text,
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'^[ㄱ-ㅎㅏ-ㅣ가-힣]$')), // 한글만 허용
          ],
          labelText: '1-digit',
          hintText: 'Enter',
          readOnly: readOnly,
          onTap: onTap,
        ),
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: controller,
          builder: (context, value, child) {
            final input = value.text;
            if (input.isNotEmpty && !RegExp(r'^[ㄱ-ㅎㅏ-ㅣ가-힣]$').hasMatch(input)) {
              return const Padding(
                padding: EdgeInsets.only(top: 8.0),
                child: Text(
                  '한글만 입력 가능합니다.',
                  style: TextStyle(color: Colors.red, fontSize: 12),
                ),
              );
            }
            return const SizedBox.shrink();
          },
        ),
      ],
    );
  }
}
