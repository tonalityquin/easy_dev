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
  final String? errorMessage;

  /// 입력 변경 시(에러 해제 등) 호출
  final VoidCallback? onEdited;

  /// 이메일 로컬파트 유효성 검사(선택)
  final bool Function(String input)? emailLocalPartValidator;

  /// ✅ 추가: 수정 모드에서 이름/전화번호 잠금
  final bool lockNameAndPhone;

  const UserInputSection({
    super.key,
    required this.nameController,
    required this.phoneController,
    required this.emailController,
    required this.nameFocus,
    required this.phoneFocus,
    required this.emailFocus,
    required this.errorMessage,
    this.onEdited,
    this.emailLocalPartValidator,
    this.lockNameAndPhone = false,
  });

  bool _isNameOk(String v) => v.trim().isNotEmpty;

  bool _isPhoneOk(String v) => RegExp(r'^\d{9,}$').hasMatch(v.trim());

  bool _isEmailOk(String v) {
    final t = v.trim();
    if (t.isEmpty) return false;
    final fn = emailLocalPartValidator;
    return fn == null ? true : fn(t);
  }

  InputDecoration _decoration(
      BuildContext context, {
        required String label,
        required String helperText,
        String? errorText,
        String? suffixText,
        bool showDoneIcon = false,
        bool done = false,
        bool locked = false,
      }) {
    return InputDecoration(
      labelText: label,
      helperText: helperText,
      floatingLabelStyle: const TextStyle(
        color: _SvcColors.dark,
        fontWeight: FontWeight.w700,
      ),
      suffixText: suffixText,
      suffixStyle: const TextStyle(
        color: _SvcColors.dark,
        fontWeight: FontWeight.w600,
      ),
      suffixIcon: locked
          ? const Icon(Icons.lock, color: _SvcColors.dark)
          : (showDoneIcon
          ? Icon(
        done ? Icons.check_circle : Icons.radio_button_unchecked,
        color:
        done ? _SvcColors.dark : _SvcColors.light.withOpacity(.70),
      )
          : null),
      isDense: true,
      filled: true,
      fillColor: locked
          ? _SvcColors.light.withOpacity(.04)
          : _SvcColors.light.withOpacity(.06),
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
    // 기존 호환: 문자열 비교로 필드별 에러 분기 유지
    final nameError = errorMessage == '이름을 다시 입력하세요' ? errorMessage : null;
    final phoneError =
    errorMessage == '전화번호를 다시 입력하세요' ? errorMessage : null;
    final emailError = (errorMessage == '이메일을 입력하세요' ||
        errorMessage == '이메일을 다시 확인하세요')
        ? errorMessage
        : null;

    final lockedHelper =
        '수정 모드에서는 변경할 수 없습니다.';

    return Column(
      children: [
        // 이름 (수정 모드 잠금)
        TextField(
          controller: nameController,
          focusNode: nameFocus,
          readOnly: lockNameAndPhone,
          enableInteractiveSelection: true,
          onChanged: lockNameAndPhone ? null : (_) => onEdited?.call(),
          textInputAction: TextInputAction.next,
          onSubmitted: (_) => FocusScope.of(context).nextFocus(),
          textCapitalization: TextCapitalization.words,
          autofillHints: const [AutofillHints.name],
          decoration: _decoration(
            context,
            label: '이름',
            helperText: lockNameAndPhone ? lockedHelper : '예: 홍길동',
            errorText: nameError,
            showDoneIcon: !lockNameAndPhone,
            done: _isNameOk(nameController.text),
            locked: lockNameAndPhone,
          ),
        ),
        const SizedBox(height: 16),

        // 전화번호 (수정 모드 잠금)
        TextField(
          controller: phoneController,
          focusNode: phoneFocus,
          readOnly: lockNameAndPhone,
          enableInteractiveSelection: true,
          onChanged: lockNameAndPhone ? null : (_) => onEdited?.call(),
          textInputAction: TextInputAction.next,
          onSubmitted: (_) => FocusScope.of(context).nextFocus(),
          keyboardType: TextInputType.phone,
          autofillHints: const [AutofillHints.telephoneNumber],
          inputFormatters: lockNameAndPhone
              ? null
              : [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(11),
          ],
          decoration: _decoration(
            context,
            label: '전화번호',
            helperText: lockNameAndPhone ? lockedHelper : '숫자만 입력 (최소 9자리)',
            errorText: phoneError,
            showDoneIcon: !lockNameAndPhone,
            done: _isPhoneOk(phoneController.text),
            locked: lockNameAndPhone,
          ),
        ),
        const SizedBox(height: 16),

        // 이메일(로컬파트) - 수정 모드에서도 편집 허용(요구사항: 이름/전화만 잠금)
        TextField(
          controller: emailController,
          focusNode: emailFocus,
          onChanged: (_) => onEdited?.call(),
          textInputAction: TextInputAction.done,
          keyboardType: TextInputType.emailAddress,
          autofillHints: const [AutofillHints.username],
          decoration: _decoration(
            context,
            label: '이메일(구글)',
            helperText: '영문/숫자/._- 만 입력 가능',
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
