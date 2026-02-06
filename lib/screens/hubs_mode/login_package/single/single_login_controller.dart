import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import 'utils/single_login_network_service.dart';
import 'utils/single_login_validate.dart';
import '../../../../repositories/user_repo_services/user_repository.dart';
import '../../../../states/area/area_state.dart';
import '../../../../states/user/user_state.dart';
import '../../../../utils/snackbar_helper.dart';
import '../../../../utils/tts/tts_ownership.dart';
import '../../../../utils/tts/tts_user_filters.dart';

// ✅ 추가: endTime 예약/갱신 서비스
import 'package:easydev/services/endtime_reminder_service.dart';

String _ts() => DateTime.now().toIso8601String();

// UserState 에서 사용하는 cachedUserJson 키와 동일한 문자열
const String _prefsKeyCachedUser = 'cachedUserJson';

class SingleLoginController {
  SingleLoginController(
      this.context, {
        this.onLoginSucceeded,
      });

  static const String _requiredMode = 'single';

  final BuildContext context;
  final VoidCallback? onLoginSucceeded;

  final TextEditingController nameController = TextEditingController();
  final TextEditingController phoneController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();

  final FocusNode nameFocus = FocusNode();
  final FocusNode phoneFocus = FocusNode();
  final FocusNode passwordFocus = FocusNode();

  bool isLoading = false;
  bool obscurePassword = true;

  bool _hasModeAccessFromList(List<String> modes, String required) {
    final req = required.trim().toLowerCase();

    bool matches(String raw) {
      final v = raw.trim().toLowerCase();

      // ✅ 하위 호환: simple ↔ single
      if (req == 'single') return v == 'single' || v == 'simple';
      if (req == 'simple') return v == 'single' || v == 'simple';

      return v == req;
    }

    return modes.any(matches);
  }

  List<String> _extractModes(dynamic raw) {
    if (raw is List) {
      return raw.map((e) => e.toString()).toList();
    }
    return const <String>[];
  }

  /// ✅ 자동 로그인(약식은 local-only)
  void initState() {
    final userState = Provider.of<UserState>(context, listen: false);

    userState.loadUserToLogInLocalOnly().then((_) {
      final isLoggedIn = userState.isLoggedIn;
      debugPrint('[LOGIN-SIMPLE][${_ts()}] autoLogin(local-only) → isLoggedIn=$isLoggedIn');

      if (!isLoggedIn || !context.mounted) return;

      final user = userState.user;
      final allowed = user != null && _hasModeAccessFromList(user.modes, _requiredMode);
      if (!allowed) {
        debugPrint('[LOGIN-SIMPLE][${_ts()}] autoLogin blocked: modes missing "$_requiredMode"');
        showFailedSnackbar(context, '이 계정은 single(구 simple) 모드 사용 권한이 없습니다.');
        return;
      }

      WidgetsBinding.instance.addPostFrameCallback((_) {
        debugPrint('[LOGIN-SIMPLE][${_ts()}] autoLogin → onLoginSucceeded()');
        if (onLoginSucceeded != null) {
          onLoginSucceeded!();
        } else {
          Navigator.pushReplacementNamed(context, '/single_commute');
        }
      });
    });
  }

  Future<void> login(StateSetter setState) async {
    final name = nameController.text.trim();
    final phone = phoneController.text.trim().replaceAll(RegExp(r'\D'), '');
    final password = passwordController.text.trim();

    if (name.isEmpty && phone.isEmpty && password == '00000') {
      debugPrint('[LOGIN-SIMPLE][${_ts()}] backdoor bypass');
      return;
    }

    final phoneError = SingleLoginValidate.validatePhone(phone);
    final passwordError = SingleLoginValidate.validatePassword(password);

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

    // 🔹 1) local-only 로그인 시도(cachedUserJson)
    try {
      final cachedJson = prefs.getString(_prefsKeyCachedUser);
      if (cachedJson != null && cachedJson.isNotEmpty) {
        final decoded = jsonDecode(cachedJson) as Map<String, dynamic>;
        final cachedName = (decoded['name'] as String?)?.trim() ?? '';
        final cachedPhoneRaw = (decoded['phone'] as String?)?.trim() ?? '';
        final cachedPhone = cachedPhoneRaw.replaceAll(RegExp(r'\D'), '');
        final cachedPassword = (decoded['password'] as String?) ?? '';

        if (cachedName == name && cachedPhone == phone && cachedPassword == password) {
          final cachedModes = _extractModes(decoded['modes']);
          final allowed = _hasModeAccessFromList(cachedModes, _requiredMode);
          if (!allowed) {
            debugPrint(
              '[LOGIN-SIMPLE][${_ts()}] local-only blocked: modes missing "$_requiredMode" → fallback to Firestore',
            );
          } else {
            debugPrint('[LOGIN-SIMPLE][${_ts()}] local-only login hit (cachedUserJson match)');

            await prefs.setString('mode', 'simple');

            final userState = context.read<UserState>();
            await userState.loadUserToLogInLocalOnly();

            final isLoggedIn = userState.isLoggedIn;
            debugPrint('[LOGIN-SIMPLE][${_ts()}] local-only login result → isLoggedIn=$isLoggedIn');

            if (isLoggedIn && context.mounted) {
              await TtsOwnership.setOwner(TtsOwner.foreground);

              WidgetsBinding.instance.addPostFrameCallback((_) {
                debugPrint('[LOGIN-SIMPLE][${_ts()}] local-only login → onLoginSucceeded()');
                if (onLoginSucceeded != null) {
                  onLoginSucceeded!();
                } else {
                  Navigator.pushReplacementNamed(context, '/single_commute');
                }
              });
            }
            return;
          }
        }
      }
    } catch (e, st) {
      debugPrint('[LOGIN-SIMPLE][${_ts()}] local-only login decode 실패: $e\n$st');
    }

    // 🔹 2) Firestore 로그인(폴백)
    setState(() => isLoading = true);

    final isConn = await SingleLoginNetworkService().isConnected();
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
        debugPrint('[LOGIN-SIMPLE][${_ts()}] 입력값 name="$name" phone="$phone" pwLen=${password.length}');
        if (user != null) {
          debugPrint('[LOGIN-SIMPLE][${_ts()}] DB 유저: name=${user.name}, phone=${user.phone}');
        } else {
          debugPrint('[LOGIN-SIMPLE][${_ts()}] DB에서 사용자 정보 없음');
        }
      }

      if (user != null && user.name == name && user.password == password) {
        final allowed = _hasModeAccessFromList(user.modes, _requiredMode);
        if (!allowed) {
          debugPrint('[LOGIN-SIMPLE][${_ts()}] login blocked: modes missing "$_requiredMode"');
          if (context.mounted) {
            showFailedSnackbar(context, '이 계정은 single(구 simple) 모드 사용 권한이 없습니다.');
          }
          return;
        }

        final userState = context.read<UserState>();
        final areaState = context.read<AreaState>();
        final updatedUser = user.copyWith(isSaved: true);

        userState.updateLoginUser(updatedUser);
        debugPrint('[LOGIN-SIMPLE][${_ts()}] userState.updateLoginUser done');

        await prefs.setString('phone', updatedUser.phone);
        await prefs.setString('selectedArea', updatedUser.selectedArea ?? '');
        await prefs.setString('division', updatedUser.divisions.firstOrNull ?? '');
        await prefs.setString('startTime', _timeToString(updatedUser.startTime));

        final endHHmm = _timeToString(updatedUser.endTime);
        await prefs.setString('endTime', endHHmm);
        if (endHHmm.isNotEmpty) {
          await EndTimeReminderService.instance.scheduleDailyOneHourBefore(endHHmm);
        } else {
          debugPrint('[LOGIN-SIMPLE][${_ts()}] endTime is empty → skip schedule');
        }

        await prefs.setString('role', updatedUser.role);
        await prefs.setString('position', updatedUser.position ?? '');
        await prefs.setStringList('fixedHolidays', updatedUser.fixedHolidays);

        await prefs.setString('mode', 'simple');

        await TtsOwnership.setOwner(TtsOwner.foreground);

        debugPrint('[LOGIN-SIMPLE][${_ts()}] SharedPreferences 저장 완료: phone=${prefs.getString('phone')}');

        final areaToSet = updatedUser.areas.firstOrNull ?? '';
        await areaState.updateArea(areaToSet);
        debugPrint('[LOGIN-SIMPLE][${_ts()}] areaState.updateArea("$areaToSet")');

        final a = context.read<AreaState>().currentArea;
        debugPrint('[LOGIN-SIMPLE][${_ts()}] send area to FG (currentArea="$a")');
        if (a.isNotEmpty) {
          final filters = await TtsUserFilters.load();
          FlutterForegroundTask.sendDataToTask({
            'area': a,
            'ttsFilters': filters.toMap(),
          });
          debugPrint('[LOGIN-SIMPLE][${_ts()}] sendDataToTask ok (with filters ${filters.toMap()})');
        } else {
          debugPrint('[LOGIN-SIMPLE][${_ts()}] currentArea is empty → skip send');
        }

        if (context.mounted) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            debugPrint('[LOGIN-SIMPLE][${_ts()}] login success → onLoginSucceeded()');
            if (onLoginSucceeded != null) {
              onLoginSucceeded!();
            } else {
              Navigator.pushReplacementNamed(context, '/single_commute');
            }
          });
        }
      } else {
        if (context.mounted) {
          debugPrint('[LOGIN-SIMPLE][${_ts()}] auth failed (name/password mismatch or no user)');
          showFailedSnackbar(context, '이름 또는 비밀번호가 올바르지 않습니다.');
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

  /// ✅ 컨셉 테마 반영: 하드코딩 제거, ColorScheme 기반으로 전환
  InputDecoration inputDecoration({
    required String label,
    IconData? icon,
    Widget? suffixIcon,
  }) {
    final cs = Theme.of(context).colorScheme;

    return InputDecoration(
      labelText: label,
      hintText: label,
      prefixIcon: icon != null ? Icon(icon) : null,
      suffixIcon: suffixIcon,
      contentPadding: const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
      filled: true,
      fillColor: cs.surfaceContainerLow,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: cs.outlineVariant),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: cs.outlineVariant),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: cs.primary, width: 1.6),
      ),
      prefixIconColor: MaterialStateColor.resolveWith(
            (states) => states.contains(MaterialState.focused) ? cs.primary : cs.onSurfaceVariant,
      ),
      suffixIconColor: MaterialStateColor.resolveWith(
            (states) => states.contains(MaterialState.focused) ? cs.primary : cs.onSurfaceVariant,
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
  }
}
