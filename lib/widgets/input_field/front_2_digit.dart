import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:easydev/widgets/common/common_field.dart';

/// Class : 번호판 앞 두 자리(숫자) UI
class NumFieldFront2 extends StatefulWidget {
  final TextEditingController controller;
  final VoidCallback? onTap;
  final String? Function(String?)? validator; // 입력값 검증 함수

  const NumFieldFront2({
    super.key,
    required this.controller,
    this.onTap,
    this.validator,
  });

  @override
  NumFieldFront2State createState() => NumFieldFront2State(); // 상태 클래스 public으로 수정
}

class NumFieldFront2State extends State<NumFieldFront2> { // 상태 클래스 public
  String? _errorText; // 에러 메시지 상태 관리

  void _validateInput(String value) {
    if (widget.validator != null) {
      setState(() {
        _errorText = widget.validator!(value); // 검증 함수 결과에 따라 에러 메시지 설정
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
          maxLength: 2,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          labelText: '2-digit',
          hintText: 'Enter',
          onTap: widget.onTap,
          // 입력값 변경 시 검증 수행
          onChanged: (value) => _validateInput(value),
        ),
        if (_errorText != null) // 에러 메시지 표시
          Padding(
            padding: const EdgeInsets.only(top: 4.0),
            child: Text(
              _errorText!,
              style: TextStyle(color: Colors.red, fontSize: 12.0),
            ),
          ),
      ],
    );
  }
}
