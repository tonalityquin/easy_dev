import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 공통 번호판 입력 필드 위젯
class CommonPlateInput extends StatelessWidget {
  final int frontDigitCount; // 앞자리 숫자 개수
  final bool hasMiddleChar;  // 중간 한글 여부
  final int backDigitCount;  // 뒷자리 숫자 개수
  final TextEditingController frontController;
  final TextEditingController? middleController;
  final TextEditingController backController;
  final Function(TextEditingController) onKeypadStateChanged; // ✅ 키패드 상태 변경 콜백 추가

  const CommonPlateInput({
    super.key,
    required this.frontDigitCount,
    required this.hasMiddleChar,
    required this.backDigitCount,
    required this.frontController,
    this.middleController,
    required this.backController,
    required this.onKeypadStateChanged, // ✅ Keypad 상태 변경 콜백 추가
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center, // 중앙 정렬
      children: [
        Expanded(
          flex: frontDigitCount,
          child: _buildDigitInput(frontController, frontDigitCount, "${frontDigitCount}-digit"),
        ),
        if (hasMiddleChar)
          Expanded(
            flex: 1,
            child: _buildMiddleInput(middleController!, "1-digit"),
          ), // 한글 필드 추가
        Expanded(
          flex: backDigitCount,
          child: _buildDigitInput(backController, backDigitCount, "${backDigitCount}-digit"),
        ),
      ],
    );
  }

  /// 숫자 입력 필드 (3-digit, 4-digit)
  Widget _buildDigitInput(TextEditingController controller, int length, String labelText) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 4.0),
      child: TextField(
        controller: controller,
        keyboardType: TextInputType.none, // ✅ 핸드폰 가상 키패드 비활성화
        maxLength: length,
        textAlign: TextAlign.center, // 가운데 정렬 추가
        readOnly: true, // ✅ 강제 읽기 전용으로 설정 (Keypad만 사용)
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: InputDecoration(
          counterText: "", // 글자 수 제한 표시 제거
          border: const UnderlineInputBorder(
            borderSide: BorderSide(width: 2.0, color: Colors.black), // 진한 밑줄 추가
          ),
          labelText: labelText, // 라벨 추가
          labelStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold), // 라벨 스타일 강화
        ),
        onTap: () {
          _resetAndFocusFrontField(); // ✅ 모든 필드 초기화 후 3-digit에 포커스
        },
      ),
    );
  }

  /// 한글 입력 필드 (1-digit)
  Widget _buildMiddleInput(TextEditingController controller, String labelText) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 4.0),
      child: TextField(
        controller: controller,
        keyboardType: TextInputType.none, // ✅ 핸드폰 가상 키패드 비활성화
        maxLength: 1,
        textAlign: TextAlign.center, // 가운데 정렬 추가
        readOnly: true, // ✅ 강제 읽기 전용으로 설정 (Keypad만 사용)
        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^[ㄱ-ㅎㅏ-ㅣ가-힣]$'))],
        decoration: InputDecoration(
          counterText: "",
          border: const UnderlineInputBorder(
            borderSide: BorderSide(width: 2.0, color: Colors.black), // 진한 밑줄 추가
          ),
          labelText: labelText, // 라벨 추가
          labelStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold), // 라벨 스타일 강화
        ),
        onTap: () {
          _resetAndFocusFrontField(); // ✅ 모든 필드 초기화 후 3-digit에 포커스
        },
      ),
    );
  }

  /// ✅ **모든 입력 필드를 초기화하고 3-digit을 활성화**
  void _resetAndFocusFrontField() {
    frontController.clear();
    middleController?.clear();
    backController.clear();
    onKeypadStateChanged(frontController); // ✅ 3-digit Keypad 활성화
  }
}
