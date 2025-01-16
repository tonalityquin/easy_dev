import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../widgets/common/common_plate_field.dart';

/// **NumFieldBack4 위젯**
/// - 4자리 숫자를 입력받는 텍스트 필드 위젯
class NumFieldBack4 extends StatefulWidget {
  final TextEditingController controller;
  final VoidCallback? onTap;
  final bool readOnly;

  const NumFieldBack4({
    super.key,
    required this.controller,
    this.onTap,
    this.readOnly = false,
  });

  @override
  NumFieldBack4State createState() => NumFieldBack4State();
}

class NumFieldBack4State extends State<NumFieldBack4> {
  String? _errorText;

  /// **에러 메시지 설정**
  void _setErrorText(String? message) {
    if (_errorText != message) {
      setState(() {
        _errorText = message;
      });
    }
  }

  /// **입력값 검증 함수**
  void _validateInput(String value) {
    if (value.isEmpty || value.length != 4) {
      _setErrorText('정확히 4자리 숫자를 입력하세요.');
    } else {
      _setErrorText(null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CommonPlateField(
          controller: widget.controller,
          maxLength: 4,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          labelText: '4-digit',
          hintText: 'Enter',
          readOnly: widget.readOnly,
          onTap: widget.onTap,
          onChanged: _validateInput,
        ),
        if (_errorText != null)
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
