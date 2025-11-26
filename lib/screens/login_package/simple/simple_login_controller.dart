// lib/screens/login/simple/simple_login_controller.dart
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import 'utils/simple_login_network_service.dart';
import 'utils/simple_login_validate.dart';
import '../../../repositories/user_repo_services/user_repository.dart';
import '../../../states/area/area_state.dart';
import '../../../states/user/user_state.dart';
import '../../../utils/snackbar_helper.dart';
import '../../../utils/tts/tts_ownership.dart';
import '../../../utils/tts/tts_user_filters.dart';

// ✅ 추가: endTime 예약/갱신 서비스
import 'package:easydev/services/endtime_reminder_service.dart';

String _ts() => DateTime.now().toIso8601String();

// UserState 에서 사용하는 cachedUserJson 키와 동일한 문자열
const String _prefsKeyCachedUser = 'cachedUserJson';

class SimpleLoginController {
  SimpleLoginController(
      this.context, {
        this.onLoginSucceeded, // ✅ 성공 시 화면에서 내비 처리(redirectAfterLogin 반영)
      });

  final BuildContext context;

  // 성공 시 호출되는 콜백(없으면 기본 동작으로 /simple_commute 이동)
  final VoidCallback? onLoginSucceeded;

  final TextEditingController nameController = TextEditingController();
  final TextEditingController phoneController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();

  final FocusNode nameFocus = FocusNode();
  final FocusNode phoneFocus = FocusNode();
  final FocusNode passwordFocus = FocusNode();

  bool isLoading = false;
  bool obscurePassword = true;

  /// ✅ 자동 로그인 게이트(기존 initState 역할)
  /// - 약식 로그인(Simple 모드)에서는 **항상 local-only** 경로만 사용
  ///   (UserState.loadUserToLogInLocalOnly → SharedPreferences 기반 복원)
  void initState() {
    final userState = Provider.of<UserState>(context, listen: false);

    userState.loadUserToLogInLocalOnly().then((_) {
      final isLoggedIn = userState.isLoggedIn;
      debugPrint(
          '[LOGIN-SIMPLE][${_ts()}] autoLogin(local-only) → isLoggedIn=$isLoggedIn');
      if (isLoggedIn && context.mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          debugPrint(
              '[LOGIN-SIMPLE][${_ts()}] autoLogin → onLoginSucceeded()');
          // 콜백이 없으면 기본값(/simple_commute)로 이동
          if (onLoginSucceeded != null) {
            onLoginSucceeded!();
          } else {
            Navigator.pushReplacementNamed(context, '/simple_commute');
          }
        });
      }
    });
  }

  /// 수동 로그인
  /// - 최초 로그인: Firestore 1 read(getUserByPhone) + 1 write(updateUser) 유지
  /// - 이후 로그인: cachedUserJson 과 입력값이 일치하면 local-only 경로로 처리
  Future<void> login(StateSetter setState) async {
    final name = nameController.text.trim();
    final phone = phoneController.text.trim().replaceAll(RegExp(r'\D'), '');
    final password = passwordController.text.trim();

    // 백도어(테스트용) – 기존 동작 유지
    if (name.isEmpty && phone.isEmpty && password == '00000') {
      debugPrint('[LOGIN-SIMPLE][${_ts()}] backdoor bypass');
      return;
    }

    final phoneError = SimpleLoginValidate.validatePhone(phone);
    final passwordError = SimpleLoginValidate.validatePassword(password);

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

    final prefs = await SharedPreferences.getInstance();

    // 🔹 1단계: 가능한 경우 local-only 로그인 시도
    //   - UserState.saveCardToUserPhone()에서 저장한 cachedUserJson 기반
    try {
      final cachedJson = prefs.getString(_prefsKeyCachedUser);
      if (cachedJson != null && cachedJson.isNotEmpty) {
        final decoded = jsonDecode(cachedJson) as Map<String, dynamic>;
        final cachedName =
            (decoded['name'] as String?)?.trim() ?? '';
        final cachedPhoneRaw =
            (decoded['phone'] as String?)?.trim() ?? '';
        final cachedPhone =
        cachedPhoneRaw.replaceAll(RegExp(r'\D'), '');
        final cachedPassword =
            (decoded['password'] as String?) ?? '';

        if (cachedName == name &&
            cachedPhone == phone &&
            cachedPassword == password) {
          debugPrint(
              '[LOGIN-SIMPLE][${_ts()}] local-only login hit (cachedUserJson match)');

          // 모드 표시를 simple 로 맞춰둔다 (허브 카드 등에서 사용)
          await prefs.setString('mode', 'simple');

          final userState = context.read<UserState>();
          await userState.loadUserToLogInLocalOnly();
          final isLoggedIn = userState.isLoggedIn;
          debugPrint(
              '[LOGIN-SIMPLE][${_ts()}] local-only login result → isLoggedIn=$isLoggedIn');

          if (isLoggedIn && context.mounted) {
            // 약식 로그인에서도 TTS 오너십은 포그라운드로 맞춰둠
            await TtsOwnership.setOwner(TtsOwner.foreground);

            WidgetsBinding.instance.addPostFrameCallback((_) {
              debugPrint(
                  '[LOGIN-SIMPLE][${_ts()}] local-only login → onLoginSucceeded()');
              if (onLoginSucceeded != null) {
                onLoginSucceeded!();
              } else {
                Navigator.pushReplacementNamed(
                    context, '/simple_commute');
              }
            });
          }
          // ✅ local-only 경로에서는 Firestore/네트워크 호출 없이 종료
          return;
        }
      }
    } catch (e, st) {
      debugPrint(
          '[LOGIN-SIMPLE][${_ts()}] local-only login decode 실패: $e\n$st');
      // local-only 실패 시에는 그냥 아래 Firestore 로그인으로 폴백
    }

    // 🔹 2단계: local-only 매치가 안 되면, "최초 로그인" 또는 갱신 케이스로 보고
    //          기존 Firestore 로그인 플로우를 그대로 수행
    setState(() => isLoading = true);

    final isConn = await SimpleLoginNetworkService().isConnected();
    debugPrint('[LOGIN-SIMPLE][${_ts()}] isConnected=$isConn');
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
        debugPrint(
            "[LOGIN-SIMPLE][${_ts()}] 입력값 name=\"$name\" phone=\"$phone\" pwLen=${password.length}");
        if (user != null) {
          debugPrint(
              "[LOGIN-SIMPLE][${_ts()}] DB 유저: name=${user.name}, phone=${user.phone}");
        } else {
          debugPrint("[LOGIN-SIMPLE][${_ts()}] DB에서 사용자 정보 없음");
        }
      }

      if (user != null && user.name == name && user.password == password) {
        final userState = context.read<UserState>();
        final areaState = context.read<AreaState>();
        final updatedUser = user.copyWith(isSaved: true);
        userState.updateLoginUser(updatedUser);
        debugPrint(
            '[LOGIN-SIMPLE][${_ts()}] userState.updateLoginUser done');

        await prefs.setString('phone', updatedUser.phone);
        await prefs.setString(
            'selectedArea', updatedUser.selectedArea ?? '');
        await prefs.setString(
            'division', updatedUser.divisions.firstOrNull ?? '');
        await prefs.setString(
            'startTime', _timeToString(updatedUser.startTime));

        // ✅ endTime 저장 + 즉시 예약/갱신
        final endHHmm = _timeToString(updatedUser.endTime);
        await prefs.setString('endTime', endHHmm);
        await EndtimeReminderService.instance
            .scheduleDailyOneHourBefore(endHHmm);

        await prefs.setString('role', updatedUser.role);
        await prefs.setString(
            'position', updatedUser.position ?? '');
        await prefs.setStringList(
            'fixedHolidays', updatedUser.fixedHolidays);
        await prefs.setString('mode', 'simple'); // ✅ 약식 로그인 모드 저장

        // ✅ 오너십: 포그라운드가 Plate TTS를 담당하도록 설정
        await TtsOwnership.setOwner(TtsOwner.foreground);
        debugPrint(
            "[LOGIN-SIMPLE][${_ts()}] SharedPreferences 저장 완료: phone=${prefs.getString('phone')}");

        // ✅ 현재 앱의 지역 컨텍스트 업데이트 (await로 보장)
        final areaToSet = updatedUser.areas.firstOrNull ?? '';
        await areaState.updateArea(areaToSet); // ← 반드시 await
        debugPrint(
            '[LOGIN-SIMPLE][${_ts()}] areaState.updateArea("$areaToSet")');

        // ✅ 서비스 모드 때와 동일하게 currentArea 기준으로
        //    TTS 구독 영역 + 필터 전달 (네비게이션 전에)
        final a = context.read<AreaState>().currentArea; // ← '' 방지
        debugPrint(
            '[LOGIN-SIMPLE][${_ts()}] send area to FG (currentArea="$a")');
        if (a.isNotEmpty) {
          final filters = await TtsUserFilters.load();
          FlutterForegroundTask.sendDataToTask({
            'area': a,
            'ttsFilters': filters.toMap(),
          });
          debugPrint(
              '[LOGIN-SIMPLE][${_ts()}] sendDataToTask ok (with filters ${filters.toMap()})');
        } else {
          debugPrint(
              '[LOGIN-SIMPLE][${_ts()}] currentArea is empty → skip send');
        }

        if (context.mounted) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            debugPrint(
                '[LOGIN-SIMPLE][${_ts()}] login success → onLoginSucceeded()');
            if (onLoginSucceeded != null) {
              onLoginSucceeded!();
            } else {
              Navigator.pushReplacementNamed(
                  context, '/simple_commute'); // 하위 호환
            }
          });
        }
      } else {
        if (context.mounted) {
          debugPrint(
              '[LOGIN-SIMPLE][${_ts()}] auth failed (name/password mismatch or no user)');
          showFailedSnackbar(
              context, '이름 또는 비밀번호가 올바르지 않습니다.');
        }
      }
    } catch (e, st) {
      debugPrint('[LOGIN-SIMPLE][${_ts()}] login error: $e\n$st');
      if (context.mounted) {
        showFailedSnackbar(context, '로그인 실패: $e');
      }
    } finally {
      setState(() => isLoading = false);
      debugPrint('[LOGIN-SIMPLE][${_ts()}] set isLoading=false');
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
      formatted =
      '${numbersOnly.substring(0, 3)}-${numbersOnly.substring(3, 7)}-${numbersOnly.substring(7, 11)}';
    } else if (numbersOnly.length >= 10) {
      formatted =
      '${numbersOnly.substring(0, 3)}-${numbersOnly.substring(3, 6)}-${numbersOnly.substring(6, 10)}';
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
      contentPadding:
      const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
      filled: true,
      fillColor: Colors.grey.shade100,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
      focusedBorder:
      OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
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
