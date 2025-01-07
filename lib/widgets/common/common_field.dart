// Flutter Material Design 패키지와 입력 포맷팅 패키지 가져오기
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// CommonField 위젯
/// 공통 입력 필드로 사용되며, 다양한 옵션으로 사용자 입력 처리를 지원
class CommonField extends StatelessWidget {
  // 필드 컨트롤러 (입력값 제어)
  final TextEditingController controller;

  // 필드가 탭될 때 실행되는 콜백 함수 (선택적)
  final VoidCallback? onTap;

  // 입력값 변경 시 실행되는 콜백 함수 (선택적)
  final ValueChanged<String>? onChanged;

  // 읽기 전용 여부
  final bool readOnly;

  // 라벨 텍스트
  final String labelText;

  // 라벨 텍스트 스타일 (선택적)
  final TextStyle? labelStyle;

  // 힌트 텍스트 (입력 필드 배경에 나타나는 텍스트)
  final String? hintText;

  // 힌트 텍스트 스타일 (선택적)
  final TextStyle? hintStyle;

  // 최대 입력 길이
  final int maxLength;

  // 키보드 타입 (숫자 입력, 텍스트 입력 등)
  final TextInputType keyboardType;

  // 입력 포맷터 (입력값 제한 규칙 설정)
  final List<TextInputFormatter> inputFormatters;

  // CommonField 생성자
  const CommonField({
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
      // 필드의 폭을 계산 (maxLength에 따라 동적으로 변경)
      width: _getWidth(context),
      child: TextField(
        // 컨트롤러 설정
        controller: controller,
        // 키보드 타입 설정
        keyboardType: keyboardType,
        // 텍스트 가운데 정렬
        textAlign: TextAlign.center,
        // 입력 포맷터 적용 (길이 제한 포함)
        inputFormatters: [
          LengthLimitingTextInputFormatter(maxLength),
          ...inputFormatters, // 추가 입력 포맷터 적용
        ],
        // 읽기 전용 설정
        readOnly: readOnly,
        // 입력 필드 스타일 정의
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
        // 입력 필드 텍스트 스타일
        style: theme.bodyLarge?.copyWith(
          fontSize: 18,
          fontWeight: FontWeight.bold,
        ),
        // 필드가 탭되었을 때 동작 정의
        onTap: () {
          // onTap 콜백 함수 실행
          if (onTap != null) {
            onTap!();
          }
          // 입력 필드가 비어 있지 않으면 초기화
          if (controller.text.isNotEmpty) {
            controller.clear();
          }
        },
        // 입력값 변경 시 동작 정의
        onChanged: onChanged,
      ),
    );
  }

  /// 입력 필드의 폭을 계산
  /// maxLength 값에 따라 필드의 크기를 동적으로 조정
  double _getWidth(BuildContext context) {
    if (maxLength == 1) return 70; // 한 자리 입력일 경우 고정 크기
    if (maxLength == 2) return MediaQuery.of(context).size.width * 0.25;
    if (maxLength == 3) return 100; // 세 자리 입력일 경우 고정 크기
    if (maxLength == 4) return MediaQuery.of(context).size.width * 0.4;
    return MediaQuery.of(context).size.width * 0.5; // 기본 크기
  }
}
