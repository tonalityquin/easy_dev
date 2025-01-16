import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// **CommonPlateField 위젯**
/// - 차량 번호판 입력과 같은 다양한 입력 필드로 재사용 가능
class CommonPlateField extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback? onTap;
  final ValueChanged<String>? onChanged;
  final bool readOnly;
  final String labelText;
  final TextStyle? labelStyle;
  final String? hintText;
  final TextStyle? hintStyle;
  final int maxLength;
  final TextInputType keyboardType;
  final List<TextInputFormatter> inputFormatters;

  const CommonPlateField({
    super.key,
    required this.controller,
    required this.maxLength,
    required this.keyboardType,
    required this.inputFormatters,
    this.onTap,
    this.onChanged,
    this.readOnly = false,
    this.labelText = '',
    this.labelStyle,
    this.hintText,
    this.hintStyle,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;

    return SizedBox(
      width: _getWidth(context),
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
        textAlign: TextAlign.center,
        inputFormatters: [
          LengthLimitingTextInputFormatter(maxLength),
          ...inputFormatters,
        ],
        readOnly: readOnly,
        decoration: InputDecoration(
          labelText: labelText,
          labelStyle: _getLabelStyle(theme),
          hintText: hintText,
          hintStyle: _getHintStyle(theme),
          contentPadding: const EdgeInsets.only(top: 20.0),
          enabledBorder: const UnderlineInputBorder(
            borderSide: BorderSide(color: Colors.black, width: 2.0),
          ),
          focusedBorder: const UnderlineInputBorder(
            borderSide: BorderSide(color: Colors.blue, width: 2.0),
          ),
        ),
        style: theme.bodyLarge?.copyWith(
          fontSize: 18,
          fontWeight: FontWeight.bold,
        ),
        onTap: () {
          if (onTap != null) {
            onTap!(); // 추가적인 콜백 호출
          }
          controller.clear(); // 입력 필드 초기화
        },
        onChanged: onChanged,
      ),
    );
  }

  /// **라벨 스타일 설정**
  TextStyle _getLabelStyle(TextTheme theme) {
    return labelStyle ??
        (theme.bodyLarge ?? const TextStyle()).copyWith(
          fontSize: 18,
          fontWeight: FontWeight.bold,
          color: Colors.grey,
        );
  }

  /// **힌트 스타일 설정**
  TextStyle _getHintStyle(TextTheme theme) {
    return hintStyle ??
        (theme.bodyMedium ?? const TextStyle()).copyWith(
          color: Colors.grey,
        );
  }

  /// **입력 필드의 폭 계산**
  double _getWidth(BuildContext context) {
    if (maxLength == 1) return 70;
    if (maxLength == 2) return MediaQuery.of(context).size.width * 0.25;
    if (maxLength == 3) return 100;
    if (maxLength == 4) return MediaQuery.of(context).size.width * 0.4;
    return MediaQuery.of(context).size.width * 0.5;
  }
}
