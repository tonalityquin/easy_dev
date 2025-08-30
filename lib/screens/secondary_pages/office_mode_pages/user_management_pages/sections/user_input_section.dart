import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class UserInputSection extends StatelessWidget {
  final TextEditingController nameController;
  final TextEditingController phoneController;
  final TextEditingController emailController;

  final FocusNode nameFocus;
  final FocusNode phoneFocus;
  final FocusNode emailFocus;

  /// 현재 구조와의 호환을 위해 유지.
  /// (권장: 필드별 에러 전달 또는 Form/validator로 대체)
  final String? errorMessage;

  const UserInputSection({
    super.key,
    required this.nameController,
    required this.phoneController,
    required this.emailController,
    required this.nameFocus,
    required this.phoneFocus,
    required this.emailFocus,
    required this.errorMessage,
  });

  InputDecoration _decoration(
    BuildContext context, {
    required String label,
    String? errorText,
    String? suffixText,
  }) {
    final primary = Theme.of(context).colorScheme.primary;
    return InputDecoration(
      labelText: label,
      suffixText: suffixText,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
      focusedBorder: OutlineInputBorder(
        borderSide: BorderSide(color: primary),
        borderRadius: BorderRadius.circular(8),
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
      ),
      errorText: errorText,
    );
  }

  @override
  Widget build(BuildContext context) {
    // 문자열 비교는 유지(호환). 추후 필드별 에러로 교체 권장.
    final nameError = errorMessage == '이름을 다시 입력하세요' ? errorMessage : null;
    final phoneError = errorMessage == '전화번호를 다시 입력하세요' ? errorMessage : null;
    final emailError = errorMessage == '이메일을 입력하세요' ? errorMessage : null;

    return Column(
      children: [
        // 이름
        TextField(
          controller: nameController,
          focusNode: nameFocus,
          textInputAction: TextInputAction.next,
          onSubmitted: (_) => FocusScope.of(context).nextFocus(),
          textCapitalization: TextCapitalization.words,
          autofillHints: const [AutofillHints.name],
          decoration: _decoration(
            context,
            label: '이름',
            errorText: nameError,
          ),
        ),
        const SizedBox(height: 16),

        // 전화번호
        TextField(
          controller: phoneController,
          focusNode: phoneFocus,
          textInputAction: TextInputAction.next,
          onSubmitted: (_) => FocusScope.of(context).nextFocus(),
          keyboardType: TextInputType.phone,
          autofillHints: const [AutofillHints.telephoneNumber],
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(11),
          ],
          decoration: _decoration(
            context,
            label: '전화번호',
            errorText: phoneError,
          ),
        ),
        const SizedBox(height: 16),

        // 이메일(로컬파트) + suffixText
        TextField(
          controller: emailController,
          focusNode: emailFocus,
          textInputAction: TextInputAction.done,
          keyboardType: TextInputType.emailAddress,
          autofillHints: const [AutofillHints.username],
          decoration: _decoration(
            context,
            label: '이메일(구글)',
            suffixText: '@gmail.com', // ✅ Row 대신 suffixText 사용
            errorText: emailError,
          ),
        ),
      ],
    );
  }
}
