import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:easydev/widgets/common/common_field.dart';

// NumFieldFront3 위젯 클래스
// 숫자 3자리를 입력받는 필드를 구현합니다.
class NumFieldFront3 extends StatefulWidget {
  // 입력 컨트롤러: 필드의 텍스트를 제어
  final TextEditingController controller;

  // 필드가 탭되었을 때 실행할 콜백 함수
  final VoidCallback? onTap;

  // 필드의 읽기 전용 여부 설정 (기본값: false)
  final bool readOnly;

  // 입력값 검증 함수: 유효성 검사 로직을 외부에서 정의 가능
  final String Function(String)? validator;

  // NumFieldFront3 생성자
  const NumFieldFront3({
    super.key,
    required this.controller,
    this.onTap,
    this.readOnly = false,
    this.validator,
  });

  @override
  State<NumFieldFront3> createState() => _NumFieldFront3State();
}

class _NumFieldFront3State extends State<NumFieldFront3> {
  // 에러 메시지: 입력값이 유효하지 않을 때 표시
  String? errorMessage;

  // 입력값 검증 로직 실행
  void _validateInput(String value) {
    if (widget.validator != null) {
      // 입력값을 검증하고 에러 메시지를 설정
      final result = widget.validator!(value);
      setState(() {
        errorMessage = result;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start, // 왼쪽 정렬
      children: [
        // 공통 입력 필드 (CommonField 위젯 사용)
        CommonField(
          controller: widget.controller,
          // 텍스트 컨트롤러
          maxLength: 3,
          // 최대 입력 길이: 3자리
          keyboardType: TextInputType.number,
          // 숫자 입력 키패드
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          // 숫자만 입력 허용
          labelText: '3-digit',
          // 필드의 레이블 텍스트
          hintText: 'Enter',
          // 입력 힌트 텍스트
          readOnly: widget.readOnly,
          // 읽기 전용 여부
          onTap: widget.onTap,
          // 탭 동작
          onChanged: _validateInput, // 입력값 변경 시 검증
        ),
        // 에러 메시지 표시
        if (errorMessage != null)
          Padding(
            padding: const EdgeInsets.only(top: 4.0), // 메시지 상단 여백
            child: Text(
              errorMessage!, // 에러 메시지 내용
              style: TextStyle(color: Colors.red, fontSize: 12), // 빨간색, 작은 글씨
            ),
          ),
      ],
    );
  }
}
