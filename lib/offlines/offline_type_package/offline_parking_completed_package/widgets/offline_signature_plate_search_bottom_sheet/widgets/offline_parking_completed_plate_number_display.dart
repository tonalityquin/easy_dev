import 'package:flutter/material.dart';

class ParkingCompletedPlateNumberDisplay extends StatelessWidget {
  final TextEditingController controller;
  final bool Function(String) isValidPlate;

  const ParkingCompletedPlateNumberDisplay({
    super.key,
    required this.controller,
    required this.isValidPlate,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: controller,
          builder: (context, value, child) {
            final valid = isValidPlate(value.text);
            return AnimatedOpacity(
              opacity: value.text.isEmpty ? 0.4 : 1,
              duration: const Duration(milliseconds: 300),
              child: Text(
                value.text.isEmpty ? '번호 입력 대기 중' : value.text,
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w500,
                  color: valid ? Colors.black : Colors.red,
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 8),
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: controller,
          builder: (context, value, child) {
            final valid = isValidPlate(value.text);
            if (value.text.isEmpty) {
              return const SizedBox.shrink();
            }
            return Text(
              valid ? '유효한 번호입니다.' : '숫자 4자리를 입력해주세요.',
              style: TextStyle(
                color: valid ? Colors.green : Colors.red,
                fontSize: 14,
              ),
            );
          },
        ),
      ],
    );
  }
}
