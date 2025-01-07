import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:easydev/widgets/common/common_field.dart';

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

  void _validateInput(String value) {
    if (widget.validator != null) {
      setState(() {
        _errorText = widget.validator!(value);
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
          onChanged: (value) => _validateInput(value),
        ),
        if (_errorText != null)
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
