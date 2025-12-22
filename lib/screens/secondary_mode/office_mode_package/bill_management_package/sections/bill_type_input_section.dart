// lib/screens/secondary_package/office_mode_package/bill_management_package/sections/bill_type_input_section.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../../../theme.dart'; // ✅ AppCardPalette 사용 (프로젝트 경로에 맞게 조정)

class BillTypeInputSection extends StatelessWidget {
  final TextEditingController controller;

  // 선택 옵션들: 라벨/힌트/에러/활성화/포커스 처리 등
  final String label;
  final String hint;
  final String? errorText;
  final bool enabled;
  final bool autofocus;
  final TextInputAction textInputAction;
  final VoidCallback? onEditingComplete;
  final ValueChanged<String>? onChanged;

  const BillTypeInputSection({
    super.key,
    required this.controller,
    this.label = '변동 정산 유형',
    this.hint = '예: 기본 요금',
    this.errorText,
    this.enabled = true,
    this.autofocus = false,
    this.textInputAction = TextInputAction.next,
    this.onEditingComplete,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    // ✅ Service 팔레트: ThemeExtension(AppCardPalette)에서 획득
    final palette = AppCardPalette.of(context);
    final serviceBase = palette.serviceBase;
    final serviceDark = palette.serviceDark;

    return TextFormField(
      controller: controller,
      enabled: enabled,
      autofocus: autofocus,
      textInputAction: textInputAction,
      maxLines: 1,
      autocorrect: false,
      enableSuggestions: false,
      inputFormatters: [
        // ✅ const 제거: FilteringTextInputFormatter/RegExp는 const가 아님
        FilteringTextInputFormatter.deny(RegExp(r'[\n\r]')),
      ],
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        errorText: errorText,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: Colors.black.withOpacity(0.12)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: const BorderRadius.all(Radius.circular(8)),
          borderSide: BorderSide(color: serviceBase, width: 2),
        ),
        floatingLabelStyle: TextStyle(
          color: serviceDark,
          fontWeight: FontWeight.w600,
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      ),
      onChanged: onChanged,
      onEditingComplete: onEditingComplete,
      validator: (v) {
        final t = v?.trim() ?? '';
        if (t.isEmpty) return '정산 유형을 입력해주세요.';
        return null;
      },
    );
  }
}
