// lib/screens/secondary_package/office_mode_package/bill_management_package/sections/bill_type_input_section.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 서비스 로그인 카드 팔레트(리팩터링 공통 색)
const serviceCardBase  = Color(0xFF0D47A1);
const serviceCardDark  = Color(0xFF09367D);
const serviceCardLight = Color(0xFF5472D3);
const serviceCardFg    = Colors.white; // 버튼/아이콘 전경
const serviceCardBg    = Colors.white; // 카드/시트 배경

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
    return TextFormField(
      controller: controller,
      enabled: enabled,
      autofocus: autofocus,
      textInputAction: textInputAction,
      maxLines: 1,
      autocorrect: false,
      enableSuggestions: false,
      inputFormatters: [
        // 줄바꿈 차단 + 앞뒤 공백 유입 최소화
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
        focusedBorder: const OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(8)),
          borderSide: BorderSide(color: serviceCardBase, width: 2),
        ),
        floatingLabelStyle: const TextStyle(color: serviceCardDark, fontWeight: FontWeight.w600),
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
