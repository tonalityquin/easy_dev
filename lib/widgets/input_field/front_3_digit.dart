import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../widgets/common/common_plate_field.dart';

/// **NumFieldFront3 위젯**
/// - 3자리 숫자를 입력받는 필드로, 입력값 검증 및 에러 메시지 표시 기능 포함
class NumFieldFront3 extends StatefulWidget {
  /// **입력 컨트롤러**
  /// - 필드의 텍스트를 관리
  final TextEditingController controller;

  /// **탭 이벤트 콜백** (선택적)
  /// - 필드가 탭되었을 때 호출
  final VoidCallback? onTap;

  /// **읽기 전용 설정** (기본값: false)
  /// - 필드가 읽기 전용인지 여부
  final bool readOnly;

  /// **유효성 검사 함수** (선택적)
  /// - 입력값의 유효성을 검증하는 함수
  /// - 반환값: 에러 메시지 또는 `null`(유효할 경우)
  final String Function(String)? validator;

  /// **NumFieldFront3 생성자**
  /// - [controller]: 텍스트 입력값을 관리하는 컨트롤러 (필수)
  /// - [onTap], [readOnly], [validator]: 선택적으로 설정 가능
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

/// **_NumFieldFront3State 클래스**
/// - 입력값 상태와 에러 메시지를 관리
class _NumFieldFront3State extends State<NumFieldFront3> {
  /// **에러 메시지 상태**
  /// - 입력값이 유효하지 않을 경우 설정
  String? errorMessage;

  /// **입력값 검증**
  /// - [value]: 사용자가 입력한 값
  /// - 유효성 검사 결과에 따라 에러 메시지 업데이트
  void _validateInput(String value) {
    if (widget.validator != null) {
      final result = widget.validator!(value); // 유효성 검사 결과
      setState(() {
        errorMessage = result; // 에러 메시지 업데이트
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start, // 왼쪽 정렬
      children: [
        /// **공통 입력 필드**
        /// - 3자리 숫자 입력 필드를 제공
        CommonPlateField(
          controller: widget.controller,
          // 입력값 관리 컨트롤러
          maxLength: 3,
          // 최대 입력 길이: 3자리
          keyboardType: TextInputType.number,
          // 숫자 입력 키패드
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          // 숫자만 입력 허용
          labelText: '3-digit',
          // 필드 라벨 텍스트
          hintText: 'Enter',
          // 입력 힌트 텍스트
          readOnly: widget.readOnly,
          // 읽기 전용 여부
          onTap: widget.onTap,
          // 탭 이벤트 콜백
          onChanged: _validateInput, // 입력값 변경 시 유효성 검사 호출
        ),

        /// **에러 메시지 표시**
        /// - 입력값이 유효하지 않을 경우 메시지 출력
        if (errorMessage != null)
          Padding(
            padding: const EdgeInsets.only(top: 4.0), // 메시지 상단 여백
            child: Text(
              errorMessage!, // 에러 메시지 내용
              style: const TextStyle(color: Colors.red, fontSize: 12), // 빨간색, 작은 글씨
            ),
          ),
      ],
    );
  }
}
