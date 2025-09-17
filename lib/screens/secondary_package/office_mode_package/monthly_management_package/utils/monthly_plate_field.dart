import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 서비스 로그인 카드(Deep Blue 팔레트) 톤 참조
class _SvcColors {
  static const base = Color(0xFF0D47A1);
  static const light = Color(0xFF5472D3);
}

/// 공통 번호판 입력 필드 위젯
/// - 앱 ColorScheme와 서비스 팔레트 컬러를 반영
/// - 활성/비활성/포커스 상태별 톤 분리
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
    this.middleBoxWidth = 56,
  }) : assert(
  !hasMiddleChar || middleController != null,
  'hasMiddleChar=true이면 middleController가 필요합니다.',
  );

  static const _radius = 10.0;
  static const _anim = Duration(milliseconds: 180);

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // 앞자리
        Expanded(
          flex: frontDigitCount,
          child: _buildDigitInput(context, frontController, maxLen: 4),
        ),
        if (hasMiddleChar) const SizedBox(width: 8),
        // 중간 한글
        if (hasMiddleChar)
          SizedBox(
            width: middleBoxWidth,
            child: _buildMiddleInput(context, middleController!),
          ),
        const SizedBox(width: 8),
        // 뒷자리
        Expanded(
          flex: backDigitCount,
          child: _buildDigitInput(context, backController, maxLen: 4),
        ),
      ],
    );
  }

  InputBorder _underline({
    required Color color,
    required double width,
  }) =>
      UnderlineInputBorder(
        borderSide: BorderSide(width: width, color: color),
      );

  BoxDecoration _fieldBox({
    required bool isActive,
    required ColorScheme cs,
  }) {
    // 활성 시 토널 하이라이트 + 아주 은은한 그림자
    final bg = isActive
        ? cs.primaryContainer.withOpacity(.22)
        : cs.surface;
    return BoxDecoration(
      color: bg,
      borderRadius: BorderRadius.circular(_radius),
      boxShadow: isActive
          ? [
        BoxShadow(
          color: _SvcColors.light.withOpacity(.08),
          blurRadius: 10,
          offset: const Offset(0, 4),
        ),
      ]
          : const [],
      border: Border.all(
        color: isActive ? _SvcColors.base.withOpacity(.28) : cs.outlineVariant.withOpacity(.48),
        width: 1,
      ),
    );
  }

  Widget _buildDigitInput(
      BuildContext context,
      TextEditingController controller, {
        required int maxLen,
      }) {
    final cs = Theme.of(context).colorScheme;
    final isActive = controller == activeController;
    final enabled = !isEditMode;

    return AnimatedContainer(
      duration: _anim,
      margin: const EdgeInsets.symmetric(horizontal: 4.0),
      padding: const EdgeInsets.all(6),
      decoration: _fieldBox(isActive: isActive, cs: cs),
      child: TextField(
        controller: controller,
        keyboardType: TextInputType.none,
        maxLength: maxLen,
        textAlign: TextAlign.center,
        readOnly: true,
        enabled: enabled,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        style: TextStyle(
          fontSize: 18,
          color: enabled ? cs.onSurface : cs.onSurface.withOpacity(.5),
          fontWeight: FontWeight.w600,
          letterSpacing: .5,
        ),
        decoration: InputDecoration(
          isDense: true,
          counterText: "",
          contentPadding: const EdgeInsets.symmetric(vertical: 8),
          border: _underline(color: cs.outline, width: 2),
          enabledBorder: _underline(color: cs.outline, width: 2),
          focusedBorder: _underline(color: cs.primary, width: 2.2),
          disabledBorder: _underline(color: cs.outline.withOpacity(.5), width: 2),
        ),
        onTap: isEditMode ? null : () => onKeypadStateChanged(controller),
      ),
    );
  }

  Widget _buildMiddleInput(BuildContext context, TextEditingController controller) {
    final cs = Theme.of(context).colorScheme;
    final isActive = controller == activeController;
    final enabled = !isEditMode;

    return AnimatedContainer(
      duration: _anim,
      margin: const EdgeInsets.symmetric(horizontal: 4.0),
      padding: const EdgeInsets.all(6),
      decoration: _fieldBox(isActive: isActive, cs: cs),
      child: TextField(
        controller: controller,
        keyboardType: TextInputType.none,
        maxLength: 1,
        textAlign: TextAlign.center,
        readOnly: true,
        enabled: enabled,
        inputFormatters: [
          // 한글 1자 (키패드 입력 가정)
          FilteringTextInputFormatter.allow(RegExp(r'[ㄱ-ㅎㅏ-ㅣ가-힣]')),
        ],
        style: TextStyle(
          fontSize: 20,
          color: enabled ? cs.onSurface : cs.onSurface.withOpacity(.5),
          fontWeight: FontWeight.w700,
          letterSpacing: .5,
        ),
        decoration: InputDecoration(
          isDense: true,
          counterText: "",
          contentPadding: const EdgeInsets.symmetric(vertical: 8),
          border: _underline(color: cs.outline, width: 2),
          enabledBorder: _underline(color: cs.outline, width: 2),
          focusedBorder: _underline(color: cs.primary, width: 2.2),
          disabledBorder: _underline(color: cs.outline.withOpacity(.5), width: 2),
        ),
        onTap: isEditMode ? null : () => onKeypadStateChanged(controller),
      ),
    );
  }
}
