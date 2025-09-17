import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 서비스 로그인 카드 팔레트(브랜드 톤)
class _SvcColors {
  static const base = Color(0xFF0D47A1); // primary
  static const dark = Color(0xFF09367D); // 진한 텍스트/아이콘
  static const light = Color(0xFF5472D3); // 라이트 톤/보더
}

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
    return InputDecoration(
      labelText: label,
      floatingLabelStyle: const TextStyle(
        color: _SvcColors.dark,
        fontWeight: FontWeight.w700,
      ),
      suffixText: suffixText,
      suffixStyle: const TextStyle(
        color: _SvcColors.dark,
        fontWeight: FontWeight.w600,
      ),
      isDense: true,
      filled: true,
      fillColor: _SvcColors.light.withOpacity(.06),
      contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),

      // 기본 / 포커스 / 에러 보더를 브랜드 톤으로 정리
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
          // ⚠️ const 제거 (요소가 상수가 아님)
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
