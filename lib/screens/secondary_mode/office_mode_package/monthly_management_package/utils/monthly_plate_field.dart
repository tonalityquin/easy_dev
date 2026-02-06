import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 공통 번호판 입력 필드 위젯
/// - 기존 로직(키패드 활성 컨트롤러, editMode 비활성화 등) 유지
/// - ✅ 고정 팔레트 제거 → ColorScheme/TextTheme 기반
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

  /// 중간 한글 칸 최소/고정 폭(잘림 방지)
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
  }) : assert(!hasMiddleChar || middleController != null, 'hasMiddleChar=true이면 middleController가 필요합니다.');

  static const _radius = 12.0;
  static const _anim = Duration(milliseconds: 180);

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          flex: frontDigitCount,
          child: _buildBoxInput(
            context,
            frontController,
            // ✅ 앞자리는 2/3자리 모드에 맞춰 maxLen 적용
            maxLen: frontDigitCount,
            isMiddle: false,
            isKorean: false,
          ),
        ),
        if (hasMiddleChar) const SizedBox(width: 8),
        if (hasMiddleChar)
          SizedBox(
            width: middleBoxWidth,
            child: _buildBoxInput(
              context,
              middleController!,
              maxLen: 1,
              isMiddle: true,
              isKorean: true,
            ),
          ),
        const SizedBox(width: 8),
        Expanded(
          flex: backDigitCount,
          child: _buildBoxInput(
            context,
            backController,
            // 통상 뒷자리는 4자리
            maxLen: backDigitCount,
            isMiddle: false,
            isKorean: false,
          ),
        ),
      ],
    );
  }

  BoxDecoration _fieldBox({
    required bool isActive,
    required bool enabled,
    required ColorScheme cs,
  }) {
    final bg = !enabled
        ? cs.surfaceVariant.withOpacity(.55)
        : (isActive ? cs.primaryContainer.withOpacity(.35) : cs.surface);

    return BoxDecoration(
      color: bg,
      borderRadius: BorderRadius.circular(_radius),
      border: Border.all(
        color: isActive ? cs.primary.withOpacity(.55) : cs.outlineVariant.withOpacity(.65),
        width: isActive ? 1.6 : 1.0,
      ),
      boxShadow: isActive
          ? [
        BoxShadow(
          color: cs.shadow.withOpacity(.12),
          blurRadius: 10,
          offset: const Offset(0, 4),
        ),
      ]
          : const [],
    );
  }

  TextStyle _textStyle(
      BuildContext context, {
        required ColorScheme cs,
        required bool enabled,
        required bool isKorean,
      }) {
    final tt = Theme.of(context).textTheme;

    final base = (isKorean ? tt.titleMedium : tt.titleSmall) ?? const TextStyle(fontSize: 16);
    return base.copyWith(
      fontSize: isKorean ? 20 : 18,
      color: enabled ? cs.onSurface : cs.onSurface.withOpacity(.45),
      fontWeight: isKorean ? FontWeight.w800 : FontWeight.w700,
      letterSpacing: .6,
      height: 1.1,
    );
  }

  Widget _buildBoxInput(
      BuildContext context,
      TextEditingController controller, {
        required int maxLen,
        required bool isMiddle,
        required bool isKorean,
      }) {
    final cs = Theme.of(context).colorScheme;
    final isActive = controller == activeController;
    final enabled = !isEditMode;

    return AnimatedContainer(
      duration: _anim,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: _fieldBox(isActive: isActive, enabled: enabled, cs: cs),
      child: Stack(
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
            style: _textStyle(
              context,
              cs: cs,
              enabled: enabled,
              isKorean: isKorean,
            ),
            decoration: const InputDecoration(
              isDense: true,
              counterText: "",
              border: InputBorder.none,
              focusedBorder: InputBorder.none,
              enabledBorder: InputBorder.none,
              disabledBorder: InputBorder.none,
              contentPadding: EdgeInsets.zero,
            ),
            onTap: isEditMode ? null : () => onKeypadStateChanged(controller),
          ),

          // 활성 표시(미세한 점)
          Positioned(
            right: 0,
            top: 0,
            child: AnimatedOpacity(
              opacity: isActive ? 1 : 0,
              duration: _anim,
              child: Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: cs.primary,
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
