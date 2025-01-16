import 'package:flutter/material.dart';

/// **LocationField 위젯**
/// - 주차 구역 등의 위치 정보를 입력하거나 표시하는 필드
/// - 읽기 전용 상태로 표시하며, 선택 시 콜백 이벤트를 실행 가능
class LocationField extends StatelessWidget {
  final TextEditingController controller; // 입력 컨트롤러
  final VoidCallback? onTap; // 탭 이벤트 콜백
  final bool readOnly; // 읽기 전용 여부
  final double widthFactor; // 필드 너비 비율

  const LocationField({
    super.key,
    required this.controller,
    this.onTap,
    this.readOnly = false,
    this.widthFactor = 0.7,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    final screenWidth = MediaQuery.of(context).size.width;

    return SizedBox(
      width: screenWidth * widthFactor, // 필드 너비 설정
      child: TextField(
        controller: controller,
        // 입력값 관리
        readOnly: true,
        // 항상 읽기 전용
        textAlign: TextAlign.center,
        // 텍스트 중앙 정렬
        style: theme.bodyLarge?.copyWith(
          fontSize: 18,
          fontWeight: FontWeight.bold,
          color: controller.text.isEmpty ? Colors.grey : Colors.black, // 빈 텍스트일 경우 회색
        ),
        decoration: InputDecoration(
          hintText: controller.text.isEmpty ? '미지정' : null, // 빈 텍스트일 경우 힌트 표시
          hintStyle: theme.bodyLarge?.copyWith(
            fontSize: 18,
            color: Colors.grey,
          ),
          enabledBorder: const UnderlineInputBorder(
            borderSide: BorderSide(color: Colors.black, width: 2.0),
          ),
        ),
        onTap: readOnly ? null : onTap, // 읽기 전용이 아닌 경우에만 탭 이벤트 처리
      ),
    );
  }
}
