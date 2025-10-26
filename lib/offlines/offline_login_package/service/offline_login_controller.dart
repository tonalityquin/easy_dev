import 'package:flutter/material.dart';
import 'package:easydev/offlines/sql/offline_auth_service.dart';

class OfflineLoginController {
  static const String allowedName = 'tester';
  static const String allowedPhone = '01012345678';
  static const String allowedPassword = '12345';

  static const String defaultDivision = 'dev'; // division
  static const String defaultAreaHQ = 'HQ 지역'; // areas[0]

  bool isLoading = false;
  bool obscurePassword = true;

  final TextEditingController nameController = TextEditingController();
  final TextEditingController phoneController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();

  final FocusNode nameFocus = FocusNode();
  final FocusNode phoneFocus = FocusNode();
  final FocusNode passwordFocus = FocusNode();

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

  void togglePassword() {
    obscurePassword = !obscurePassword;
  }

  void formatPhoneNumber(String value, StateSetter setState) {
    final digits = _digitsOnly(value);
    final selectionIndex = phoneController.selection.baseOffset;
    setState(() {
      phoneController.text = digits;
      final pos = digits.length;
      phoneController.selection = TextSelection.collapsed(
        offset: selectionIndex < 0 ? pos : (selectionIndex > pos ? pos : selectionIndex),
      );
    });
  }

  void login(BuildContext context, StateSetter setState) async {
    if (isLoading) return;
    setState(() => isLoading = true);
    try {
      await Future<void>.delayed(const Duration(milliseconds: 150)); // UX 보완용 소딜레이
      await attemptLogin(context);
    } finally {
      if (context.mounted) {
        setState(() => isLoading = false);
      }
    }
  }

  Future<void> attemptLogin(BuildContext context) async {
    final name = nameController.text.trim();
    final phone = _digitsOnly(phoneController.text.trim());
    final password = passwordController.text;

    final ok = name.toLowerCase() == allowedName && phone == allowedPhone && password == allowedPassword;

    if (!ok) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('오프라인 로그인 정보가 올바르지 않습니다.')),
        );
      }
      return;
    }

    try {
      await OfflineAuthService.instance.signInOffline(
        userId: phone,
        name: name,
        position: defaultDivision,
        phone: phone,
        area: defaultAreaHQ,
      );

      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('오프라인 로그인 성공')),
      );

      if (onLoginSucceeded != null) {
        onLoginSucceeded!();
      } else {
        Navigator.of(context).pushReplacementNamed('/offline_commute');
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('오프라인 세션 저장 실패: $e')),
        );
      }
    }
  }

  String _digitsOnly(String input) {
    final codeUnits = input.codeUnits;
    final buf = StringBuffer();
    for (final u in codeUnits) {
      if (u >= 48 && u <= 57) buf.writeCharCode(u);
    }
    return buf.toString();
  }
}
