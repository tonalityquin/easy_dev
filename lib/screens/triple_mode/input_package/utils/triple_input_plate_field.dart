import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class TripleInputPlateField extends StatelessWidget {
  final int frontDigitCount;
  final bool hasMiddleChar;
  final int backDigitCount;
  final TextEditingController frontController;
  final TextEditingController? middleController;
  final TextEditingController backController;
  final TextEditingController activeController;
  final Function(TextEditingController) onKeypadStateChanged;

  const TripleInputPlateField({
    super.key,
    required this.frontDigitCount,
    required this.hasMiddleChar,
    required this.backDigitCount,
    required this.frontController,
    this.middleController,
    required this.backController,
    required this.activeController,
    required this.onKeypadStateChanged,
  });

  @override
  Widget build(BuildContext context) {
    // hasMiddleChar=true인데 middleController가 null이면 런타임 에러가 나므로 방어
    assert(!hasMiddleChar || middleController != null);

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Expanded(
          flex: frontDigitCount,
          child: _DigitBox(
            controller: frontController,
            isActive: frontController == activeController,
            maxLength: 4,
            inputFormatters: _DigitBox.formatDigitsOnly,
            onTap: () => onKeypadStateChanged(frontController),
          ),
        ),
        if (hasMiddleChar)
          Expanded(
            flex: 1,
            child: _DigitBox(
              controller: middleController!,
              isActive: middleController == activeController,
              maxLength: 1,
              inputFormatters: _DigitBox.formatKoreanOnly,
              onTap: () => onKeypadStateChanged(middleController!),
            ),
          ),
        Expanded(
          flex: backDigitCount,
          child: _DigitBox(
            controller: backController,
            isActive: backController == activeController,
            maxLength: 4,
            inputFormatters: _DigitBox.formatDigitsOnly,
            onTap: () => onKeypadStateChanged(backController),
          ),
        ),
      ],
    );
  }
}

/// ✅ 공통 입력 박스(앞/한글/뒤 동일 스타일)
/// - const list 에러를 피하기 위해 inputFormatters는 static final로 캐싱
class _DigitBox extends StatelessWidget {
  // ✅ const list 에러 해결: digitsOnly / allow(...)는 const가 아니므로 static final로 보관
  static final List<TextInputFormatter> formatDigitsOnly = <TextInputFormatter>[
    FilteringTextInputFormatter.digitsOnly,
  ];

  static final List<TextInputFormatter> formatKoreanOnly = <TextInputFormatter>[
    FilteringTextInputFormatter.allow(RegExp(r'^[ㄱ-ㅎㅏ-ㅣ가-힣]$')),
  ];

  final TextEditingController controller;
  final bool isActive;
  final int maxLength;
  final List<TextInputFormatter> inputFormatters;
  final VoidCallback onTap;

  const _DigitBox({
    required this.controller,
    required this.isActive,
    required this.maxLength,
    required this.inputFormatters,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final Color bg = isActive ? cs.primaryContainer.withOpacity(0.55) : cs.surface;
    final Color border =
    isActive ? cs.primary.withOpacity(0.75) : cs.outlineVariant.withOpacity(0.85);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      margin: const EdgeInsets.symmetric(horizontal: 4.0),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: border, width: isActive ? 1.4 : 1.0),
      ),
      child: TextField(
        controller: controller,
        keyboardType: TextInputType.none,
        maxLength: maxLength,
        textAlign: TextAlign.center,
        readOnly: true,
        inputFormatters: inputFormatters,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w900,
          color: cs.onSurface,
        ),
        decoration: const InputDecoration(
          counterText: '',
          isDense: true,
          contentPadding: EdgeInsets.symmetric(vertical: 10),
          // underline 제거: 외곽선은 컨테이너에서 처리
          border: InputBorder.none,
        ),
        onTap: onTap,
      ),
    );
  }
}
