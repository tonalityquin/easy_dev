import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:easydev/widgets/common/common_field.dart';

/// Class : 번호판 앞 세 자리(숫자) UI
class NumFieldFront3 extends StatefulWidget {
  final TextEditingController controller;
  final VoidCallback? onTap;
  final bool readOnly;
  final String Function(String)? validator; // 유효성 검증 함수 추가

  const NumFieldFront3({
    super.key,
    required this.controller,
    this.onTap,
    this.readOnly = false, // 기본값 설정
    this.validator, // 유효성 검증 함수 추가
  });

  @override
  State<NumFieldFront3> createState() => _NumFieldFront3State();
}

class _NumFieldFront3State extends State<NumFieldFront3> {
  String? errorMessage; // 에러 메시지 상태 관리

  // 검증 로직 호출 및 에러 메시지 설정
  void _validateInput(String value) {
    if (widget.validator != null) {
      final result = widget.validator!(value);
      setState(() {
        errorMessage = result; // 에러 메시지 설정
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CommonField(
          controller: widget.controller,
          maxLength: 3,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          labelText: '3-digit',
          hintText: 'Enter',
          readOnly: widget.readOnly,
          onTap: widget.onTap,
          // 입력값 변경 시 검증 로직 호출
          onChanged: _validateInput,
        ),
        if (errorMessage != null) // 에러 메시지가 있을 경우 표시
          Padding(
            padding: const EdgeInsets.only(top: 4.0),
            child: Text(
              errorMessage!,
              style: TextStyle(color: Colors.red, fontSize: 12),
            ),
          ),
      ],
    );
  }
}
