import 'package:flutter/material.dart';

/// **LocationField 위젯**
/// - 주차 구역 등의 위치 정보를 입력하거나 표시하는 필드
/// - 읽기 전용 상태로 표시하며, 선택 시 콜백 이벤트를 실행 가능
class LocationField extends StatefulWidget {
  /// **입력 컨트롤러**
  /// - 선택된 값을 관리
  final TextEditingController controller;

  /// **탭 이벤트 콜백** (선택적)
  /// - 필드가 탭되었을 때 실행
  final VoidCallback? onTap;

  /// **읽기 전용 설정** (기본값: false)
  /// - 필드가 읽기 전용인지 여부
  final bool readOnly;

  /// **화면 가로 폭 비율** (기본값: 0.7)
  /// - 필드의 너비를 화면의 일정 비율로 조정 (0.0 ~ 1.0)
  final double widthFactor;

  /// **LocationField 생성자**
  /// - [controller]: 선택된 값을 관리하는 컨트롤러 (필수)
  /// - [onTap], [readOnly], [widthFactor]: 선택적으로 설정 가능
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

/// **_LocationFieldState 클래스**
/// - 필드 상태를 관리하고, UI를 동적으로 업데이트
class _LocationFieldState extends State<LocationField> {
  @override
  Widget build(BuildContext context) {
    // 현재 테마와 화면 너비 가져오기
    final theme = Theme.of(context).textTheme;
    final screenWidth = MediaQuery.of(context).size.width;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start, // 왼쪽 정렬
      children: [
        GestureDetector(
          // 읽기 전용이 아닌 경우에만 탭 이벤트 실행
          onTap: widget.readOnly
              ? null
              : () {
            if (widget.onTap != null) {
              widget.onTap!(); // 추가 콜백 호출
            }
          },
          child: Container(
            width: screenWidth * widget.widthFactor, // 필드 너비를 화면 비율로 설정
            child: TextField(
              controller: widget.controller, // 입력값 관리 컨트롤러
              readOnly: true, // 항상 읽기 전용으로 설정
              textAlign: TextAlign.center, // 텍스트 중앙 정렬
              style: theme.bodyLarge?.copyWith(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: widget.controller.text.isEmpty ? Colors.grey : Colors.black, // 빈 텍스트일 경우 회색
              ),
              decoration: InputDecoration(
                hintText: widget.controller.text.isEmpty ? '미지정' : null, // 텍스트가 없을 경우 힌트 표시
                hintStyle: theme.bodyLarge?.copyWith(
                  fontSize: 18,
                  color: Colors.grey,
                ),
                enabledBorder: const UnderlineInputBorder(
                  borderSide: BorderSide(color: Colors.black, width: 2.0), // 검은색 밑줄
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
