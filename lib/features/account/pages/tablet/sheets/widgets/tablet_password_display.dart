import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class TabletPasswordDisplay extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final bool allowCopy;
  final bool enableMonospace;

  const TabletPasswordDisplay({
    super.key,
    required this.controller,
    this.label = '비밀번호',
    this.allowCopy = true,
    this.enableMonospace = false,
  });

  Future<void> _copyToClipboard() async {
    await Clipboard.setData(ClipboardData(text: controller.text));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return TextField(
      controller: controller,
      readOnly: true,
      enableSuggestions: false,
      autocorrect: false,
      enableInteractiveSelection: true,
      style: TextStyle(
        color: cs.onSurface,
        fontFeatures: enableMonospace ? [FontFeature.tabularFigures()] : null,
        letterSpacing: 0.5,
      ),
      decoration: InputDecoration(
        labelText: label,
        helperText: '읽기 전용(자동 생성). 복사해서 전달하세요.',
        floatingLabelStyle: TextStyle(
          color: cs.primary,
          fontWeight: FontWeight.w700,
        ),
        prefixIcon: Icon(Icons.lock, color: cs.onSurfaceVariant),
        suffixIcon: allowCopy
            ? IconButton(
          tooltip: '복사',
          onPressed: _copyToClipboard,
          icon: Icon(Icons.copy, color: cs.onSurfaceVariant),
        )
            : null,
        filled: true,
        fillColor: cs.surfaceVariant.withOpacity(.45),
        isDense: true,
        contentPadding:
        const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: cs.outlineVariant.withOpacity(.75)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: cs.primary, width: 1.3),
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
        ),
      ),
    );
  }
}
