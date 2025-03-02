import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../widgets/common/common_plate_field.dart';

/// **NumFieldFront2 위젯**
/// - 2자리 숫자 입력 필드로, 유효성 검사와 에러 메시지 표시 기능 포함
class NumFieldFront2 extends StatefulWidget {
  final TextEditingController controller;
  final VoidCallback? onTap;
  final String? Function(String?)? validator;

  const NumFieldFront2({
    super.key,
    required this.controller,
    this.onTap,
    this.validator,
  });

  @override
  NumFieldFront2State createState() => NumFieldFront2State();
}

class NumFieldFront2State extends State<NumFieldFront2> {
  String? _errorText;

  /// **에러 메시지 설정 함수**
  /// - 중복 상태 변경을 방지하며 에러 메시지를 업데이트
  void _setErrorText(String? message) {
    if (_errorText != message) {
      setState(() {
        _errorText = message;
      });
    }
  }

  /// **입력값 검증 및 에러 메시지 설정**
  void _validateInput(String value) {
    if (widget.validator != null) {
      _setErrorText(widget.validator!(value));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CommonPlateField(
          controller: widget.controller,
          maxLength: 2,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          labelText: '2-digit',
          hintText: 'Enter',
          onTap: widget.onTap,
          onChanged: _validateInput,
        ),
        if (_errorText != null)
          Padding(
            padding: const EdgeInsets.only(top: 4.0),
            child: Text(
              _errorText!,
              style: const TextStyle(color: Colors.red, fontSize: 12.0),
            ),
          ),
      ],
    );
  }
}
