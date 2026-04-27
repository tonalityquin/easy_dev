
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class BillTypeInputSection extends StatelessWidget {
  final TextEditingController controller;

  
  final String label;
  final String hint;
  final String? errorText;
  final bool enabled;
  final bool autofocus;
  final TextInputAction textInputAction;
  final VoidCallback? onEditingComplete;
  final ValueChanged<String>? onChanged;

  const BillTypeInputSection({
    super.key,
    required this.controller,
    this.label = '변동 정산 유형',
    this.hint = '예: 기본 요금',
    this.errorText,
    this.enabled = true,
    this.autofocus = false,
    this.textInputAction = TextInputAction.next,
    this.onEditingComplete,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    
    
    
    final focusColor = cs.primary; 
    final labelFocusColor = cs.primary; 
    final enabledBorderColor = cs.outlineVariant.withOpacity(0.75);
    final errorColor = cs.error;

    
    
    final labelStyle = theme.textTheme.bodySmall?.copyWith(
      color: cs.onSurfaceVariant,
      fontWeight: FontWeight.w600,
    );

    final hintStyle = theme.textTheme.bodyMedium?.copyWith(
      color: cs.onSurfaceVariant.withOpacity(0.75),
      fontWeight: FontWeight.w400,
    );

    return TextFormField(
      controller: controller,
      enabled: enabled,
      autofocus: autofocus,
      textInputAction: textInputAction,
      maxLines: 1,
      autocorrect: false,
      enableSuggestions: false,
      inputFormatters: [
        FilteringTextInputFormatter.deny(RegExp(r'[\n\r]')),
      ],
      style: theme.textTheme.bodyMedium?.copyWith(
        
        color: cs.onSurface,
      ),
      cursorColor: focusColor,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        errorText: errorText,

        
        labelStyle: labelStyle,
        hintStyle: hintStyle,

        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: enabledBorderColor),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: const BorderRadius.all(Radius.circular(8)),
          borderSide: BorderSide(color: focusColor, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: errorColor, width: 1.5),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: errorColor, width: 2),
        ),

        
        floatingLabelStyle: TextStyle(
          color: labelFocusColor,
          fontWeight: FontWeight.w700,
        ),

        
        filled: true,
        fillColor: cs.surfaceContainerLow,

        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      ),
      onChanged: onChanged,
      onEditingComplete: onEditingComplete,
      validator: (v) {
        final t = v?.trim() ?? '';
        if (t.isEmpty) return '정산 유형을 입력해주세요.';
        return null;
      },
    );
  }
}
