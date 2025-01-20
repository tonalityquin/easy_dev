import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 번호판 입력 필드를 공통으로 처리하는 위젯
/// - 입력 길이 제한, 스타일 커스터마이징, 콜백 등 다양한 기능 제공
class CommonPlateField extends StatelessWidget {
  final TextEditingController controller; // 입력 값을 제어하는 컨트롤러
  final VoidCallback? onTap; // 입력 필드 탭 콜백
  final ValueChanged<String>? onChanged; // 입력 값 변경 콜백
  final bool readOnly; // 읽기 전용 여부
  final String labelText; // 라벨 텍스트
  final TextStyle? labelStyle; // 라벨 스타일
  final String? hintText; // 힌트 텍스트
  final TextStyle? hintStyle; // 힌트 스타일
  final int maxLength; // 입력 길이 제한
  final TextInputType keyboardType; // 키보드 타입
  final List<TextInputFormatter> inputFormatters; // 입력 포맷터

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
    final theme = Theme.of(context).textTheme;

    return SizedBox(
      width: _getWidth(context), // 입력 필드의 동적 너비 계산
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
        textAlign: TextAlign.center,
        inputFormatters: [
          LengthLimitingTextInputFormatter(maxLength), // 입력 길이 제한
          ...inputFormatters, // 추가 포맷터 적용
        ],
        readOnly: readOnly, // 읽기 전용 설정
        decoration: InputDecoration(
          labelText: labelText, // 라벨 텍스트
          labelStyle: _getLabelStyle(theme), // 라벨 스타일
          hintText: hintText, // 힌트 텍스트
          hintStyle: _getHintStyle(theme), // 힌트 스타일
          contentPadding: const EdgeInsets.only(top: 20.0), // 입력 필드 패딩
          enabledBorder: const UnderlineInputBorder(
            borderSide: BorderSide(color: Colors.black, width: 2.0),
          ),
          focusedBorder: const UnderlineInputBorder(
            borderSide: BorderSide(color: Colors.blue, width: 2.0),
          ),
        ),
        style: theme.bodyLarge?.copyWith(
          fontSize: 18,
          fontWeight: FontWeight.bold,
        ),
        onTap: () {
          if (onTap != null) {
            onTap!(); // 추가 콜백 호출
          }
          controller.clear(); // 입력 필드 초기화
        },
        onChanged: onChanged, // 입력 값 변경 시 호출
      ),
    );
  }

  /// 라벨 스타일 반환
  /// - 사용자 정의 스타일이 없으면 기본 스타일 적용
  TextStyle _getLabelStyle(TextTheme theme) {
    return labelStyle ??
        (theme.bodyLarge ?? const TextStyle()).copyWith(
          fontSize: 18,
          fontWeight: FontWeight.bold,
          color: Colors.grey,
        );
  }

  /// 힌트 스타일 반환
  /// - 사용자 정의 스타일이 없으면 기본 스타일 적용
  TextStyle _getHintStyle(TextTheme theme) {
    return hintStyle ??
        (theme.bodyMedium ?? const TextStyle()).copyWith(
          color: Colors.grey,
        );
  }

  /// 입력 필드의 너비 계산
  /// - `maxLength`에 따라 동적으로 너비 결정
  double _getWidth(BuildContext context) {
    if (maxLength == 1) return 70;
    if (maxLength == 2) return MediaQuery.of(context).size.width * 0.25;
    if (maxLength == 3) return 100;
    if (maxLength == 4) return MediaQuery.of(context).size.width * 0.4;
    return MediaQuery.of(context).size.width * 0.5;
  }
}
