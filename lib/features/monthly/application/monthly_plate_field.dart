import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

const _fieldInk = Color(0xFF101828);
const _fieldMuted = Color(0xFF667085);
const _fieldLine = Color(0xFFD8DEE8);
const _fieldBlue = Color(0xFF2563EB);

class MonthlyPlateField extends StatelessWidget {
  final int frontDigitCount;
  final bool hasMiddleChar;
  final int backDigitCount;
  final TextEditingController frontController;
  final TextEditingController? middleController;
  final TextEditingController backController;
  final TextEditingController activeController;
  final ValueChanged<TextEditingController> onKeypadStateChanged;
  final bool isEditMode;
  final double middleBoxWidth;

  const MonthlyPlateField({
    super.key,
    required this.frontDigitCount,
    required this.hasMiddleChar,
    required this.backDigitCount,
    required this.frontController,
    this.middleController,
    required this.backController,
    required this.activeController,
    required this.onKeypadStateChanged,
    this.isEditMode = false,
    this.middleBoxWidth = 54,
  }) : assert(!hasMiddleChar || middleController != null, 'hasMiddleChar=true이면 middleController가 필요합니다.');

  static const _duration = Duration(milliseconds: 160);

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          flex: frontDigitCount,
          child: _BoxInput(
            controller: frontController,
            activeController: activeController,
            maxLen: frontDigitCount,
            isKorean: false,
            isEditMode: isEditMode,
            onKeypadStateChanged: onKeypadStateChanged,
          ),
        ),
        if (hasMiddleChar) const SizedBox(width: 8),
        if (hasMiddleChar)
          SizedBox(
            width: middleBoxWidth,
            child: _BoxInput(
              controller: middleController!,
              activeController: activeController,
              maxLen: 1,
              isKorean: true,
              isEditMode: isEditMode,
              onKeypadStateChanged: onKeypadStateChanged,
            ),
          ),
        const SizedBox(width: 8),
        Expanded(
          flex: backDigitCount,
          child: _BoxInput(
            controller: backController,
            activeController: activeController,
            maxLen: backDigitCount,
            isKorean: false,
            isEditMode: isEditMode,
            onKeypadStateChanged: onKeypadStateChanged,
          ),
        ),
      ],
    );
  }
}

class _BoxInput extends StatelessWidget {
  const _BoxInput({
    required this.controller,
    required this.activeController,
    required this.maxLen,
    required this.isKorean,
    required this.isEditMode,
    required this.onKeypadStateChanged,
  });

  final TextEditingController controller;
  final TextEditingController activeController;
  final int maxLen;
  final bool isKorean;
  final bool isEditMode;
  final ValueChanged<TextEditingController> onKeypadStateChanged;

  @override
  Widget build(BuildContext context) {
    final isActive = controller == activeController && !isEditMode;
    final enabled = !isEditMode;
    final background = enabled
        ? isActive
            ? const Color(0xFFEFF6FF)
            : const Color(0xFFF8FAFC)
        : const Color(0xFFEFF2F7);

    return AnimatedContainer(
      duration: MonthlyPlateField._duration,
      height: 54,
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: isActive ? _fieldBlue : _fieldLine, width: isActive ? 1.6 : 1),
        boxShadow: isActive
            ? [
                BoxShadow(
                  color: _fieldBlue.withOpacity(.12),
                  blurRadius: 12,
                  offset: const Offset(0, 5),
                ),
              ]
            : const [],
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          TextField(
            controller: controller,
            keyboardType: TextInputType.none,
            maxLength: maxLen,
            textAlign: TextAlign.center,
            readOnly: true,
            enabled: enabled,
            showCursor: false,
            inputFormatters: [
              if (!isKorean) FilteringTextInputFormatter.digitsOnly,
              if (isKorean) FilteringTextInputFormatter.allow(RegExp(r'[ㄱ-ㅎㅏ-ㅣ가-힣]')),
            ],
            style: TextStyle(
              color: enabled ? _fieldInk : _fieldMuted,
              fontWeight: FontWeight.w900,
              fontSize: isKorean ? 20 : 18,
              letterSpacing: isKorean ? 0 : .8,
            ),
            decoration: const InputDecoration(
              isDense: true,
              counterText: '',
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              disabledBorder: InputBorder.none,
              contentPadding: EdgeInsets.zero,
            ),
            onTap: enabled ? () => onKeypadStateChanged(controller) : null,
          ),
          Positioned(
            right: 8,
            top: 8,
            child: AnimatedOpacity(
              duration: MonthlyPlateField._duration,
              opacity: isActive ? 1 : 0,
              child: Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: _fieldBlue,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
