import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../widgets/common/common_plate_field.dart';

/// **KorFieldMiddle1 위젯**
/// - 한글 한 글자를 입력받는 텍스트 필드 위젯
/// - 한글 입력만 허용하며, 입력값 유효성 검사 및 경고 메시지 표시
///
/// **매개변수**:
/// - [controller]: 텍스트 값을 관리하는 `TextEditingController` (필수)
/// - [onTap]: 텍스트 필드 탭 이벤트 콜백 (선택적)
/// - [readOnly]: 읽기 전용 여부 설정 (기본값: `false`)
class KorFieldMiddle1 extends StatelessWidget {
  /// **입력 컨트롤러**
  /// - 텍스트 필드 값을 관리
  final TextEditingController controller;

  /// **탭 이벤트 콜백** (선택적)
  /// - 필드가 탭되었을 때 호출
  final VoidCallback? onTap;

  /// **읽기 전용 설정** (기본값: `false`)
  /// - 필드가 읽기 전용인지 여부
  final bool readOnly;

  /// **KorFieldMiddle1 생성자**
  /// - [controller]: 입력값을 관리하는 컨트롤러 (필수)
  /// - [onTap], [readOnly]: 선택적으로 설정 가능
  const KorFieldMiddle1({
    super.key,
    required this.controller,
    this.onTap,
    this.readOnly = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start, // 왼쪽 정렬
      children: [
        /// **공통 입력 필드**
        /// - `CommonPlateField`를 활용하여 한글 입력 필드 구현
        CommonPlateField(
          controller: controller, // 텍스트 값 관리 컨트롤러
          maxLength: 1, // 최대 입력 길이: 1자
          keyboardType: TextInputType.text, // 텍스트 입력 키보드
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'^[ㄱ-ㅎㅏ-ㅣ가-힣]$')), // 한글만 허용
          ],
          labelText: '1-digit', // 레이블 텍스트
          hintText: 'Enter', // 힌트 텍스트
          readOnly: readOnly, // 읽기 전용 여부 설정
          onTap: onTap, // 탭 이벤트 콜백
        ),
        /// **유효성 검사 및 경고 메시지**
        /// - 한글 이외의 입력값에 대해 경고 메시지 출력
        ValueListenableBuilder<TextEditingValue>(
          valueListenable: controller, // 입력값 변경을 감지
          builder: (context, value, child) {
            final input = value.text;

            // 한글이 아닌 값이 입력된 경우 경고 메시지 출력
            if (input.isNotEmpty && !RegExp(r'^[ㄱ-ㅎㅏ-ㅣ가-힣]$').hasMatch(input)) {
              return const Padding(
                padding: EdgeInsets.only(top: 8.0), // 위쪽 여백
                child: Text(
                  '한글만 입력 가능합니다.', // 경고 메시지
                  style: TextStyle(color: Colors.red, fontSize: 12), // 빨간색, 작은 글씨
                ),
              );
            }
            // 유효한 값이 입력된 경우 빈 위젯 반환
            return const SizedBox.shrink();
          },
        ),
      ],
    );
  }
}
