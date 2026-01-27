import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class DoubleInputPlateField extends StatelessWidget {
  final int frontDigitCount;
  final bool hasMiddleChar;
  final int backDigitCount;
  final TextEditingController frontController;
  final TextEditingController? middleController;
  final TextEditingController backController;
  final TextEditingController activeController;
  final Function(TextEditingController) onKeypadStateChanged;

  const DoubleInputPlateField({
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
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Expanded(
          flex: frontDigitCount,
          child: _buildDigitInput(context, frontController, maxLen: frontDigitCount),
        ),
        if (hasMiddleChar)
          Expanded(
            flex: 1,
            child: _buildMiddleInput(context, middleController!),
          ),
        Expanded(
          flex: backDigitCount,
          child: _buildDigitInput(context, backController, maxLen: backDigitCount),
        ),
      ],
    );
  }

  Widget _buildDigitInput(
      BuildContext context,
      TextEditingController controller, {
        required int maxLen,
      }) {
    final cs = Theme.of(context).colorScheme;
    final isActive = controller == activeController;

    final bg = isActive ? cs.primary.withOpacity(0.08) : cs.surface;
    final border = isActive ? cs.primary.withOpacity(0.70) : cs.outlineVariant.withOpacity(0.85);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      margin: const EdgeInsets.symmetric(horizontal: 4.0),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: border),
      ),
      child: TextField(
        controller: controller,
        keyboardType: TextInputType.none,
        maxLength: maxLen, // ✅ 기존 코드의 maxLength=4 고정 제거(파라미터로 정확히)
        textAlign: TextAlign.center,
        readOnly: true,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        style: TextStyle(
          color: cs.onSurface,
          fontWeight: FontWeight.w900,
          fontSize: 18,
        ),
        decoration: InputDecoration(
          counterText: "",
          border: UnderlineInputBorder(
            borderSide: BorderSide(width: 2.0, color: cs.onSurface),
          ),
          enabledBorder: UnderlineInputBorder(
            borderSide: BorderSide(width: 2.0, color: cs.onSurface),
          ),
          focusedBorder: UnderlineInputBorder(
            borderSide: BorderSide(width: 2.2, color: cs.primary),
          ),
        ),
        onTap: () => onKeypadStateChanged(controller),
      ),
    );
  }

  Widget _buildMiddleInput(BuildContext context, TextEditingController controller) {
    final cs = Theme.of(context).colorScheme;
    final isActive = controller == activeController;

    final bg = isActive ? cs.primary.withOpacity(0.08) : cs.surface;
    final border = isActive ? cs.primary.withOpacity(0.70) : cs.outlineVariant.withOpacity(0.85);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      margin: const EdgeInsets.symmetric(horizontal: 4.0),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: border),
      ),
      child: TextField(
        controller: controller,
        keyboardType: TextInputType.none,
        maxLength: 1,
        textAlign: TextAlign.center,
        readOnly: true,
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp(r'^[ㄱ-ㅎㅏ-ㅣ가-힣]$')),
        ],
        style: TextStyle(
          color: cs.onSurface,
          fontWeight: FontWeight.w900,
          fontSize: 18,
        ),
        decoration: InputDecoration(
          counterText: "",
          border: UnderlineInputBorder(
            borderSide: BorderSide(width: 2.0, color: cs.onSurface),
          ),
          enabledBorder: UnderlineInputBorder(
            borderSide: BorderSide(width: 2.0, color: cs.onSurface),
          ),
          focusedBorder: UnderlineInputBorder(
            borderSide: BorderSide(width: 2.2, color: cs.primary),
          ),
        ),
        onTap: () => onKeypadStateChanged(controller),
      ),
    );
  }
}
