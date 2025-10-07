import 'package:flutter/material.dart';

/// 오프라인 모드 전용 로그인 컨트롤러
/// - 아래 고정 자격증명만 성공 처리:
///   이름: tester / 전화번호: 01012345678 / 비밀번호: 12345
class OfflineLoginController {
  // 고정 자격증명
  static const String allowedName = 'tester';
  static const String allowedPhone = '01012345678';
  static const String allowedPassword = '12345';

  // 상태
  bool isLoading = false;
  bool obscurePassword = true;

  // 폼 컨트롤러
  final TextEditingController nameController = TextEditingController();
  final TextEditingController phoneController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();

  // 포커스
  final FocusNode nameFocus = FocusNode();
  final FocusNode phoneFocus = FocusNode();
  final FocusNode passwordFocus = FocusNode();

  /// 로그인 성공 시 화면 전환 등 외부에서 주입할 콜백(선택)
  final VoidCallback? onLoginSucceeded;

  OfflineLoginController({this.onLoginSucceeded});

  void dispose() {
    nameController.dispose();
    phoneController.dispose();
    passwordController.dispose();
    nameFocus.dispose();
    phoneFocus.dispose();
    passwordFocus.dispose();
  }

  /// Deep Blue 팔레트 기반의 공통 인풋 데코레이션
  InputDecoration inputDecoration({
    required String label,
    required IconData icon,
    Widget? suffixIcon,
    String? hint,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon: Icon(icon),
      suffixIcon: suffixIcon,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    );
  }

  /// 비밀번호 표시/숨김 토글
  void togglePassword() {
    obscurePassword = !obscurePassword;
  }

  /// 숫자만 남기고 간단 포맷 적용(필요 시 고도화 가능)
  void formatPhoneNumber(String value, StateSetter setState) {
    final digits = _digitsOnly(value);
    // 여기서는 단순히 숫자만 유지 (하이픈 포맷이 필요하면 추가하세요)
    final selectionIndex = phoneController.selection.baseOffset;
    setState(() {
      phoneController.text = digits;
      final pos = digits.length;
      phoneController.selection = TextSelection.collapsed(
        offset: selectionIndex < 0 ? pos : (selectionIndex > pos ? pos : selectionIndex),
      );
    });
  }

  /// ServiceLoginForm 호환용: setState를 받아 로딩상태 토글 + 실제 시도
  void login(BuildContext context, StateSetter setState) async {
    if (isLoading) return;
    setState(() => isLoading = true);
    try {
      await Future<void>.delayed(const Duration(milliseconds: 150)); // 살짝의 UX용 딜레이
      await attemptLogin(context);
    } finally {
      setState(() => isLoading = false);
    }
  }

  /// 오프라인 전용 로그인 시도(직접 호출 가능)
  Future<void> attemptLogin(BuildContext context) async {
    final name = nameController.text.trim();
    final phone = _digitsOnly(phoneController.text.trim());
    final password = passwordController.text;

    final ok = name.toLowerCase() == allowedName &&
        phone == allowedPhone &&
        password == allowedPassword;

    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('오프라인 로그인 성공')),
      );
      if (onLoginSucceeded != null) {
        onLoginSucceeded!();
      } else {
        // 라우트 상수 import 없이도 작동하도록 이름 문자열 사용
        Navigator.of(context).pushReplacementNamed('/offline_commute');
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('오프라인 로그인 정보가 올바르지 않습니다.')),
      );
    }
  }

  /// 하이픈/공백 제거 및 숫자만 남기기
  String _digitsOnly(String input) {
    final codeUnits = input.codeUnits;
    final buf = StringBuffer();
    for (final u in codeUnits) {
      if (u >= 48 && u <= 57) buf.writeCharCode(u);
    }
    return buf.toString();
  }
}
