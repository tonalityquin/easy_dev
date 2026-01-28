import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class MinorModifyPlateField extends StatelessWidget {
  final int frontDigitCount;
  final bool hasMiddleChar;
  final int backDigitCount;

  final TextEditingController frontController;
  final TextEditingController? middleController;
  final TextEditingController backController;

  /// true면 수정 가능, false면 읽기 전용(기존 정책 유지)
  final bool isEditable;

  const MinorModifyPlateField({
    super.key,
    required this.frontDigitCount,
    required this.hasMiddleChar,
    required this.backDigitCount,
    required this.frontController,
    this.middleController,
    required this.backController,
    this.isEditable = false,
  });

  @override
  Widget build(BuildContext context) {
    // ✅ hasMiddleChar=true인데 middleController가 null이면 런타임 에러 → 방어
    assert(!hasMiddleChar || middleController != null,
    'hasMiddleChar=true 이면 middleController가 필요합니다.');

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Expanded(
          flex: frontDigitCount,
          child: _DigitBox(
            controller: frontController,
            maxLength: frontDigitCount,
            editable: isEditable,
            inputFormatters: _DigitBox.digitsOnlyFormatters,
          ),
        ),
        if (hasMiddleChar) const SizedBox(width: 6),
        if (hasMiddleChar)
          Expanded(
            flex: 1,
            child: _DigitBox(
              controller: middleController!,
              maxLength: 1,
              editable: isEditable,
              inputFormatters: _DigitBox.koreanCharFormatters,
            ),
          ),
        if (hasMiddleChar) const SizedBox(width: 6),
        Expanded(
          flex: backDigitCount,
          child: _DigitBox(
            controller: backController,
            maxLength: backDigitCount,
            editable: isEditable,
            inputFormatters: _DigitBox.digitsOnlyFormatters,
          ),
        ),
      ],
    );
  }
}

/// ✅ 공통 입력 박스(앞/한글/뒤 동일 스타일)
/// - underline 하드코딩 제거 → container border로 통일
/// - Theme(ColorScheme) 기반 색상 적용
/// - editable=false면 readOnly + 시각적 톤다운
class _DigitBox extends StatelessWidget {
  final TextEditingController controller;
  final int maxLength;
  final bool editable;
  final List<TextInputFormatter> inputFormatters;

  const _DigitBox({
    required this.controller,
    required this.maxLength,
    required this.editable,
    required this.inputFormatters,
  });

  // ✅ const 불가(Formatter들이 const가 아님) → static final로 재사용
  static final List<TextInputFormatter> digitsOnlyFormatters = <TextInputFormatter>[
    FilteringTextInputFormatter.digitsOnly,
  ];

  static final List<TextInputFormatter> koreanCharFormatters = <TextInputFormatter>[
    FilteringTextInputFormatter.allow(RegExp(r'[ㄱ-ㅎㅏ-ㅣ가-힣]')),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final String text = controller.text.trim();
    final bool isEmpty = text.isEmpty;

    final Color bg = editable ? cs.surface : cs.surfaceVariant.withOpacity(0.55);
    final Color border = editable
        ? cs.outlineVariant.withOpacity(0.85)
        : cs.outlineVariant.withOpacity(0.55);

    final Color fg = editable ? cs.onSurface : cs.onSurface.withOpacity(0.60);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      margin: const EdgeInsets.symmetric(horizontal: 2),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: border, width: 1.2),
      ),
      child: TextField(
        controller: controller,
        keyboardType: TextInputType.none,
        maxLength: maxLength,
        textAlign: TextAlign.center,
        readOnly: !editable,
        enabled: true, // readOnly여도 선택/복사 UX를 위해 enabled 유지
        inputFormatters: inputFormatters,
        style: theme.textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w900,
          color: fg,
        ),
        decoration: InputDecoration(
          counterText: '',
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(vertical: 10),
          border: InputBorder.none,
          hintText: isEmpty ? '' : null,
        ),
      ),
    );
  }
}
