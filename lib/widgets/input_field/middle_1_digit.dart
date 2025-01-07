import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:easydev/widgets/common/common_field.dart';

/// `KorFieldMiddle1`
///
/// 한글 1글자를 입력받는 텍스트 필드 위젯.
/// - 한글 입력만 허용 (Validation 포함).
/// - `CommonField` 위젯을 활용.
/// - 텍스트 입력 시, 잘못된 값에 대해 경고 메시지를 표시.
///
/// [controller]: 텍스트 필드 값을 제어하는 `TextEditingController`
/// [onTap]: 텍스트 필드가 탭되었을 때 호출되는 콜백 (선택적).
/// [readOnly]: 텍스트 필드를 읽기 전용으로 설정 (기본값: `false`).
class KorFieldMiddle1 extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback? onTap;
  final bool readOnly;

  // 생성자
  const KorFieldMiddle1({
    super.key,
    required this.controller, // 텍스트 필드 값 관리
    this.onTap, // 탭 콜백 (선택적)
    this.readOnly = false, // 읽기 전용 모드 기본값은 `false`
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start, // 왼쪽 정렬
      children: [
        // 공통 필드(CommonField) 위젯 활용
        CommonField(
          controller: controller,
          maxLength: 1,
          // 최대 입력 길이: 1자
          keyboardType: TextInputType.text,
          // 키보드 타입: 텍스트
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'^[ㄱ-ㅎㅏ-ㅣ가-힣]$')), // 한글만 허용
          ],
          labelText: '1-digit',
          // 레이블 텍스트
          hintText: 'Enter',
          // 힌트 텍스트
          readOnly: readOnly,
          // 읽기 전용 여부
          onTap: onTap, // 탭 콜백
        ),
        // 입력 값 유효성 검사 및 경고 메시지 표시
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: controller, // 입력 값 변경을 감지
          builder: (context, value, child) {
            final input = value.text;
            // 입력 값이 한글이 아닌 경우 경고 메시지 표시
            if (input.isNotEmpty && !RegExp(r'^[ㄱ-ㅎㅏ-ㅣ가-힣]$').hasMatch(input)) {
              return const Padding(
                padding: EdgeInsets.only(top: 8.0), // 위쪽 여백 추가
                child: Text(
                  '한글만 입력 가능합니다.', // 경고 메시지
                  style: TextStyle(color: Colors.red, fontSize: 12), // 스타일: 빨간색, 작은 글씨
                ),
              );
            }
            // 입력 값이 비어있거나 유효한 경우 빈 위젯 반환
            return const SizedBox.shrink();
          },
        ),
      ],
    );
  }
}
