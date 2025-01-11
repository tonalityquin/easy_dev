// Flutter Material Design 패키지와 입력 포맷팅 패키지 가져오기
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// **CommonPlateField 위젯**
/// - 차량 번호판 입력과 같은 다양한 입력 필드로 재사용 가능
/// - 동적 크기와 다양한 스타일링, 입력 처리 옵션 제공
class CommonPlateField extends StatelessWidget {
  // **필드 컨트롤러** (입력값 제어)
  final TextEditingController controller;

  // **필드 탭 콜백 함수** (선택적)
  final VoidCallback? onTap;

  // **입력값 변경 콜백 함수** (선택적)
  final ValueChanged<String>? onChanged;

  // **읽기 전용 여부**
  final bool readOnly;

  // **라벨 텍스트** (필드 위에 표시되는 텍스트)
  final String labelText;

  // **라벨 텍스트 스타일** (선택적)
  final TextStyle? labelStyle;

  // **힌트 텍스트** (필드 내부에 배경으로 나타나는 텍스트)
  final String? hintText;

  // **힌트 텍스트 스타일** (선택적)
  final TextStyle? hintStyle;

  // **최대 입력 길이**
  final int maxLength;

  // **키보드 타입** (숫자, 텍스트 등)
  final TextInputType keyboardType;

  // **입력 포맷터** (입력값 제한 규칙 설정)
  final List<TextInputFormatter> inputFormatters;

  /// **CommonPlateField 생성자**
  /// - [controller]: 입력값을 제어하는 텍스트 컨트롤러
  /// - [maxLength]: 최대 입력 길이
  /// - [keyboardType]: 키보드 입력 타입
  /// - [inputFormatters]: 입력값 제한 규칙
  /// - 선택적 매개변수로 콜백(onTap, onChanged), 스타일링(labelText, labelStyle, hintText, hintStyle) 제공
  const CommonPlateField({
    super.key,
    required this.controller,
    required this.maxLength,
    required this.keyboardType,
    required this.inputFormatters,
    this.onTap,
    this.onChanged,
    this.readOnly = false,
    this.labelText = '',
    this.labelStyle,
    this.hintText,
    this.hintStyle,
  });

  @override
  Widget build(BuildContext context) {
    // 현재 테마에서 텍스트 스타일 가져오기
    final theme = Theme.of(context).textTheme;

    return SizedBox(
      // 입력 필드의 폭을 계산 (maxLength에 따라 동적으로 변경)
      width: _getWidth(context),
      child: TextField(
        // **컨트롤러 설정**
        controller: controller,
        // **키보드 타입 설정**
        keyboardType: keyboardType,
        // **텍스트 가운데 정렬**
        textAlign: TextAlign.center,
        // **입력 포맷터 적용** (길이 제한 포함)
        inputFormatters: [
          LengthLimitingTextInputFormatter(maxLength),
          ...inputFormatters, // 추가 입력 포맷터 적용
        ],
        // **읽기 전용 설정**
        readOnly: readOnly,
        // **입력 필드 스타일 정의**
        decoration: InputDecoration(
          labelText: labelText,
          labelStyle: labelStyle ??
              theme.bodyLarge?.copyWith(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.grey,
              ),
          hintText: hintText,
          hintStyle: hintStyle ??
              theme.bodyMedium?.copyWith(
                color: Colors.grey,
              ),
          contentPadding: const EdgeInsets.only(top: 20.0),
          enabledBorder: const UnderlineInputBorder(
            borderSide: BorderSide(color: Colors.black, width: 2.0),
          ),
          focusedBorder: const UnderlineInputBorder(
            borderSide: BorderSide(color: Colors.blue, width: 2.0),
          ),
        ),
        // **입력 필드 텍스트 스타일**
        style: theme.bodyLarge?.copyWith(
          fontSize: 18,
          fontWeight: FontWeight.bold,
        ),
        // **필드 탭 시 동작 정의**
        onTap: () {
          if (onTap != null) {
            onTap!(); // onTap 콜백 함수 실행
          }
          if (controller.text.isNotEmpty) {
            controller.clear(); // 입력 필드 초기화
          }
        },
        // **입력값 변경 시 동작 정의**
        onChanged: onChanged,
      ),
    );
  }

  /// **입력 필드의 폭 계산**
  /// - maxLength 값에 따라 필드의 크기를 동적으로 조정
  /// - [context]: BuildContext
  /// - 반환값: 필드의 폭 (double)
  double _getWidth(BuildContext context) {
    if (maxLength == 1) return 70; // 한 자리 입력일 경우 고정 크기
    if (maxLength == 2) return MediaQuery.of(context).size.width * 0.25; // 2자리
    if (maxLength == 3) return 100; // 세 자리 입력일 경우 고정 크기
    if (maxLength == 4) return MediaQuery.of(context).size.width * 0.4; // 4자리
    return MediaQuery.of(context).size.width * 0.5; // 기본 크기
  }
}
