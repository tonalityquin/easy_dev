import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:easydev/widgets/common/common_field.dart';

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
  String? errorMessage;

  void _validateInput(String value) {
    if (widget.validator != null) {
      final result = widget.validator!(value);
      setState(() {
        errorMessage = result;
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
          onChanged: _validateInput,
        ),
        if (errorMessage != null)
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
