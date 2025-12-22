import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// ✅ AppCardPalette 정의 파일을 프로젝트 경로에 맞게 import 하세요.
// 예) import 'package:your_app/theme/app_card_palette.dart';
import '../../../../../theme.dart';

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

  /// ✅ 수정 모드에서 이름/전화번호 잠금
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
        required Color base,
        required Color dark,
        required Color light,
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
      floatingLabelStyle: TextStyle(
        color: dark,
        fontWeight: FontWeight.w700,
      ),
      suffixText: suffixText,
      suffixStyle: TextStyle(
        color: dark,
        fontWeight: FontWeight.w600,
      ),
      suffixIcon: locked
          ? Icon(Icons.lock, color: dark)
          : (showDoneIcon
          ? Icon(
        done ? Icons.check_circle : Icons.radio_button_unchecked,
        color: done ? dark : light.withOpacity(.70),
      )
          : null),
      isDense: true,
      filled: true,
      fillColor: locked ? light.withOpacity(.04) : light.withOpacity(.06),
      contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: light.withOpacity(.45)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: base, width: 1.2),
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
    final palette = AppCardPalette.of(context);
    final base = palette.serviceBase;
    final dark = palette.serviceDark;
    final light = palette.serviceLight;

    // 기존 호환: 문자열 비교로 필드별 에러 분기 유지
    final nameError = errorMessage == '이름을 다시 입력하세요' ? errorMessage : null;
    final phoneError =
    errorMessage == '전화번호를 다시 입력하세요' ? errorMessage : null;
    final emailError = (errorMessage == '이메일을 입력하세요' ||
        errorMessage == '이메일을 다시 확인하세요')
        ? errorMessage
        : null;

    const lockedHelper = '수정 모드에서는 변경할 수 없습니다.';

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
            base: base,
            dark: dark,
            light: light,
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
            base: base,
            dark: dark,
            light: light,
            label: '전화번호',
            helperText:
            lockNameAndPhone ? lockedHelper : '숫자만 입력 (최소 9자리)',
            errorText: phoneError,
            showDoneIcon: !lockNameAndPhone,
            done: _isPhoneOk(phoneController.text),
            locked: lockNameAndPhone,
          ),
        ),
        const SizedBox(height: 16),

        // 이메일(로컬파트) - 수정 모드에서도 편집 허용(이름/전화만 잠금)
        TextField(
          controller: emailController,
          focusNode: emailFocus,
          onChanged: (_) => onEdited?.call(),
          textInputAction: TextInputAction.done,
          keyboardType: TextInputType.emailAddress,
          autofillHints: const [AutofillHints.username],
          decoration: _decoration(
            context,
            base: base,
            dark: dark,
            light: light,
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
