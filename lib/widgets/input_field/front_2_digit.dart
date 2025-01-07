import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:easydev/widgets/common/common_field.dart';

/// NumFieldFront2 위젯
/// 2자리 숫자를 입력받는 필드로, 유효성 검사와 에러 메시지 표시를 포함합니다.
class NumFieldFront2 extends StatefulWidget {
  /// 컨트롤러: 입력된 텍스트를 관리합니다.
  final TextEditingController controller;

  /// 탭 이벤트: 필드가 탭되었을 때 실행되는 콜백 함수 (옵션).
  final VoidCallback? onTap;

  /// 유효성 검사 함수: 입력값의 유효성을 검증하는 함수 (옵션).
  final String? Function(String?)? validator;

  /// NumFieldFront2 생성자
  /// [controller]: 필수적으로 전달해야 하는 TextEditingController.
  /// [onTap], [validator]: 선택적으로 전달 가능.
  const NumFieldFront2({
    super.key,
    required this.controller,
    this.onTap,
    this.validator,
  });

  @override
  NumFieldFront2State createState() => NumFieldFront2State();
}

/// NumFieldFront2State 클래스
/// 상태 관리를 통해 유효성 검사를 수행하고 에러 메시지를 표시합니다.
class NumFieldFront2State extends State<NumFieldFront2> {
  /// 현재 에러 메시지 상태
  String? _errorText;

  /// 입력값을 검증하고 에러 메시지를 업데이트합니다.
  /// [value]: 사용자가 입력한 값.
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
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        /// 공통 입력 필드 위젯
        /// - 최대 입력 길이: 2자리
        /// - 입력 타입: 숫자만 입력 가능
        CommonField(
          controller: widget.controller,
          maxLength: 2,
          // 최대 2자리 숫자만 입력 가능
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
        // 에러 메시지 표시
        if (_errorText != null)
          Padding(
            padding: const EdgeInsets.only(top: 4.0),
            child: Text(
              _errorText!, // 유효성 검사 결과 메시지
              style: TextStyle(color: Colors.red, fontSize: 12.0), // 빨간색 텍스트
            ),
          ),
      ],
    );
  }
}
