import 'package:flutter/material.dart';

import '../../../../../../shared/auth/account_code_number.dart';

class UserInputSection extends StatelessWidget {
  final TextEditingController nameController;
  final TextEditingController codeNumberController;
  final TextEditingController emailController;

  final FocusNode nameFocus;
  final FocusNode codeNumberFocus;
  final FocusNode emailFocus;

  
  final String? errorMessage;

  
  final VoidCallback? onEdited;

  
  final bool Function(String input)? emailLocalPartValidator;

  
  final bool lockNameAndCodeNumber;

  const UserInputSection({
    super.key,
    required this.nameController,
    required this.codeNumberController,
    required this.emailController,
    required this.nameFocus,
    required this.codeNumberFocus,
    required this.emailFocus,
    required this.errorMessage,
    this.onEdited,
    this.emailLocalPartValidator,
    this.lockNameAndCodeNumber = false,
  });

  bool _isNameOk(String v) => v.trim().isNotEmpty;
  bool _isCodeNumberOk(String v) => lockNameAndCodeNumber
      ? AccountCodeNumber.isValid(v)
      : AccountCodeNumber.isGeneratedCode(v);

  bool _isEmailOk(String v) {
    final t = v.trim();
    if (t.isEmpty) return false;
    final fn = emailLocalPartValidator;
    return fn == null ? true : fn(t);
  }

  InputDecoration _decoration(
      BuildContext context, {
        required ColorScheme cs,
        required String label,
        String? errorText,
        String? suffixText,
        bool showDoneIcon = false,
        bool done = false,
        bool locked = false,
      }) {
    final fill = locked ? cs.surfaceVariant.withOpacity(.30) : cs.surfaceVariant.withOpacity(.45);

    return InputDecoration(
      labelText: label,
      floatingLabelStyle: TextStyle(
        color: cs.primary,
        fontWeight: FontWeight.w700,
      ),
      suffixText: suffixText,
      suffixStyle: TextStyle(
        color: cs.onSurfaceVariant.withOpacity(.85),
        fontWeight: FontWeight.w600,
      ),
      suffixIcon: locked
          ? Icon(Icons.lock, color: cs.onSurfaceVariant)
          : (showDoneIcon
          ? Icon(
        done ? Icons.check_circle : Icons.radio_button_unchecked,
        color: done ? cs.primary : cs.onSurfaceVariant.withOpacity(.55),
      )
          : null),
      isDense: true,
      filled: true,
      fillColor: fill,
      contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: cs.outlineVariant.withOpacity(.75)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: cs.primary, width: 1.3),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: cs.error.withOpacity(.60)),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: cs.error, width: 1.3),
      ),
      errorText: errorText,
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    
    final nameError = errorMessage == '이름을 다시 입력하세요' ? errorMessage : null;
    final codeNumberError = errorMessage == '코드번호를 다시 확인하세요' ? errorMessage : null;
    final emailError =
    (errorMessage == '이메일을 입력하세요' || errorMessage == '이메일을 다시 확인하세요') ? errorMessage : null;

    return Column(
      children: [
        
        TextField(
          controller: nameController,
          focusNode: nameFocus,
          readOnly: lockNameAndCodeNumber,
          enableInteractiveSelection: true,
          onChanged: lockNameAndCodeNumber ? null : (_) => onEdited?.call(),
          textInputAction: TextInputAction.next,
          onSubmitted: (_) => FocusScope.of(context).nextFocus(),
          textCapitalization: TextCapitalization.words,
          autofillHints: const [AutofillHints.name],
          style: TextStyle(color: cs.onSurface),
          decoration: _decoration(
            context,
            cs: cs,
            label: '이름',
            errorText: nameError,
            showDoneIcon: !lockNameAndCodeNumber,
            done: _isNameOk(nameController.text),
            locked: lockNameAndCodeNumber,
          ),
        ),
        const SizedBox(height: 16),

        
        TextField(
          controller: codeNumberController,
          focusNode: codeNumberFocus,
          readOnly: true,
          enableInteractiveSelection: true,
          onChanged: null,
          textInputAction: TextInputAction.next,
          onSubmitted: (_) => FocusScope.of(context).nextFocus(),
          keyboardType: TextInputType.text,
          style: TextStyle(color: cs.onSurface),
          decoration: _decoration(
            context,
            cs: cs,
            label: '코드번호',
            errorText: codeNumberError,
            showDoneIcon: false,
            done: _isCodeNumberOk(codeNumberController.text),
            locked: true,
          ),
        ),
        const SizedBox(height: 16),

        
        TextField(
          controller: emailController,
          focusNode: emailFocus,
          onChanged: (_) => onEdited?.call(),
          textInputAction: TextInputAction.done,
          keyboardType: TextInputType.emailAddress,
          autofillHints: const [AutofillHints.username],
          style: TextStyle(color: cs.onSurface),
          decoration: _decoration(
            context,
            cs: cs,
            label: '이메일(구글)',
            suffixText: '@gmail.com',
            errorText: emailError,
            showDoneIcon: true,
            done: _isEmailOk(emailController.text),
            locked: false,
          ),
        ),
      ],
    );
  }
}
