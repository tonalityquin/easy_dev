import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import 'utils/service_login_network_service.dart';
import 'utils/service_login_validate.dart';
import '../../../../repositories/user_repo_services/user_repository.dart';
import '../../../../states/area/area_state.dart';
import '../../../../states/user/user_state.dart';
import '../../../../utils/snackbar_helper.dart';
import '../../../../utils/tts/tts_ownership.dart';
import '../../../../utils/tts/tts_user_filters.dart';

// ✅ 추가: endTime 예약/갱신 서비스
import 'package:easydev/services/endtime_reminder_service.dart';

String _ts() => DateTime.now().toIso8601String();

class ServiceLoginController {
  ServiceLoginController(
      this.context, {
        this.onLoginSucceeded, // ✅ 성공 시 화면에서 내비 처리(redirectAfterLogin 반영)
      });

  static const String _requiredMode = 'service';

  final BuildContext context;

  // 성공 시 호출되는 콜백(없으면 기본 동작으로 /commute 이동)
  final VoidCallback? onLoginSucceeded;

  final TextEditingController nameController = TextEditingController();
  final TextEditingController phoneController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();

  final FocusNode nameFocus = FocusNode();
  final FocusNode phoneFocus = FocusNode();
  final FocusNode passwordFocus = FocusNode();

  bool isLoading = false;
  bool obscurePassword = true;

  bool _hasModeAccess(List<String> modes, String required) {
    final req = required.trim().toLowerCase();
    return modes.any((m) => m.trim().toLowerCase() == req);
  }

  /// ✅ 자동 로그인 게이트(기존 initState 역할)
  /// - Firestore로 계정 검증에 성공하면 onLoginSucceeded() 호출 (네비게이션은 화면이 담당)
  void initState() {
    Provider.of<UserState>(context, listen: false).loadUserToLogIn().then((_) {
      final userState = Provider.of<UserState>(context, listen: false);
      final isLoggedIn = userState.isLoggedIn;
      debugPrint('[LOGIN-SERVICE][${_ts()}] autoLogin check → isLoggedIn=$isLoggedIn');

      if (!isLoggedIn || !context.mounted) return;

      // ✅ 추가: modes 권한 체크 (service 권한 없으면 자동진입 차단)
      final user = userState.user;
      final allowed = user != null && _hasModeAccess(user.modes, _requiredMode);
      if (!allowed) {
        debugPrint('[LOGIN-SERVICE][${_ts()}] autoLogin blocked: modes missing "$_requiredMode"');
        showFailedSnackbar(context, '이 계정은 service 모드 사용 권한이 없습니다.');
        return;
      }

      WidgetsBinding.instance.addPostFrameCallback((_) {
        debugPrint('[LOGIN-SERVICE][${_ts()}] autoLogin → onLoginSucceeded()');
        // 콜백이 없으면 기존 기본값(/commute)로 이동해 하위 호환 유지
        if (onLoginSucceeded != null) {
          onLoginSucceeded!();
        } else {
          Navigator.pushReplacementNamed(context, '/commute');
        }
      });
    });
  }

  /// 수동 로그인
  /// - 성공 시 onLoginSucceeded() 호출
  Future<void> login(StateSetter setState) async {
    final name = nameController.text.trim();
    final phone = phoneController.text.trim().replaceAll(RegExp(r'\D'), '');
    final password = passwordController.text.trim();

    // 백도어(테스트용) – 기존 동작 유지
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
        debugPrint(
          "[LOGIN-SERVICE][${_ts()}] 입력값 name=\"$name\" phone=\"$phone\" pwLen=${password.length}",
        );
        if (user != null) {
          debugPrint(
            "[LOGIN-SERVICE][${_ts()}] DB 유저: name=${user.name}, phone=${user.phone}",
          );
        } else {
          debugPrint("[LOGIN-SERVICE][${_ts()}] DB에서 사용자 정보 없음");
        }
      }

      if (user != null && user.name == name && user.password == password) {
        // ✅ 추가: modes 권한 체크 (service 권한 없으면 로그인 차단)
        final allowed = _hasModeAccess(user.modes, _requiredMode);
        if (!allowed) {
          debugPrint('[LOGIN-SERVICE][${_ts()}] login blocked: modes missing "$_requiredMode"');
          if (context.mounted) {
            showFailedSnackbar(context, '이 계정은 service 모드 사용 권한이 없습니다.');
          }
          return;
        }

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

        // ✅ endTime 저장 + 즉시 예약/갱신
        final endHHmm = _timeToString(updatedUser.endTime);
        await prefs.setString('endTime', endHHmm);
        if (endHHmm.isNotEmpty) {
          await EndTimeReminderService.instance.scheduleDailyOneHourBefore(endHHmm);
        } else {
          debugPrint('[LOGIN-SERVICE][${_ts()}] endTime is empty → skip schedule');
        }

        await prefs.setString('role', updatedUser.role);
        await prefs.setString('position', updatedUser.position ?? '');
        await prefs.setStringList('fixedHolidays', updatedUser.fixedHolidays);
        await prefs.setString('mode', 'service'); // ✅ 로그인 모드 저장

        // ✅ 오너십: 포그라운드가 Plate TTS를 담당하도록 설정
        await TtsOwnership.setOwner(TtsOwner.foreground);
        debugPrint(
          "[LOGIN-SERVICE][${_ts()}] SharedPreferences 저장 완료: phone=${prefs.getString('phone')}",
        );

        // ✅ 현재 앱의 지역 컨텍스트 업데이트 (await로 보장)
        final areaToSet = updatedUser.areas.firstOrNull ?? '';
        await areaState.updateArea(areaToSet); // ← 반드시 await
        debugPrint('[LOGIN-SERVICE][${_ts()}] areaState.updateArea("$areaToSet")');

        // ✅ 서비스 모드: currentArea 기준으로 TTS 구독 영역 + 필터 전달 (네비게이션 전에)
        final a = context.read<AreaState>().currentArea; // ← '' 방지
        debugPrint('[LOGIN-SERVICE][${_ts()}] send area to FG (currentArea="$a")');
        if (a.isNotEmpty) {
          final filters = await TtsUserFilters.load();
          FlutterForegroundTask.sendDataToTask({
            'area': a,
            'ttsFilters': filters.toMap(),
          });
          debugPrint('[LOGIN-SERVICE][${_ts()}] sendDataToTask ok (with filters ${filters.toMap()})');
        } else {
          debugPrint('[LOGIN-SERVICE][${_ts()}] currentArea is empty → skip send');
        }

        if (context.mounted) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            debugPrint('[LOGIN-SERVICE][${_ts()}] login success → onLoginSucceeded()');
            if (onLoginSucceeded != null) {
              onLoginSucceeded!();
            } else {
              Navigator.pushReplacementNamed(context, '/commute'); // 하위 호환
            }
          });
        }
      } else {
        if (context.mounted) {
          debugPrint(
            '[LOGIN-SERVICE][${_ts()}] auth failed (name/password mismatch or no user)',
          );
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
      contentPadding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
      filled: true,
      fillColor: Colors.grey.shade100,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
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
