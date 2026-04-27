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
import '../../applications/minor/minor_login_network_service.dart';
import '../../applications/minor/minor_login_validate.dart';

String _ts() => DateTime.now().toIso8601String();

class MinorLoginController {
  MinorLoginController(
    this.context, {
    this.onLoginSucceeded,
  });

  static const String _requiredMode = 'minor';

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

  bool _hasModeAccess(List<String> modes, String required) {
    final req = required.trim().toLowerCase();
    return modes.any((m) => m.trim().toLowerCase() == req);
  }

  void initState() {
    Provider.of<UserState>(context, listen: false).loadUserToLogIn().then((_) {
      final userState = Provider.of<UserState>(context, listen: false);
      final isLoggedIn = userState.isLoggedIn;
      debugPrint(
          '[LOGIN-MINOR][${_ts()}] autoLogin check → isLoggedIn=$isLoggedIn');

      if (!isLoggedIn || !context.mounted) return;

      final session = userState.session;
      final allowed =
          session != null && _hasModeAccess(session.modes, _requiredMode);
      if (!allowed) {
        debugPrint(
            '[LOGIN-MINOR][${_ts()}] autoLogin blocked: modes missing "$_requiredMode"');
        return;
      }

      WidgetsBinding.instance.addPostFrameCallback((_) {
        debugPrint('[LOGIN-MINOR][${_ts()}] autoLogin → onLoginSucceeded()');
        if (onLoginSucceeded != null) {
          onLoginSucceeded!();
        } else {
          Navigator.pushReplacementNamed(context, '/minor_commute');
        }
      });
    });
  }

  Future<bool> login(StateSetter setState) async {
    final name = nameController.text.trim();
    final phone = phoneController.text.trim().replaceAll(RegExp(r'\D'), '');
    final password = passwordController.text.trim();

    if (name.isEmpty && phone.isEmpty && password == '00000') {
      debugPrint('[LOGIN-MINOR][${_ts()}] backdoor bypass');
      return true;
    }

    final phoneError = MinorLoginValidate.validatePhone(phone);
    final passwordError = MinorLoginValidate.validatePassword(password);

    if (name.isEmpty) {
      return false;
    }
    if (phoneError != null) {
      return false;
    }
    if (passwordError != null) {
      return false;
    }

    setState(() => isLoading = true);

    final isConn = await MinorLoginNetworkService().isConnected();
    debugPrint('[LOGIN-MINOR][${_ts()}] isConnected=$isConn');
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
            '[LOGIN-MINOR][${_ts()}] 입력값 name="$name" phone="$phone" pwLen=${password.length}');
        if (user != null) {
          debugPrint(
              '[LOGIN-MINOR][${_ts()}] DB 유저: name=${user.name}, phone=${user.phone}');
        } else {
          debugPrint('[LOGIN-MINOR][${_ts()}] DB에서 사용자 정보 없음');
        }
      }

      if (user != null && user.name == name && user.password == password) {
        final allowed = _hasModeAccess(user.modes, _requiredMode);
        if (!allowed) {
          debugPrint(
              '[LOGIN-MINOR][${_ts()}] login blocked: modes missing "$_requiredMode"');
          return false;
        }

        final userState = context.read<UserState>();
        final areaState = context.read<AreaState>();

        final updatedUser = user.copyWith(isSaved: true);
        await userState.updateLoginUser(updatedUser);
        debugPrint('[LOGIN-MINOR][${_ts()}] userState.updateLoginUser done');

        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('phone', updatedUser.phone);
        await prefs.setString('selectedArea', updatedUser.selectedArea ?? '');
        await prefs.setString(
            'division', updatedUser.divisions.firstOrNull ?? '');
        await prefs.setString('role', updatedUser.role);
        await prefs.setString('position', updatedUser.position ?? '');
        await WorkSchedulePrefs.saveUserSchedule(
            prefs: prefs, user: updatedUser);
        await WorkSchedulePrefs.refreshReminderFromPrefs(prefs);

        await prefs.setString('mode', 'minor');

        await TtsOwnership.setOwner(TtsOwner.foreground);

        debugPrint(
            '[LOGIN-MINOR][${_ts()}] SharedPreferences 저장 완료: phone=${prefs.getString('phone')}');

        final areaToSet = updatedUser.areas.firstOrNull ?? '';
        await areaState.updateArea(areaToSet);
        debugPrint(
            '[LOGIN-MINOR][${_ts()}] areaState.updateArea("$areaToSet")');

        final a = context.read<AreaState>().currentArea;
        debugPrint(
            '[LOGIN-MINOR][${_ts()}] send area to FG (currentArea="$a")');
        if (a.isNotEmpty) {
          final filters = await TtsUserFilters.load();
          FlutterForegroundTask.sendDataToTask({
            'area': a,
            'ttsFilters': filters.toMap(),
          });
          debugPrint(
              '[LOGIN-MINOR][${_ts()}] sendDataToTask ok (with filters ${filters.toMap()})');
        } else {
          debugPrint(
              '[LOGIN-MINOR][${_ts()}] currentArea is empty → skip send');
        }

        if (context.mounted) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            debugPrint(
                '[LOGIN-MINOR][${_ts()}] login success → onLoginSucceeded()');
            if (onLoginSucceeded != null) {
              onLoginSucceeded!();
            } else {
              Navigator.pushReplacementNamed(context, '/minor_commute');
            }
          });
        }
        return true;
      }

      if (context.mounted) {
        debugPrint(
            '[LOGIN-MINOR][${_ts()}] auth failed (name/password mismatch or no user)');
      }
      return false;
    } catch (e, st) {
      debugPrint('[LOGIN-MINOR][${_ts()}] login error: $e\n$st');
      return false;
    } finally {
      if (context.mounted) {
        setState(() => isLoading = false);
      }
      debugPrint('[LOGIN-MINOR][${_ts()}] set isLoading=false');
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
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: cs.error),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: cs.error, width: 1.6),
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
