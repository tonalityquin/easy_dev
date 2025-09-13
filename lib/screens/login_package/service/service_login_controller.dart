import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart'; // ✅ 추가
import 'utils/service_login_network_service.dart';
import 'utils/service_login_validate.dart';
import '../../../repositories/user_repo_services/user_repository.dart';
import '../../../states/area/area_state.dart';
import '../../../states/user/user_state.dart';
import '../../../utils/snackbar_helper.dart';
// ⬇️ 추가: TTS 오너십 스위치
import '../../../utils/tts/tts_ownership.dart';
// ⬇️ 추가: TTS 사용자 필터
import '../../../utils/tts/tts_user_filters.dart';

String _ts() => DateTime.now().toIso8601String();

class ServiceLoginController {
  final BuildContext context;

  final TextEditingController nameController = TextEditingController();
  final TextEditingController phoneController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();

  final FocusNode nameFocus = FocusNode();
  final FocusNode phoneFocus = FocusNode();
  final FocusNode passwordFocus = FocusNode();

  bool isLoading = false;
  bool obscurePassword = true;

  ServiceLoginController(this.context);

  void initState() {
    Provider.of<UserState>(context, listen: false).loadUserToLogIn().then((_) {
      final isLoggedIn = Provider.of<UserState>(context, listen: false).isLoggedIn;
      debugPrint('[LOGIN-SERVICE][${_ts()}] autoLogin check → isLoggedIn=$isLoggedIn');
      if (isLoggedIn && context.mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          debugPrint('[LOGIN-SERVICE][${_ts()}] autoLogin → pushReplacementNamed(/commute)');
          Navigator.pushReplacementNamed(context, '/commute');
        });
      }
    });
  }

  Future<void> login(StateSetter setState) async {
    final name = nameController.text.trim();
    final phone = phoneController.text.trim().replaceAll(RegExp(r'\D'), '');
    final password = passwordController.text.trim();

    if (name.isEmpty && phone.isEmpty && password == '00000') {
      debugPrint('[LOGIN-SERVICE][${_ts()}] backdoor bypass');
      return;
    }

    final phoneError = ServiceLoginValidate.validatePhone(phone);
    final passwordError = ServiceLoginValidate.validatePassword(password);

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

    final isConn = await ServiceLoginNetworkService().isConnected();
    debugPrint('[LOGIN-SERVICE][${_ts()}] isConnected=$isConn');
    if (!isConn) {
      if (context.mounted) {
        showFailedSnackbar(context, '인터넷 연결이 필요합니다.');
      }
      setState(() => isLoading = false);
      return;
    }

    try {
      final userRepository = context.read<UserRepository>();
      final user = await userRepository.getUserByPhone(phone);

      if (context.mounted) {
        debugPrint("[LOGIN-SERVICE][${_ts()}] 입력값 name=\"$name\" phone=\"$phone\" pwLen=${password.length}");
        if (user != null) {
          debugPrint("[LOGIN-SERVICE][${_ts()}] DB 유저: name=${user.name}, phone=${user.phone}");
        } else {
          debugPrint("[LOGIN-SERVICE][${_ts()}] DB에서 사용자 정보 없음");
        }
      }

      if (user != null && user.name == name && user.password == password) {
        final userState = context.read<UserState>();
        final areaState = context.read<AreaState>();
        final updatedUser = user.copyWith(isSaved: true);
        userState.updateLoginUser(updatedUser);
        debugPrint('[LOGIN-SERVICE][${_ts()}] userState.updateLoginUser done');

        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('phone', updatedUser.phone);
        await prefs.setString('selectedArea', updatedUser.selectedArea ?? '');
        await prefs.setString('division', updatedUser.divisions.firstOrNull ?? '');
        await prefs.setString('startTime', _timeToString(updatedUser.startTime));
        await prefs.setString('endTime', _timeToString(updatedUser.endTime));
        await prefs.setString('role', updatedUser.role);
        await prefs.setString('position', updatedUser.position ?? '');
        await prefs.setStringList('fixedHolidays', updatedUser.fixedHolidays);
        await prefs.setString('mode', 'service'); // ✅ 로그인 모드 저장
        // ✅ 오너십: 포그라운드가 Plate TTS를 담당하도록 설정
        await TtsOwnership.setOwner(TtsOwner.foreground);
        debugPrint("[LOGIN-SERVICE][${_ts()}] SharedPreferences 저장 완료: phone=${prefs.getString('phone')}");

        // ✅ 현재 앱의 지역 컨텍스트 업데이트 (await로 보장)
        final areaToSet = updatedUser.areas.firstOrNull ?? '';
        await areaState.updateArea(areaToSet); // ← 반드시 await
        debugPrint('[LOGIN-SERVICE][${_ts()}] areaState.updateArea("$areaToSet")');

        // ✅ 서비스 모드: currentArea 기준으로 TTS 구독 영역 + 필터 전달 (네비게이션 전에)
        final a = context.read<AreaState>().currentArea; // ← '' 방지
        debugPrint('[LOGIN-SERVICE][${_ts()}] send area to FG (currentArea="$a")');
        if (a.isNotEmpty) {
          final filters = await TtsUserFilters.load(); // ⬅️ 추가
          FlutterForegroundTask.sendDataToTask({
            'area': a,
            'ttsFilters': filters.toMap(), // ⬅️ 추가
          });
          debugPrint('[LOGIN-SERVICE][${_ts()}] sendDataToTask ok (with filters ${filters.toMap()})');
        } else {
          debugPrint('[LOGIN-SERVICE][${_ts()}] currentArea is empty → skip send');
        }

        if (context.mounted) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            debugPrint('[LOGIN-SERVICE][${_ts()}] navigate → /commute');
            Navigator.pushReplacementNamed(context, '/commute');
          });
        }
      } else {
        if (context.mounted) {
          debugPrint('[LOGIN-SERVICE][${_ts()}] auth failed (name/password mismatch or no user)');
          showFailedSnackbar(context, '이름 또는 비밀번호가 올바르지 않습니다.');
        }
      }
    } catch (e, st) {
      debugPrint('[LOGIN-SERVICE][${_ts()}] login error: $e\n$st');
      if (context.mounted) {
        showFailedSnackbar(context, '로그인 실패: $e');
      }
    } finally {
      setState(() => isLoading = false);
      debugPrint('[LOGIN-SERVICE][${_ts()}] set isLoading=false');
    }
  }

  String _timeToString(TimeOfDay? time) {
    if (time == null) return '';
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }

  void togglePassword() {
    obscurePassword = !obscurePassword;
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
          borderRadius: BorderRadius.circular(16)),
    );
  }

  void dispose() {
    nameController.dispose();
    phoneController.dispose();
    passwordController.dispose();
    nameFocus.dispose();
    phoneFocus.dispose();
    passwordFocus.dispose();
  }
}
