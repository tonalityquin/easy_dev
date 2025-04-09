import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../states/user/user_state.dart';
import '../../states/area/area_state.dart';
import '../../repositories/user/user_repository.dart';
import '../../utils/snackbar_helper.dart';
import '../../utils/login_network_service.dart';
import 'login_view_model.dart';

class LoginController {
  final BuildContext context;

  final TextEditingController nameController = TextEditingController();
  final TextEditingController phoneController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();

  final FocusNode nameFocus = FocusNode();
  final FocusNode phoneFocus = FocusNode();
  final FocusNode passwordFocus = FocusNode();

  bool isLoading = false;
  bool obscurePassword = true;

  LoginController(this.context);

  void initState() {
    Provider.of<UserState>(context, listen: false).loadUserToLogIn().then((_) {
      if (Provider.of<UserState>(context, listen: false).isLoggedIn) {
        Navigator.pushReplacementNamed(context, '/home');
      }
    });
  }

  void dispose() {
    nameController.dispose();
    phoneController.dispose();
    passwordController.dispose();
    nameFocus.dispose();
    phoneFocus.dispose();
    passwordFocus.dispose();
  }

  void togglePassword() {
    obscurePassword = !obscurePassword;
  }

  InputDecoration inputDecoration({required String label, IconData? icon, Widget? suffixIcon}) {
    return InputDecoration(
      labelText: label,
      hintText: label,
      prefixIcon: icon != null ? Icon(icon) : null,
      suffixIcon: suffixIcon,
      contentPadding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
      filled: true,
      fillColor: Colors.grey.shade100,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: const BorderSide(color: Colors.indigo, width: 2)),
    );
  }

  Future<void> login(StateSetter setState) async {
    final name = nameController.text.trim();
    final phone = phoneController.text.trim().replaceAll(RegExp(r'\D'), '');
    final password = passwordController.text.trim();

    final phoneError = LoginValidator.validatePhone(phone);
    final passwordError = LoginValidator.validatePassword(password);

    if (name.isEmpty) {
      showFailedSnackbar(context, '이름을 입력해주세요.');
      return;
    }
    if (phoneError != null) {
      showFailedSnackbar(context, phoneError);
      return;
    }
    if (passwordError != null) {
      showFailedSnackbar(context, passwordError);
      return;
    }

    setState(() => isLoading = true);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    if (!await NetworkService().isConnected()) {
      Navigator.of(context).pop();
      showFailedSnackbar(context, '인터넷 연결이 필요합니다.');
      setState(() => isLoading = false);
      return;
    }

    try {
      final userRepository = context.read<UserRepository>();
      final user = await userRepository.getUserByPhone(phone);

      // ✅ 디버깅 출력
      print("[DEBUG] 입력값 → name: $name, phone: $phone, password: $password");

      if (user != null) {
        print("[DEBUG] DB 유저 → name: ${user.name}, phone: ${user.phone}, password: ${user.password}");
      } else {
        print("[DEBUG] Firestore에서 user가 null로 반환됨");
      }

      if (user != null && user.name == name && user.password == password) {
        final userState = context.read<UserState>();
        final areaState = context.read<AreaState>();

        final updatedUser = user.copyWith(isSaved: true);
        userState.updateUserCard(updatedUser);
        areaState.updateArea(updatedUser.area);

        Navigator.of(context).pop();
        Navigator.pushReplacementNamed(context, '/home');
      } else {
        Navigator.of(context).pop();
        showFailedSnackbar(context, '이름 또는 비밀번호가 올바르지 않습니다.');
      }
    } catch (e) {
      Navigator.of(context).pop();
      showFailedSnackbar(context, '로그인 실패: $e');
    }
  }
}