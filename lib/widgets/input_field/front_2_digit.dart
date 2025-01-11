import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../widgets/common/common_plate_field.dart';

/// **NumFieldFront2 위젯**
/// - 2자리 숫자를 입력받는 필드로, 유효성 검사와 에러 메시지 표시 기능을 포함
/// - 상태 관리를 통해 입력값의 유효성을 확인하고 에러 메시지를 업데이트
class NumFieldFront2 extends StatefulWidget {
  /// **컨트롤러**
  /// - 입력된 텍스트를 관리
  final TextEditingController controller;

  /// **탭 이벤트**
  /// - 필드가 탭되었을 때 실행되는 콜백 함수 (선택적)
  final VoidCallback? onTap;

  /// **유효성 검사 함수**
  /// - 입력값의 유효성을 검증하는 함수 (선택적)
  /// - 반환값: 유효하지 않을 경우 에러 메시지, 유효할 경우 `null`
  final String? Function(String?)? validator;

  /// **NumFieldFront2 생성자**
  /// - [controller]: 입력값을 관리하는 컨트롤러 (필수)
  /// - [onTap], [validator]: 선택적으로 설정 가능
  const NumFieldFront2({
    super.key,
    required this.controller,
    this.onTap,
    this.validator,
  });

  @override
  NumFieldFront2State createState() => NumFieldFront2State();
}

/// **NumFieldFront2State 클래스**
/// - 입력값 상태와 유효성 검사를 관리
/// - 에러 메시지를 업데이트하고 표시
class NumFieldFront2State extends State<NumFieldFront2> {
  /// **에러 메시지 상태**
  /// - 유효하지 않은 입력값에 대한 에러 메시지
  String? _errorText;

  /// **입력값 검증 및 에러 메시지 업데이트**
  /// - [value]: 사용자가 입력한 값
  /// - 유효성 검사 결과를 에러 메시지로 설정
  void _validateInput(String value) {
    if (widget.validator != null) {
      setState(() {
        _errorText = widget.validator!(value); // 유효성 검사 결과를 에러 메시지로 설정
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start, // 좌측 정렬
      children: [
        /// **공통 입력 필드 위젯**
        /// - 2자리 숫자 입력 필드를 제공
        /// - `CommonPlateField`를 사용하여 기본 스타일링 및 입력 제한 처리
        CommonPlateField(
          controller: widget.controller,
          // 텍스트 입력값 컨트롤러
          maxLength: 2,
          // 최대 입력 길이: 2자리
          keyboardType: TextInputType.number,
          // 숫자 키패드 활성화
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          // 숫자만 허용
          labelText: '2-digit',
          // 라벨 텍스트
          hintText: 'Enter',
          // 힌트 텍스트
          onTap: widget.onTap,
          // 필드 탭 이벤트
          onChanged: (value) => _validateInput(value), // 입력 변경 시 유효성 검사 호출
        ),

        /// **에러 메시지 표시**
        /// - `_errorText`가 `null`이 아닌 경우 에러 메시지를 출력
        if (_errorText != null)
          Padding(
            padding: const EdgeInsets.only(top: 4.0), // 에러 메시지와 필드 간격 설정
            child: Text(
              _errorText!, // 유효성 검사 결과 메시지
              style: const TextStyle(color: Colors.red, fontSize: 12.0), // 에러 메시지 스타일
            ),
          ),
      ],
    );
  }
}
