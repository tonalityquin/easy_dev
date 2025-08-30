import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 공통 번호판 입력 필드 위젯
class MonthlyPlateField extends StatelessWidget {
  final int frontDigitCount;
  final bool hasMiddleChar;
  final int backDigitCount;

  final TextEditingController frontController;
  final TextEditingController? middleController;
  final TextEditingController backController;

  final TextEditingController activeController;
  final ValueChanged<TextEditingController> onKeypadStateChanged;

  /// 수정 모드에서는 입력 비활성화
  final bool isEditMode;

  /// ✅ 중간 한글 칸 최소/고정 폭(잘림 방지)
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
    this.middleBoxWidth = 56, // 기본 56px (상황에 따라 60~72로 넉넉히)
  }) : assert(
  !hasMiddleChar || middleController != null,
  'hasMiddleChar=true이면 middleController가 필요합니다.',
  );

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // 앞자리: 남은 공간을 유연하게 사용
        Expanded(
          flex: frontDigitCount, // 자리수 비율 반영(2 또는 3)
          child: _buildDigitInput(context, frontController, maxLen: 4),
        ),
        if (hasMiddleChar) const SizedBox(width: 8),
        // ✅ 중간 한글: 고정 폭으로 확보
        if (hasMiddleChar)
          SizedBox(
            width: middleBoxWidth,
            child: _buildMiddleInput(context, middleController!),
          ),
        const SizedBox(width: 8),
        // 뒷자리: 남은 공간을 유연하게 사용
        Expanded(
          flex: backDigitCount, // 4자리 비율 반영
          child: _buildDigitInput(context, backController, maxLen: 4),
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

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      margin: const EdgeInsets.symmetric(horizontal: 4.0),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: isActive ? cs.primaryContainer.withOpacity(0.22) : cs.surface,
        borderRadius: BorderRadius.circular(8),
      ),
      child: TextField(
        controller: controller,
        keyboardType: TextInputType.none,
        maxLength: maxLen,
        textAlign: TextAlign.center,
        readOnly: true,
        enabled: !isEditMode,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        style: const TextStyle(fontSize: 18),
        decoration: InputDecoration(
          isDense: true,
          counterText: "",
          contentPadding: const EdgeInsets.symmetric(vertical: 8),
          border: UnderlineInputBorder(
            borderSide: BorderSide(width: 2.0, color: cs.outline),
          ),
          enabledBorder: UnderlineInputBorder(
            borderSide: BorderSide(width: 2.0, color: cs.outline),
          ),
          focusedBorder: UnderlineInputBorder(
            borderSide: BorderSide(width: 2.0, color: cs.primary),
          ),
        ),
        onTap: isEditMode ? null : () => onKeypadStateChanged(controller),
      ),
    );
  }

  Widget _buildMiddleInput(BuildContext context, TextEditingController controller) {
    final cs = Theme.of(context).colorScheme;
    final isActive = controller == activeController;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      margin: const EdgeInsets.symmetric(horizontal: 4.0),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: isActive ? cs.primaryContainer.withOpacity(0.22) : cs.surface,
        borderRadius: BorderRadius.circular(8),
      ),
      child: TextField(
        controller: controller,
        keyboardType: TextInputType.none,
        maxLength: 1,
        textAlign: TextAlign.center,
        readOnly: true,
        enabled: !isEditMode,
        inputFormatters: [
          // 한글 1자 (키패드 입력 가정)
          FilteringTextInputFormatter.allow(RegExp(r'[ㄱ-ㅎㅏ-ㅣ가-힣]')),
        ],
        style: const TextStyle(fontSize: 20), // ✅ 가독성 확보
        decoration: InputDecoration(
          isDense: true,
          counterText: "",
          contentPadding: const EdgeInsets.symmetric(vertical: 8),
          border: UnderlineInputBorder(
            borderSide: BorderSide(width: 2.0, color: cs.outline),
          ),
          enabledBorder: UnderlineInputBorder(
            borderSide: BorderSide(width: 2.0, color: cs.outline),
          ),
          focusedBorder: UnderlineInputBorder(
            borderSide: BorderSide(width: 2.0, color: cs.primary),
          ),
        ),
        onTap: isEditMode ? null : () => onKeypadStateChanged(controller),
      ),
    );
  }
}
