import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../widgets/common/common_plate_field.dart';

/// **NumFieldFront3 위젯**
/// - 3자리 숫자 입력 필드로, 유효성 검사 및 에러 메시지 표시 기능 포함
class NumFieldFront3 extends StatefulWidget {
  final TextEditingController controller;
  final VoidCallback? onTap;
  final bool readOnly;
  final String Function(String)? validator;

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
  String? _errorMessage;

  /// **에러 메시지 설정 함수**
  /// - 상태 변경 중복을 방지하기 위해 기존 값과 비교 후 업데이트
  void _setErrorMessage(String? message) {
    if (_errorMessage != message) {
      setState(() {
        _errorMessage = message;
      });
    }
  }

  /// **입력값 검증**
  void _validateInput(String value) {
    if (widget.validator != null) {
      final result = widget.validator!(value);
      _setErrorMessage(result);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CommonPlateField(
          controller: widget.controller,
          maxLength: 3,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          labelText: '3-digit',
          hintText: 'Enter',
          readOnly: widget.readOnly,
          onTap: widget.onTap,
          onChanged: _validateInput,
        ),
        if (_errorMessage != null)
          Padding(
            padding: const EdgeInsets.only(top: 4.0),
            child: Text(
              _errorMessage!,
              style: const TextStyle(color: Colors.red, fontSize: 12),
            ),
          ),
      ],
    );
  }
}
