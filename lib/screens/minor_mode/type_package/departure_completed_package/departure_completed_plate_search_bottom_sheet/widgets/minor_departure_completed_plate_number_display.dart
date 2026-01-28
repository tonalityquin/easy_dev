import 'package:flutter/material.dart';

class MinorDepartureCompletedPlateNumberDisplay extends StatelessWidget {
  final TextEditingController controller;
  final bool Function(String) isValidPlate;

  const MinorDepartureCompletedPlateNumberDisplay({
    super.key,
    required this.controller,
    required this.isValidPlate,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, child) {
        final raw = value.text;
        final text = raw.trim();
        final valid = isValidPlate(text);

        // ✅ Theme(ColorScheme) 기반 톤/보더 통일
        final Color tone = text.isEmpty
            ? cs.onSurfaceVariant
            : (valid ? cs.tertiary : cs.error);

        final Color border = text.isEmpty
            ? cs.outlineVariant.withOpacity(0.85)
            : (valid ? cs.tertiary.withOpacity(0.55) : cs.error.withOpacity(0.60));

        Color boxBg(bool filled) {
          if (filled) return cs.surface;
          // 비어있는 칸은 톤을 살짝 죽여서 구분
          return cs.surfaceVariant.withOpacity(0.35);
        }

        TextStyle digitStyle(bool filled) => textTheme.titleLarge?.copyWith(
          fontSize: 22,
          fontWeight: FontWeight.w900,
          color: filled ? cs.onSurface : cs.onSurfaceVariant.withOpacity(0.55),
        ) ??
            TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w900,
              color: filled ? cs.onSurface : cs.onSurfaceVariant.withOpacity(0.55),
            );

        final IconData statusIcon = text.isEmpty
            ? Icons.edit
            : (valid ? Icons.check_circle_outline : Icons.error_outline);

        final String statusText = text.isEmpty
            ? '숫자 4자리를 입력해주세요.'
            : (valid ? '유효한 번호입니다.' : '숫자 4자리를 입력해주세요.');

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ✅ 4자리 박스 표시
            Row(
              children: List.generate(4, (i) {
                final char = (i < text.length) ? text[i] : '';
                final filled = char.isNotEmpty;

                return Expanded(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    curve: Curves.easeOutCubic,
                    margin: EdgeInsets.only(right: i == 3 ? 0 : 8),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(
                      color: boxBg(filled),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: border, width: 1.2),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.03),
                          blurRadius: 10,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: Center(
                      child: Text(
                        filled ? char : '•',
                        style: digitStyle(filled),
                      ),
                    ),
                  ),
                );
              }),
            ),

            const SizedBox(height: 10),

            AnimatedOpacity(
              opacity: text.isEmpty ? 0.9 : 1,
              duration: const Duration(milliseconds: 180),
              child: Row(
                children: [
                  Icon(statusIcon, size: 16, color: tone),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      statusText,
                      style: textTheme.bodySmall?.copyWith(
                        color: tone,
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                      ) ??
                          TextStyle(
                            color: tone,
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                  ),
                ],
              ),
            ),

            // ✅ 입력 가이드(빈 상태에서만)
            if (text.isEmpty) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.info_outline, size: 14, color: cs.primary.withOpacity(0.85)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '키패드로 4자리를 입력하면 검색할 수 있습니다.',
                      style: textTheme.bodySmall?.copyWith(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: cs.primary.withOpacity(0.85),
                      ) ??
                          TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: cs.primary.withOpacity(0.85),
                          ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        );
      },
    );
  }
}
