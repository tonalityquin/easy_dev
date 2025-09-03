import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'debugs/tablet_login_debug_firestore_logger.dart';
import 'personal/tablet_personal_calendar.dart';
import 'utils/tablet_login_network_service.dart';
import 'utils/tablet_login_validate.dart';
import '../../../repositories/user/user_repository.dart';
import '../../../states/area/area_state.dart';
import '../../../states/user/user_state.dart';
import '../../../utils/snackbar_helper.dart';

class TabletLoginController {
  final BuildContext context;

  final TextEditingController nameController = TextEditingController();
  final TextEditingController phoneController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();

  final FocusNode nameFocus = FocusNode();
  final FocusNode phoneFocus = FocusNode();
  final FocusNode passwordFocus = FocusNode();

  bool isLoading = false;
  bool obscurePassword = true;

  TabletLoginController(this.context);

  void initState() {
    TabletLoginDebugFirestoreLogger().log('TabletLoginController 초기화 시작', level: 'info');

    Provider.of<UserState>(context, listen: false).loadUserToLogIn().then((_) {
      final isLoggedIn = Provider.of<UserState>(context, listen: false).isLoggedIn;

      TabletLoginDebugFirestoreLogger().log(
        '이전 로그인 정보 로드 완료: isLoggedIn=$isLoggedIn',
        level: 'success',
      );

      if (isLoggedIn && context.mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          TabletLoginDebugFirestoreLogger().log('자동 로그인: 홈 화면으로 이동', level: 'info');
          Navigator.pushReplacementNamed(context, '/home');
        });
      }
    });
  }

  Future<void> login(StateSetter setState) async {
    final name = nameController.text.trim();
    final phone = phoneController.text.trim().replaceAll(RegExp(r'\D'), '');
    final password = passwordController.text.trim();

    if (name.isEmpty && phone.isEmpty && password == '00000') {
      TabletLoginDebugFirestoreLogger().log('비밀번호 00000으로 TabletPersonalCalendar 진입', level: 'info');
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const TabletPersonalCalendar()),
      );
      return;
    }

    TabletLoginDebugFirestoreLogger().log('로그인 시도: name="$name", phone="$phone"', level: 'called');

    final phoneError = TabletLoginValidate.validatePhone(phone);
    final passwordError = TabletLoginValidate.validatePassword(password);

    if (name.isEmpty) {
      showFailedSnackbar(context, '이름을 입력해주세요.');
      TabletLoginDebugFirestoreLogger().log('이름 미입력', level: 'error');
      return;
    }
    if (phoneError != null) {
      showFailedSnackbar(context, phoneError);
      TabletLoginDebugFirestoreLogger().log('전화번호 오류: $phoneError', level: 'error');
      return;
    }
    if (passwordError != null) {
      showFailedSnackbar(context, passwordError);
      TabletLoginDebugFirestoreLogger().log('비밀번호 오류: $passwordError', level: 'error');
      return;
    }

    setState(() => isLoading = true);
    TabletLoginDebugFirestoreLogger().log('로그인 처리 중...', level: 'info');

    if (!await TabletLoginNetworkService().isConnected()) {
      if (context.mounted) {
        showFailedSnackbar(context, '인터넷 연결이 필요합니다.');
      }
      TabletLoginDebugFirestoreLogger().log('네트워크 연결 실패', level: 'error');
      setState(() => isLoading = false);
      return;
    }

    try {
      final userRepository = context.read<UserRepository>();
      final user = await userRepository.getUserByPhone(phone);

      if (user != null) {
        TabletLoginDebugFirestoreLogger().log('사용자 정보 조회 성공: ${user.name}', level: 'success');
      } else {
        TabletLoginDebugFirestoreLogger().log('사용자 정보 조회 실패', level: 'error');
      }

      if (context.mounted) {
        debugPrint("입력값: name=$name, phone=$phone, password=$password");
        if (user != null) {
          debugPrint("DB 유저: name=${user.name}, phone=${user.phone}, password=${user.password}");
        } else {
          debugPrint("DB에서 사용자 정보 없음");
        }
      }

      if (user != null && user.name == name && user.password == password) {
        final userState = context.read<UserState>();
        final areaState = context.read<AreaState>();
        final updatedUser = user.copyWith(isSaved: true);
        userState.updateLoginUser(updatedUser);

        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('phone', updatedUser.phone);
        await prefs.setString('selectedArea', updatedUser.selectedArea ?? '');
        await prefs.setString('division', updatedUser.divisions.firstOrNull ?? '');
        await prefs.setString('startTime', _timeToString(updatedUser.startTime));
        await prefs.setString('endTime', _timeToString(updatedUser.endTime));
        await prefs.setString('role', updatedUser.role);
        await prefs.setString('position', updatedUser.position ?? '');
        await prefs.setStringList('fixedHolidays', updatedUser.fixedHolidays);

        debugPrint("SharedPreferences 저장 완료: phone=${prefs.getString('phone')}");

        TabletLoginDebugFirestoreLogger().log(
          '로그인 성공: user=${user.name}, area=${updatedUser.areas.firstOrNull ?? ''}',
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
        TabletLoginDebugFirestoreLogger().log('로그인 인증 실패', level: 'error');
      }
    } catch (e) {
      if (context.mounted) {
        showFailedSnackbar(context, '로그인 실패: $e');
      }
      TabletLoginDebugFirestoreLogger().log('예외 발생: $e', level: 'error');
    } finally {
      setState(() => isLoading = false);
      TabletLoginDebugFirestoreLogger().log('로그인 프로세스 종료', level: 'info');
    }
  }

  String _timeToString(TimeOfDay? time) {
    if (time == null) return '';
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }

  void togglePassword() {
    obscurePassword = !obscurePassword;
    TabletLoginDebugFirestoreLogger().log('비밀번호 가시성 변경: $obscurePassword', level: 'info');
  }

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
    TabletLoginDebugFirestoreLogger().log('전화번호 포맷팅: $formatted', level: 'info');
  }

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

  void dispose() {
    nameController.dispose();
    phoneController.dispose();
    passwordController.dispose();
    nameFocus.dispose();
    phoneFocus.dispose();
    passwordFocus.dispose();
    TabletLoginDebugFirestoreLogger().log('TabletLoginDebugFirestoreLogger dispose() 호출됨', level: 'info');
  }
}
