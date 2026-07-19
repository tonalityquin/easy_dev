import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../design_system/prompt_ui/prompt_ui_theme.dart';

class MonthlyPlateField extends StatelessWidget {
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
  }) : assert(
          !hasMiddleChar || middleController != null,
          'hasMiddleChar=true이면 middleController가 필요합니다.',
        );

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

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          flex: frontDigitCount,
          child: _PlateBoxInput(
            controller: frontController,
            activeController: activeController,
            maxLength: frontDigitCount,
            korean: false,
            editMode: isEditMode,
            onSelected: onKeypadStateChanged,
          ),
        ),
        if (hasMiddleChar) const SizedBox(width: 8),
        if (hasMiddleChar)
          SizedBox(
            width: middleBoxWidth,
            child: _PlateBoxInput(
              controller: middleController!,
              activeController: activeController,
              maxLength: 1,
              korean: true,
              editMode: isEditMode,
              onSelected: onKeypadStateChanged,
            ),
          ),
        const SizedBox(width: 8),
        Expanded(
          flex: backDigitCount,
          child: _PlateBoxInput(
            controller: backController,
            activeController: activeController,
            maxLength: backDigitCount,
            korean: false,
            editMode: isEditMode,
            onSelected: onKeypadStateChanged,
          ),
        ),
      ],
    );
  }
}

class _PlateBoxInput extends StatelessWidget {
  const _PlateBoxInput({
    required this.controller,
    required this.activeController,
    required this.maxLength,
    required this.korean,
    required this.editMode,
    required this.onSelected,
  });

  final TextEditingController controller;
  final TextEditingController activeController;
  final int maxLength;
  final bool korean;
  final bool editMode;
  final ValueChanged<TextEditingController> onSelected;

  @override
  Widget build(BuildContext context) {
    final tokens = PromptUiTheme.of(context);
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final active = controller == activeController && !editMode;
    final enabled = !editMode;
    final background = enabled
        ? active
            ? tokens.surfaceSelected
            : tokens.surfaceOverlay
        : tokens.surfaceDisabled;
    final border = active ? tokens.focusRing : tokens.borderSubtle;

    return Semantics(
      textField: true,
      enabled: enabled,
      selected: active,
      label: korean ? '번호판 가운데 글자' : '번호판 숫자',
      child: AnimatedContainer(
        duration: reduceMotion ? Duration.zero : PromptUiMotion.selection,
        curve: PromptUiMotion.standard,
        height: 54,
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(PromptUiShapes.control),
          border: Border.all(color: border, width: active ? 1.5 : 1),
          boxShadow: [
            if (active)
              BoxShadow(
                color: tokens.focusRing.withOpacity(0.16),
                blurRadius: 12,
                offset: const Offset(0, 5),
              ),
          ],
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            TextField(
              controller: controller,
              keyboardType: TextInputType.none,
              maxLength: maxLength,
              textAlign: TextAlign.center,
              readOnly: true,
              enabled: enabled,
              showCursor: false,
              inputFormatters: [
                if (!korean) FilteringTextInputFormatter.digitsOnly,
                if (korean)
                  FilteringTextInputFormatter.allow(
                    RegExp(r'[ㄱ-ㅎㅏ-ㅣ가-힣]'),
                  ),
              ],
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: enabled ? tokens.textPrimary : tokens.textDisabled,
                    fontWeight: FontWeight.w800,
                    letterSpacing: korean ? 0 : 0.8,
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
              onTap: enabled ? () => onSelected(controller) : null,
            ),
            Positioned(
              right: 8,
              top: 8,
              child: AnimatedScale(
                scale: active ? 1 : 0,
                duration: reduceMotion ? Duration.zero : PromptUiMotion.press,
                curve: PromptUiMotion.enter,
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: tokens.accent,
                    borderRadius: BorderRadius.circular(PromptUiShapes.pill),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
