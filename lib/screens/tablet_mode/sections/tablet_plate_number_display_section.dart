import 'package:flutter/material.dart';

class TabletPlateNumberDisplaySection extends StatelessWidget {
  final TextEditingController controller;
  final bool Function(String) isValidPlate;

  const TabletPlateNumberDisplaySection({
    super.key,
    required this.controller,
    required this.isValidPlate,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: controller,
          builder: (context, value, child) {
            final input = value.text;
            final valid = isValidPlate(input);

            // 입력이 없을 때는 힌트 톤(투명도)으로
            final baseColor = cs.onSurface;
            final displayColor = input.isEmpty
                ? baseColor.withOpacity(.65)
                : (valid ? baseColor : cs.error);

            return AnimatedOpacity(
              opacity: input.isEmpty ? 0.55 : 1.0,
              duration: const Duration(milliseconds: 300),
              child: Text(
                input.isEmpty ? '번호 입력 대기 중' : input,
                style: (textTheme.headlineSmall ?? const TextStyle()).copyWith(
                  fontSize: 26,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.2,
                  color: displayColor,
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 8),
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: controller,
          builder: (context, value, child) {
            final input = value.text;
            final valid = isValidPlate(input);

            if (input.isEmpty) {
              return const SizedBox.shrink();
            }

            // ✅ 성공/에러를 테마 토큰으로만 표현
            // - 성공: tertiary (앱 컨셉에서 "상태 강조"용 토큰으로 사용)
            // - 실패: error
            final msgColor = valid ? cs.tertiary : cs.error;

            return Text(
              valid ? '유효한 번호입니다.' : '숫자 4자리를 입력해주세요.',
              style: (textTheme.bodySmall ?? const TextStyle()).copyWith(
                color: msgColor,
                fontSize: 14,
                fontWeight: FontWeight.w700,
                height: 1.2,
              ),
            );
          },
        ),
      ],
    );
  }
}
