import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 서비스(로그인 카드)와 동일 계열 팔레트
class _SvcColors {
  static const base = Color(0xFF0D47A1); // primary
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
  final TextEditingController handleController; // 🔁 phone → handle
  final TextEditingController emailController;

  final FocusNode nameFocus;
  final FocusNode handleFocus; // 🔁 phone → handle
  final FocusNode emailFocus;

  /// 현재 구조와의 호환을 위해 유지.
  /// (권장: 필드별 에러 전달 또는 Form/validator로 대체)
  final String? errorMessage;

  const TabletInputSection({
    super.key,
    required this.nameController,
    required this.handleController, // 🔁
    required this.emailController,
    required this.nameFocus,
    required this.handleFocus, // 🔁
    required this.emailFocus,
    required this.errorMessage,
  });

  InputDecoration _decoration(
      BuildContext context, {
        required String label,
        String? errorText,
        String? suffixText,
        IconData? prefixIcon,
      }) {
    return InputDecoration(
      labelText: label,
      suffixText: suffixText,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
      prefixIcon: prefixIcon == null ? null : Icon(prefixIcon),
      prefixIconColor: _SvcColors.base.withOpacity(.85),
      focusedBorder: OutlineInputBorder(
        borderSide: const BorderSide(color: _SvcColors.base),
        borderRadius: BorderRadius.circular(8),
      ),
      enabledBorder: OutlineInputBorder(
        borderSide: BorderSide(color: _SvcColors.base.withOpacity(.28)),
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
    final nameError  = errorMessage == '이름을 다시 입력하세요' ? errorMessage : null;

    // 새 규칙/문구와의 호환 + 과거 문구 호환(전화번호 → 아이디 전환기)
    final handleError = (errorMessage == '아이디는 소문자 영어 3~20자로 입력하세요' ||
        errorMessage == '아이디를 다시 입력하세요' ||
        errorMessage == '전화번호를 다시 입력하세요')
        ? errorMessage
        : null;

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
            prefixIcon: Icons.person_outline,
          ),
        ),
        const SizedBox(height: 16),

        // 아이디(소문자 영문) — 기존 전화번호 입력 대체
        TextField(
          controller: handleController,
          focusNode: handleFocus,
          textInputAction: TextInputAction.next,
          onSubmitted: (_) => FocusScope.of(context).nextFocus(),
          keyboardType: TextInputType.visiblePassword,
          autofillHints: const [AutofillHints.username],
          // ❗ const 리스트 → 일반 리스트로 변경 (RegExp가 const 아님)
          inputFormatters: [
            const LowercaseTextFormatter(),                          // 대문자 → 소문자
            FilteringTextInputFormatter.allow(RegExp(r'[a-z]')),     // 소문자만
            LengthLimitingTextInputFormatter(20),                    // 최대 20자
          ],
          decoration: _decoration(
            context,
            label: '아이디(소문자 영문)',
            errorText: handleError,
            prefixIcon: Icons.tag,
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
            prefixIcon: Icons.alternate_email,
          ),
        ),
      ],
    );
  }
}
