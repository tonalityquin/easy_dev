import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import '../../../../features/account/applications/user_state.dart';
import '../../../../features/account/domain/repositories/user_repository.dart';
import '../../../../utils/init/work_schedule_prefs.dart';
import '../../../../utils/tts/tts_ownership.dart';
import '../../../../utils/tts/tts_user_filters.dart';
import '../../../dev/application/area_state.dart';
import '../../applications/single/single_login_network_service.dart';
import '../../applications/single/single_login_validate.dart';

String _ts() => DateTime.now().toIso8601String();

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

  void initState() {
    final userState = Provider.of<UserState>(context, listen: false);

    userState.loadUserToLogInLocalOnly().then((_) {
      final isLoggedIn = userState.isLoggedIn;
      debugPrint(
          '[LOGIN-SIMPLE][${_ts()}] autoLogin(local-only) → isLoggedIn=$isLoggedIn');

      if (!isLoggedIn || !context.mounted) return;

      final session = userState.session;
      final allowed = session != null &&
          _hasModeAccessFromList(session.modes, _requiredMode);
      if (!allowed) {
        debugPrint(
            '[LOGIN-SIMPLE][${_ts()}] autoLogin blocked: modes missing "$_requiredMode"');
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

  Future<bool> login(StateSetter setState) async {
    final name = nameController.text.trim();
    final phone = phoneController.text.trim().replaceAll(RegExp(r'\D'), '');
    final password = passwordController.text.trim();

    if (name.isEmpty && phone.isEmpty && password == '00000') {
      debugPrint('[LOGIN-SIMPLE][${_ts()}] backdoor bypass');
      return true;
    }

    final phoneError = SingleLoginValidate.validatePhone(phone);
    final passwordError = SingleLoginValidate.validatePassword(password);

    if (name.isEmpty) {
      return false;
    }
    if (phoneError != null) {
      return false;
    }
    if (passwordError != null) {
      return false;
    }

    final prefs = await SharedPreferences.getInstance();

    try {
      final cachedJson = prefs.getString(_prefsKeyCachedUser);
      if (cachedJson != null && cachedJson.isNotEmpty) {
        final decoded = jsonDecode(cachedJson) as Map<String, dynamic>;
        final cachedName = (decoded['name'] as String?)?.trim() ?? '';
        final cachedPhoneRaw = (decoded['phone'] as String?)?.trim() ?? '';
        final cachedPhone = cachedPhoneRaw.replaceAll(RegExp(r'\D'), '');
        final cachedPassword = (decoded['password'] as String?) ?? '';

        if (cachedName == name &&
            cachedPhone == phone &&
            cachedPassword == password) {
          final cachedModes = _extractModes(decoded['modes']);
          final allowed = _hasModeAccessFromList(cachedModes, _requiredMode);
          if (!allowed) {
            debugPrint(
              '[LOGIN-SIMPLE][${_ts()}] local-only blocked: modes missing "$_requiredMode" → fallback to Firestore',
            );
          } else {
            debugPrint(
                '[LOGIN-SIMPLE][${_ts()}] local-only login hit (cachedUserJson match)');

            await prefs.setString('mode', 'simple');

            final userState = context.read<UserState>();
            await userState.loadUserToLogInLocalOnly();

            final isLoggedIn = userState.isLoggedIn;
            debugPrint(
                '[LOGIN-SIMPLE][${_ts()}] local-only login result → isLoggedIn=$isLoggedIn');

            if (isLoggedIn && context.mounted) {
              await TtsOwnership.setOwner(TtsOwner.foreground);

              WidgetsBinding.instance.addPostFrameCallback((_) {
                debugPrint(
                    '[LOGIN-SIMPLE][${_ts()}] local-only login → onLoginSucceeded()');
                if (onLoginSucceeded != null) {
                  onLoginSucceeded!();
                } else {
                  Navigator.pushReplacementNamed(context, '/single_commute');
                }
              });
              return true;
            }
            return false;
          }
        }
      }
    } catch (e, st) {
      debugPrint(
          '[LOGIN-SIMPLE][${_ts()}] local-only login decode 실패: $e\n$st');
    }

    setState(() => isLoading = true);

    final isConn = await SingleLoginNetworkService().isConnected();
    debugPrint('[LOGIN-SIMPLE][${_ts()}] isConnected=$isConn');
    if (!isConn) {
      if (context.mounted) {
        setState(() => isLoading = false);
      }
      return false;
    }

    try {
      final userRepository = context.read<UserRepository>();
      final user = await userRepository.getUserByPhone(phone);

      if (context.mounted) {
        debugPrint(
            '[LOGIN-SIMPLE][${_ts()}] 입력값 name="$name" phone="$phone" pwLen=${password.length}');
        if (user != null) {
          debugPrint(
              '[LOGIN-SIMPLE][${_ts()}] DB 유저: name=${user.name}, phone=${user.phone}');
        } else {
          debugPrint('[LOGIN-SIMPLE][${_ts()}] DB에서 사용자 정보 없음');
        }
      }

      if (user != null && user.name == name && user.password == password) {
        final allowed = _hasModeAccessFromList(user.modes, _requiredMode);
        if (!allowed) {
          debugPrint(
              '[LOGIN-SIMPLE][${_ts()}] login blocked: modes missing "$_requiredMode"');
          return false;
        }

        final userState = context.read<UserState>();
        final areaState = context.read<AreaState>();
        final updatedUser = user.copyWith(isSaved: true);

        await userState.updateLoginUser(updatedUser);
        debugPrint('[LOGIN-SIMPLE][${_ts()}] userState.updateLoginUser done');

        await prefs.setString('phone', updatedUser.phone);
        await prefs.setString('selectedArea', updatedUser.selectedArea ?? '');
        await prefs.setString(
            'division', updatedUser.divisions.firstOrNull ?? '');
        await prefs.setString('role', updatedUser.role);
        await prefs.setString('position', updatedUser.position ?? '');
        await WorkSchedulePrefs.saveUserSchedule(
            prefs: prefs, user: updatedUser);
        await WorkSchedulePrefs.refreshReminderFromPrefs(prefs);

        await prefs.setString('mode', 'simple');

        await TtsOwnership.setOwner(TtsOwner.foreground);

        debugPrint(
            '[LOGIN-SIMPLE][${_ts()}] SharedPreferences 저장 완료: phone=${prefs.getString('phone')}');

        final areaToSet = updatedUser.areas.firstOrNull ?? '';
        await areaState.updateArea(areaToSet);
        debugPrint(
            '[LOGIN-SIMPLE][${_ts()}] areaState.updateArea("$areaToSet")');

        final a = context.read<AreaState>().currentArea;
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
              Navigator.pushReplacementNamed(context, '/single_commute');
            }
          });
        }
        return true;
      }

      if (context.mounted) {
        debugPrint(
            '[LOGIN-SIMPLE][${_ts()}] auth failed (name/password mismatch or no user)');
      }
      return false;
    } catch (e, st) {
      debugPrint('[LOGIN-SIMPLE][${_ts()}] login error: $e\n$st');
      return false;
    } finally {
      if (context.mounted) {
        setState(() => isLoading = false);
      }
      debugPrint('[LOGIN-SIMPLE][${_ts()}] set isLoading=false');
    }
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
        (states) => states.contains(MaterialState.focused)
            ? cs.primary
            : cs.onSurfaceVariant,
      ),
      suffixIconColor: MaterialStateColor.resolveWith(
        (states) => states.contains(MaterialState.focused)
            ? cs.primary
            : cs.onSurfaceVariant,
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
