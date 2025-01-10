import 'package:flutter/material.dart';

class LocationField extends StatefulWidget {
  final TextEditingController controller; // 선택된 값을 관리하는 컨트롤러
  final VoidCallback? onTap; // 탭 이벤트 콜백
  final bool readOnly; // 읽기 전용 여부
  final double widthFactor; // 화면 가로 폭 비율 (0.0 ~ 1.0)

  const LocationField({
    super.key,
    required this.controller,
    this.onTap,
    this.readOnly = false,
    this.widthFactor = 0.7, // 기본값: 화면 전체 너비의 70%
  });

  @override
  State<LocationField> createState() => _LocationFieldState();
}

class _LocationFieldState extends State<LocationField> {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    final screenWidth = MediaQuery.of(context).size.width;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: widget.readOnly
              ? null
              : () {
            // 추가 콜백 호출
            if (widget.onTap != null) {
              widget.onTap!();
            }
          },
          child: Container(
            width: screenWidth * widget.widthFactor,
            child: TextField(
              controller: widget.controller,
              readOnly: true,
              textAlign: TextAlign.center,
              style: theme.bodyLarge?.copyWith(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: widget.controller.text.isEmpty ? Colors.grey : Colors.black,
              ),
              decoration: InputDecoration(
                hintText: widget.controller.text.isEmpty ? '미지정' : null,
                hintStyle: theme.bodyLarge?.copyWith(
                  fontSize: 18,
                  color: Colors.grey,
                ),
                enabledBorder: const UnderlineInputBorder(
                  borderSide: BorderSide(color: Colors.black, width: 2.0),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
