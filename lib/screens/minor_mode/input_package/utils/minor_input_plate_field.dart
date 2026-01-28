import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class MinorInputPlateField extends StatelessWidget {
  final int frontDigitCount;
  final bool hasMiddleChar;
  final int backDigitCount;
  final TextEditingController frontController;
  final TextEditingController? middleController;
  final TextEditingController backController;
  final TextEditingController activeController;
  final Function(TextEditingController) onKeypadStateChanged;

  const MinorInputPlateField({
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
          child: _buildDigitInput(context, frontController, maxLength: 4),
        ),
        if (hasMiddleChar)
          Expanded(
            flex: 1,
            child: _buildMiddleInput(context, middleController!),
          ),
        Expanded(
          flex: backDigitCount,
          child: _buildDigitInput(context, backController, maxLength: 4),
        ),
      ],
    );
  }

  Widget _buildDigitInput(
      BuildContext context,
      TextEditingController controller, {
        required int maxLength,
      }) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    final isActive = controller == activeController;

    final bg = isActive ? cs.primaryContainer : cs.surface;
    final borderColor = isActive ? cs.primary : cs.outlineVariant;

    final textStyle = (tt.titleLarge ?? const TextStyle()).copyWith(
      fontWeight: FontWeight.w900,
      color: cs.onSurface,
    );

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      margin: const EdgeInsets.symmetric(horizontal: 4.0),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: borderColor.withOpacity(0.95), width: isActive ? 1.4 : 1.0),
      ),
      child: TextField(
        controller: controller,
        keyboardType: TextInputType.none,
        maxLength: maxLength,
        textAlign: TextAlign.center,
        readOnly: true,
        style: textStyle,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: InputDecoration(
          counterText: "",
          border: UnderlineInputBorder(
            borderSide: BorderSide(width: 2.0, color: cs.outline),
          ),
          enabledBorder: UnderlineInputBorder(
            borderSide: BorderSide(width: 2.0, color: cs.outline),
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
    final tt = Theme.of(context).textTheme;

    final isActive = controller == activeController;

    final bg = isActive ? cs.primaryContainer : cs.surface;
    final borderColor = isActive ? cs.primary : cs.outlineVariant;

    final textStyle = (tt.titleLarge ?? const TextStyle()).copyWith(
      fontWeight: FontWeight.w900,
      color: cs.onSurface,
    );

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      margin: const EdgeInsets.symmetric(horizontal: 4.0),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: borderColor.withOpacity(0.95), width: isActive ? 1.4 : 1.0),
      ),
      child: TextField(
        controller: controller,
        keyboardType: TextInputType.none,
        maxLength: 1,
        textAlign: TextAlign.center,
        readOnly: true,
        style: textStyle,
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp(r'^[ㄱ-ㅎㅏ-ㅣ가-힣]$')),
        ],
        decoration: InputDecoration(
          counterText: "",
          border: UnderlineInputBorder(
            borderSide: BorderSide(width: 2.0, color: cs.outline),
          ),
          enabledBorder: UnderlineInputBorder(
            borderSide: BorderSide(width: 2.0, color: cs.outline),
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
