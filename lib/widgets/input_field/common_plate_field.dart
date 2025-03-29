import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 공통 번호판 입력 필드 위젯
class CommonPlateInput extends StatelessWidget {
  final int frontDigitCount;
  final bool hasMiddleChar;
  final int backDigitCount;
  final TextEditingController frontController;
  final TextEditingController? middleController;
  final TextEditingController backController;
  final TextEditingController activeController;
  final Function(TextEditingController) onKeypadStateChanged;

  const CommonPlateInput({
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
          child: _buildDigitInput(frontController),
        ),
        if (hasMiddleChar)
          Expanded(
            flex: 1,
            child: _buildMiddleInput(middleController!),
          ),
        Expanded(
          flex: backDigitCount,
          child: _buildDigitInput(backController),
        ),
      ],
    );
  }

  Widget _buildDigitInput(TextEditingController controller) {
    final isActive = controller == activeController;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      margin: const EdgeInsets.symmetric(horizontal: 4.0),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: isActive ? Colors.red.shade50 : Colors.white,
        borderRadius: BorderRadius.circular(6),
      ),
      child: TextField(
        controller: controller,
        keyboardType: TextInputType.none,
        maxLength: 4, // 최대 자릿수 제한 (공통적으로 3~4자)
        textAlign: TextAlign.center,
        readOnly: true,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: const InputDecoration(
          counterText: "",
          border: UnderlineInputBorder(
            borderSide: BorderSide(width: 2.0, color: Colors.black),
          ),
        ),
        onTap: () => onKeypadStateChanged(controller),
      ),
    );
  }

  Widget _buildMiddleInput(TextEditingController controller) {
    final isActive = controller == activeController;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      margin: const EdgeInsets.symmetric(horizontal: 4.0),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: isActive ? Colors.red.shade50 : Colors.white,
        borderRadius: BorderRadius.circular(6),
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
        decoration: const InputDecoration(
          counterText: "",
          border: UnderlineInputBorder(
            borderSide: BorderSide(width: 2.0, color: Colors.black),
          ),
        ),
        onTap: () => onKeypadStateChanged(controller),
      ),
    );
  }
}
