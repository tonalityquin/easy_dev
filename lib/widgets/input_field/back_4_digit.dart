import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:easydev/widgets/common/common_field.dart';

/// Class : 번호판 뒷 네 자리(숫자) UI
class NumFieldBack4 extends StatefulWidget {
  final TextEditingController controller;
  final VoidCallback? onTap;
  final bool readOnly;

  const NumFieldBack4({
    super.key,
    required this.controller,
    this.onTap,
    this.readOnly = false, // 기본값 설정
  });

  @override
  NumFieldBack4State createState() => NumFieldBack4State(); // 상태 클래스 public으로 수정
}

class NumFieldBack4State extends State<NumFieldBack4> { // 상태 클래스 public
  String? _errorText; // 에러 메시지 저장

  /// 유효성 검사 함수
  void _validateInput(String value) {
    if (value.isEmpty || value.length != 4) {
      setState(() {
        _errorText = '정확히 4자리 숫자를 입력하세요.';
      });
    } else {
      setState(() {
        _errorText = null; // 에러 없음
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
          maxLength: 4,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          labelText: '4-digit',
          hintText: 'Enter',
          readOnly: widget.readOnly,
          onTap: widget.onTap,
          // 입력 값이 변경될 때마다 유효성 검사 실행
          onChanged: (value) => _validateInput(value),
        ),
        if (_errorText != null) // 에러 메시지 표시
          Padding(
            padding: const EdgeInsets.only(top: 4.0),
            child: Text(
              _errorText!,
              style: const TextStyle(color: Colors.red, fontSize: 12),
            ),
          ),
      ],
    );
  }
}
