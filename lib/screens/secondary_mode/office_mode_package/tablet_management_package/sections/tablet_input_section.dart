import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 서비스(로그인 카드)와 동일 계열 팔레트
class _SvcColors {
  static const base = Color(0xFF0D47A1);
  static const dark = Color(0xFF09367D);
  static const light = Color(0xFF5472D3);
}

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

  InputDecoration _decoration({
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
      floatingLabelStyle: const TextStyle(
        color: _SvcColors.dark,
        fontWeight: FontWeight.w700,
      ),
      prefixIcon: prefixIcon == null ? null : Icon(prefixIcon),
      prefixIconColor: _SvcColors.dark,
      suffixText: suffixText,
      suffixStyle: const TextStyle(
        color: _SvcColors.dark,
        fontWeight: FontWeight.w600,
      ),
      suffixIcon: showDoneIcon
          ? Icon(
        done ? Icons.check_circle : Icons.radio_button_unchecked,
        color: done ? _SvcColors.dark : _SvcColors.light.withOpacity(.70),
      )
          : null,
      filled: true,
      fillColor: _SvcColors.light.withOpacity(.06),
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: _SvcColors.light.withOpacity(.45)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: _SvcColors.base, width: 1.2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: Colors.red.shade300),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: Colors.red.shade400, width: 1.2),
      ),
      errorText: errorText,
    );
  }

  @override
  Widget build(BuildContext context) {
    // 문자열 비교는 유지(호환). 추후 필드별 에러로 교체 권장.
    final nameError =
    errorMessage == '이름을 다시 입력하세요' ? errorMessage : null;

    final handleError = (errorMessage == '아이디는 소문자 영어 3~20자로 입력하세요' ||
        errorMessage == '아이디를 다시 입력하세요' ||
        errorMessage == '전화번호를 다시 입력하세요')
        ? errorMessage
        : null;

    final emailError = (errorMessage == '이메일을 입력하세요' ||
        errorMessage == '이메일을 다시 확인하세요')
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
          decoration: _decoration(
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
          decoration: _decoration(
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
          decoration: _decoration(
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
