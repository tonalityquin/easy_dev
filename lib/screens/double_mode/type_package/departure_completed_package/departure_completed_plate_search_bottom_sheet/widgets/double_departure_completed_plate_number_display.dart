import 'package:flutter/material.dart';

class DoubleDepartureCompletedPlateNumberDisplay extends StatelessWidget {
  // ✅ 요청 팔레트 (BlueGrey)
  static const Color _base = Color(0xFF546E7A); // BlueGrey 600

  final TextEditingController controller;
  final bool Function(String) isValidPlate;

  const DoubleDepartureCompletedPlateNumberDisplay({
    super.key,
    required this.controller,
    required this.isValidPlate,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, child) {
        final text = value.text;
        final valid = isValidPlate(text);

        final tone = text.isEmpty
            ? Colors.black54
            : (valid ? Colors.green.shade700 : Colors.redAccent);

        final border = text.isEmpty
            ? Colors.black12
            : (valid ? Colors.green.withOpacity(0.45) : Colors.redAccent.withOpacity(0.55));

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 4자리 박스 표시(직관적)
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
                      color: filled ? Colors.white : Colors.grey.shade50,
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
                        char.isEmpty ? '•' : char,
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          color: char.isEmpty ? Colors.black26 : Colors.black87,
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
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // 입력 가이드 (BlueGrey 톤으로 살짝 강조)
            if (text.isEmpty) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Icon(Icons.info_outline, size: 14, color: _base.withOpacity(0.85)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '키패드로 4자리를 입력하면 검색할 수 있습니다.',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: _base.withOpacity(0.85),
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
