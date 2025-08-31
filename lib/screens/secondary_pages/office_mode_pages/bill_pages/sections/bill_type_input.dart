import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class BillTypeInput extends StatelessWidget {
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

  const BillTypeInput({
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
    final cs = Theme.of(context).colorScheme;

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
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: cs.primary, width: 2),
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
