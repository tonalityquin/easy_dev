import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 수정된 번호판 입력 필드 위젯 (ModifyPlateInfo 용)
class ModifyPlateInput extends StatelessWidget {
  final int frontDigitCount; // 앞자리 숫자 개수
  final bool hasMiddleChar; // 중간 한글 여부
  final int backDigitCount; // 뒷자리 숫자 개수
  final TextEditingController frontController;
  final TextEditingController? middleController;
  final TextEditingController backController;
  final bool isEditable; // 수정 가능한지 여부 (ModifyPlateInfo에서는 false)

  const ModifyPlateInput({
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
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Expanded(
          flex: frontDigitCount,
          child: _buildDigitInput(frontController, frontDigitCount, ""),
        ),
        if (hasMiddleChar)
          Expanded(
            flex: 1,
            child: _buildMiddleInput(middleController!, ""),
          ),
        Expanded(
          flex: backDigitCount,
          child: _buildDigitInput(backController, backDigitCount, ""),
        ),
      ],
    );
  }

  Widget _buildDigitInput(TextEditingController controller, int length, String labelText) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 4.0),
      child: TextField(
        controller: controller,
        keyboardType: TextInputType.none,
        maxLength: length,
        textAlign: TextAlign.center,
        readOnly: !isEditable,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: InputDecoration(
          counterText: "",
          border: const UnderlineInputBorder(
            borderSide: BorderSide(width: 2.0, color: Colors.black),
          ),
          labelText: labelText.isEmpty ? null : labelText,
          labelStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }

  Widget _buildMiddleInput(TextEditingController controller, String labelText) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 4.0),
      child: TextField(
        controller: controller,
        keyboardType: TextInputType.none,
        maxLength: 1,
        textAlign: TextAlign.center,
        readOnly: !isEditable,
        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^[ㄱ-ㅎㅏ-ㅣ가-힣]$'))],
        decoration: InputDecoration(
          counterText: "",
          border: const UnderlineInputBorder(
            borderSide: BorderSide(width: 2.0, color: Colors.black),
          ),
          labelText: labelText.isEmpty ? null : labelText,
          labelStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}
