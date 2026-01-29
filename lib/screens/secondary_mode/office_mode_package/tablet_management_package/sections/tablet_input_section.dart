import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 대문자 입력 시 자동으로 소문자로 변환
class LowercaseTextFormatter extends TextInputFormatter {
  const LowercaseTextFormatter();

  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue,
      TextEditingValue newValue,
      ) {
    final lowered = newValue.text.toLowerCase();
    return newValue.copyWith(
      text: lowered,
      selection: newValue.selection,
      composing: TextRange.empty,
    );
  }
}

class TabletInputSection extends StatelessWidget {
  final TextEditingController nameController;
  final TextEditingController handleController;
  final TextEditingController emailController;

  final FocusNode nameFocus;
  final FocusNode handleFocus;
  final FocusNode emailFocus;

  /// 기존 호환 유지(문자열 기반 에러)
  final String? errorMessage;

  /// 입력 변경 시(에러 해제 등) 호출
  final VoidCallback? onEdited;

  /// 이메일 로컬파트 유효성 검사(선택)
  final bool Function(String input)? emailLocalPartValidator;

  const TabletInputSection({
    super.key,
    required this.nameController,
    required this.handleController,
    required this.emailController,
    required this.nameFocus,
    required this.handleFocus,
    required this.emailFocus,
    required this.errorMessage,
    this.onEdited,
    this.emailLocalPartValidator,
  });

  bool _isNameOk(String v) => v.trim().isNotEmpty;

  bool _isHandleOk(String v) => RegExp(r'^[a-z]{3,20}$').hasMatch(v.trim());

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
        required String helperText,
        String? errorText,
        String? suffixText,
        IconData? prefixIcon,
        bool showDoneIcon = false,
        bool done = false,
      }) {
    return InputDecoration(
      labelText: label,
      helperText: helperText,
      floatingLabelStyle: TextStyle(
        color: cs.primary,
        fontWeight: FontWeight.w700,
      ),
      prefixIcon: prefixIcon == null ? null : Icon(prefixIcon),
      prefixIconColor: cs.onSurfaceVariant,
      suffixText: suffixText,
      suffixStyle: TextStyle(
        color: cs.onSurfaceVariant.withOpacity(.85),
        fontWeight: FontWeight.w600,
      ),
      suffixIcon: showDoneIcon
          ? Icon(
        done ? Icons.check_circle : Icons.radio_button_unchecked,
        color: done ? cs.primary : cs.onSurfaceVariant.withOpacity(.55),
      )
          : null,
      filled: true,
      fillColor: cs.surfaceVariant.withOpacity(.45),
      isDense: true,
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

    // 문자열 비교는 유지(호환). 추후 필드별 에러로 교체 권장.
    final nameError = errorMessage == '이름을 다시 입력하세요' ? errorMessage : null;

    final handleError = (errorMessage == '아이디는 소문자 영어 3~20자로 입력하세요' ||
        errorMessage == '아이디를 다시 입력하세요' ||
        errorMessage == '전화번호를 다시 입력하세요')
        ? errorMessage
        : null;

    final emailError =
    (errorMessage == '이메일을 입력하세요' || errorMessage == '이메일을 다시 확인하세요')
        ? errorMessage
        : null;

    return Column(
      children: [
        // 이름
        TextField(
          controller: nameController,
          focusNode: nameFocus,
          onChanged: (_) => onEdited?.call(),
          textInputAction: TextInputAction.next,
          onSubmitted: (_) => FocusScope.of(context).nextFocus(),
          textCapitalization: TextCapitalization.words,
          autofillHints: const [AutofillHints.name],
          style: TextStyle(color: cs.onSurface),
          decoration: _decoration(
            context,
            cs: cs,
            label: '이름',
            helperText: '예: 태블릿A, 로비태블릿 등',
            errorText: nameError,
            prefixIcon: Icons.person_outline,
            showDoneIcon: true,
            done: _isNameOk(nameController.text),
          ),
        ),
        const SizedBox(height: 16),

        // 아이디(소문자 영문)
        TextField(
          controller: handleController,
          focusNode: handleFocus,
          onChanged: (_) => onEdited?.call(),
          textInputAction: TextInputAction.next,
          onSubmitted: (_) => FocusScope.of(context).nextFocus(),
          keyboardType: TextInputType.visiblePassword,
          autofillHints: const [AutofillHints.username],
          inputFormatters: [
            const LowercaseTextFormatter(),
            FilteringTextInputFormatter.allow(RegExp(r'[a-z]')),
            LengthLimitingTextInputFormatter(20),
          ],
          style: TextStyle(color: cs.onSurface),
          decoration: _decoration(
            context,
            cs: cs,
            label: '아이디(소문자 영문)',
            helperText: '소문자 a~z, 3~20자',
            errorText: handleError,
            prefixIcon: Icons.tag,
            showDoneIcon: true,
            done: _isHandleOk(handleController.text),
          ),
        ),
        const SizedBox(height: 16),

        // 이메일(로컬파트)
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
            helperText: '영문/숫자/._- 만 입력 가능',
            suffixText: '@gmail.com',
            errorText: emailError,
            prefixIcon: Icons.alternate_email,
            showDoneIcon: true,
            done: _isEmailOk(emailController.text),
          ),
        ),
      ],
    );
  }
}
