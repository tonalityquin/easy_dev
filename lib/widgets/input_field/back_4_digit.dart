import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:easydev/widgets/common/common_field.dart';

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

  void _validateInput(String value) {
    if (value.isEmpty || value.length != 4) {
      setState(() {
        _errorText = '정확히 4자리 숫자를 입력하세요.';
      });
    } else {
      setState(() {
        _errorText = null;
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
          onChanged: (value) => _validateInput(value),
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
