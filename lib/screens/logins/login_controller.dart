import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'utils/login_validate.dart';

import '../../repositories/user/user_repository.dart';

import '../../states/user/user_state.dart';
import '../../states/area/area_state.dart';

import '../../utils/snackbar_helper.dart';
import '../../utils/login_network_service.dart';

import 'debugs/login_debug_firestore_logger.dart';

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
    LoginDebugFirestoreLogger().log('🔵 LoginController.initState() 호출', level: 'info');

    Provider.of<UserState>(context, listen: false).loadUserToLogIn().then((_) {
      LoginDebugFirestoreLogger().log(
        '✅ loadUserToLogIn() 완료: isLoggedIn=${Provider.of<UserState>(context, listen: false).isLoggedIn}',
        level: 'success',
      );

      if (Provider.of<UserState>(context, listen: false).isLoggedIn && context.mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          LoginDebugFirestoreLogger().log('➡️ 이미 로그인되어 홈으로 이동', level: 'info');
          Navigator.pushReplacementNamed(context, '/home');
        });
      }
    });
  }

  Future<void> login(StateSetter setState) async {
    final name = nameController.text.trim();
    final phone = phoneController.text.trim().replaceAll(RegExp(r'\D'), '');
    final password = passwordController.text.trim();

    LoginDebugFirestoreLogger().log(
      '📥 로그인 시도: name="$name", phone="$phone"',
      level: 'called',
    );

    final phoneError = LoginValidate.validatePhone(phone);
    final passwordError = LoginValidate.validatePassword(password);

    if (name.isEmpty) {
      showFailedSnackbar(context, '이름을 입력해주세요.');
      LoginDebugFirestoreLogger().log('⚠️ 이름 미입력', level: 'error');
      return;
    }
    if (phoneError != null) {
      showFailedSnackbar(context, phoneError);
      LoginDebugFirestoreLogger().log('⚠️ 전화번호 유효성 오류: $phoneError', level: 'error');
      return;
    }
    if (passwordError != null) {
      showFailedSnackbar(context, passwordError);
      LoginDebugFirestoreLogger().log('⚠️ 비밀번호 유효성 오류: $passwordError', level: 'error');
      return;
    }

    setState(() => isLoading = true);
    LoginDebugFirestoreLogger().log('🔄 로그인 진행 중...', level: 'info');

    if (!await NetworkService().isConnected()) {
      if (context.mounted) {
        showFailedSnackbar(context, '인터넷 연결이 필요합니다.');
      }
      LoginDebugFirestoreLogger().log('❌ 네트워크 연결 실패', level: 'error');
      setState(() => isLoading = false);
      return;
    }

    try {
      final userRepository = context.read<UserRepository>();
      final user = await userRepository.getUserByPhone(phone);

      if (user != null) {
        LoginDebugFirestoreLogger().log(
          '✅ DB에서 사용자 조회 성공: ${user.name}',
          level: 'success',
        );
      } else {
        LoginDebugFirestoreLogger().log(
          '⚠️ DB에서 사용자 조회 실패(null 반환)',
          level: 'error',
        );
      }

      if (context.mounted) {
        debugPrint("login, 입력값 → name: $name, phone: $phone, password: $password");

        if (user != null) {
          debugPrint("login, DB 유저 → name: ${user.name}, phone: ${user.phone}, password: ${user.password}");
        } else {
          debugPrint("login, DB에서 user가 null로 반환됨");
        }
      }

      if (user != null && user.name == name && user.password == password) {
        final userState = context.read<UserState>();
        final areaState = context.read<AreaState>();

        final updatedUser = user.copyWith(isSaved: true);
        userState.updateLoginUser(updatedUser);
        final prefs = await SharedPreferences.getInstance();

        debugPrint("login, 로그인 직후 저장된 phone=${prefs.getString('phone')} / area=${prefs.getString('area')}");
        LoginDebugFirestoreLogger().log(
          '✅ 로그인 성공: user=${user.name}, area=${updatedUser.areas.firstOrNull ?? ''}',
          level: 'success',
        );

        areaState.updateArea(updatedUser.areas.firstOrNull ?? '');

        if (context.mounted) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            Navigator.pushReplacementNamed(context, '/home');
          });
        }
      } else {
        if (context.mounted) {
          showFailedSnackbar(context, '이름 또는 비밀번호가 올바르지 않습니다.');
        }
        LoginDebugFirestoreLogger().log(
          '❌ 인증 실패: 이름 또는 비밀번호 불일치',
          level: 'error',
        );
      }
    } catch (e) {
      if (context.mounted) {
        showFailedSnackbar(context, '로그인 실패: $e');
      }
      LoginDebugFirestoreLogger().log('❌ 예외 발생: $e', level: 'error');
    } finally {
      setState(() => isLoading = false);
      LoginDebugFirestoreLogger().log('🔚 로그인 프로세스 종료', level: 'info');
    }
  }

  /// 비밀번호 보이기&숨기기
  void togglePassword() {
    obscurePassword = !obscurePassword;
    LoginDebugFirestoreLogger().log(
      '👁️ 비밀번호 표시 상태 변경: $obscurePassword',
      level: 'info',
    );
  }

  /// 전화번호 자동 하이픈 포맷팅
  void formatPhoneNumber(String value, StateSetter setState) {
    final numbersOnly = value.replaceAll(RegExp(r'\D'), '');
    String formatted = numbersOnly;

    if (numbersOnly.length >= 11) {
      formatted = '${numbersOnly.substring(0, 3)}-${numbersOnly.substring(3, 7)}-${numbersOnly.substring(7, 11)}';
    } else if (numbersOnly.length >= 10) {
      formatted = '${numbersOnly.substring(0, 3)}-${numbersOnly.substring(3, 6)}-${numbersOnly.substring(6, 10)}';
    }

    setState(() {
      phoneController.value = TextEditingValue(
        text: formatted,
        selection: TextSelection.collapsed(offset: formatted.length),
      );
    });
    LoginDebugFirestoreLogger().log(
      '☎️ 전화번호 포맷팅: $formatted',
      level: 'info',
    );
  }

  /// 로그인 페이지 텍스트 필드 데코레이션
  InputDecoration inputDecoration({
    required String label,
    IconData? icon,
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: label,
      prefixIcon: icon != null ? Icon(icon) : null,
      suffixIcon: suffixIcon,
      contentPadding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
      filled: true,
      fillColor: Colors.grey.shade100,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Colors.indigo, width: 2),
      ),
    );
  }

  /// 화면 종료 시
  void dispose() {
    nameController.dispose();
    phoneController.dispose();
    passwordController.dispose();
    nameFocus.dispose();
    phoneFocus.dispose();
    passwordFocus.dispose();
    LoginDebugFirestoreLogger().log('🔴 LoginController dispose()', level: 'info');
  }
}
