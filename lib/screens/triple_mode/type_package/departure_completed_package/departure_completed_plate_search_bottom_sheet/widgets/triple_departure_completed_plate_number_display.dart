import 'package:flutter/material.dart';

class TripleDepartureCompletedPlateNumberDisplay extends StatelessWidget {
  final TextEditingController controller;
  final bool Function(String) isValidPlate;

  const TripleDepartureCompletedPlateNumberDisplay({
    super.key,
    required this.controller,
    required this.isValidPlate,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, child) {
        final text = value.text;
        final valid = isValidPlate(text);

        final Color tone = text.isEmpty
            ? cs.onSurfaceVariant
            : (valid ? cs.primary : cs.error);

        final Color border = text.isEmpty
            ? cs.outlineVariant
            : (valid ? cs.primary.withOpacity(0.55) : cs.error.withOpacity(0.55));

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: List.generate(4, (i) {
                final char = (i < text.length) ? text[i] : '';
                final filled = char.isNotEmpty;

                return Expanded(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    margin: EdgeInsets.only(right: i == 3 ? 0 : 8),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(
                      color: filled ? cs.surface : cs.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: border, width: 1.2),
                      boxShadow: [
                        BoxShadow(
                          color: cs.shadow.withOpacity(0.04),
                          blurRadius: 10,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: Center(
                      child: Text(
                        char.isEmpty ? '•' : char,
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          color: char.isEmpty ? cs.outlineVariant : cs.onSurface,
                        ),
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
                  Icon(
                    text.isEmpty
                        ? Icons.edit
                        : (valid ? Icons.check_circle_outline : Icons.error_outline),
                    size: 16,
                    color: tone,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      text.isEmpty
                          ? '숫자 4자리를 입력해주세요.'
                          : (valid ? '유효한 번호입니다.' : '숫자 4자리를 입력해주세요.'),
                      style: TextStyle(
                        color: tone,
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            if (text.isEmpty) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.info_outline, size: 14, color: cs.primary.withOpacity(0.9)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '키패드로 4자리를 입력하면 검색할 수 있습니다.',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: cs.primary.withOpacity(0.9),
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
