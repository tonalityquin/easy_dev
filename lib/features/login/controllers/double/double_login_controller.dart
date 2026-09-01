import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../app/di/routes.dart';

import '../../../../app/init/work_schedule_prefs.dart';
import '../../../../features/account/applications/user_state.dart';
import '../../../../features/account/domain/repositories/user_repository.dart';
import '../../../../shared/work_session/application/work_area_session_coordinator.dart';
import '../../../dev/application/area_state.dart';
import '../area_login_session_refresher.dart';
import '../../applications/double/double_login_network_service.dart';
import '../../applications/double/double_login_validate.dart';

String _ts() => DateTime.now().toIso8601String();

class DoubleLoginController {
  DoubleLoginController(
    this.context, {
    this.onLoginSucceeded,
  });

  static const String _requiredMode = 'double';

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

    bool matches(String raw) {
      final v = raw.trim().toLowerCase();

      if (req == 'double') return v == 'double' || v == 'lite' || v == 'light';
      if (req == 'lite' || req == 'light') {
        return v == 'double' || v == 'lite' || v == 'light';
      }

      return v == req;
    }

    return modes.any(matches);
  }

  void initState() {
    Provider.of<UserState>(context, listen: false).loadUserToLogIn().then((_) {
      final userState = Provider.of<UserState>(context, listen: false);
      final isLoggedIn = userState.isLoggedIn;
      debugPrint(
          '[LOGIN-LITE][${_ts()}] autoLogin check → isLoggedIn=$isLoggedIn');

      if (!isLoggedIn || !context.mounted) return;

      final session = userState.session;
      final allowed =
          session != null && _hasModeAccess(session.modes, _requiredMode);
      if (!allowed) {
        debugPrint(
            '[LOGIN-LITE][${_ts()}] autoLogin blocked: modes missing "$_requiredMode"');
        return;
      }

      WidgetsBinding.instance.addPostFrameCallback((_) {
        debugPrint('[LOGIN-LITE][${_ts()}] autoLogin → onLoginSucceeded()');
        if (onLoginSucceeded != null) {
          onLoginSucceeded!();
        } else {
          Navigator.pushReplacementNamed(context, AppRoutes.doubleCommute);
        }
      });
    });
  }

  Future<bool> login(StateSetter setState) async {
    final name = nameController.text.trim();
    final phone = phoneController.text.trim().replaceAll(RegExp(r'\D'), '');
    final password = passwordController.text.trim();

    if (name.isEmpty && phone.isEmpty && password == '00000') {
      debugPrint('[LOGIN-LITE][${_ts()}] backdoor bypass');
      return true;
    }

    final phoneError = DoubleLoginValidate.validatePhone(phone);
    final passwordError = DoubleLoginValidate.validatePassword(password);

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

    final isConn = await DoubleLoginNetworkService().isConnected();
    debugPrint('[LOGIN-LITE][${_ts()}] isConnected=$isConn');

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
            '[LOGIN-LITE][${_ts()}] 입력값 name="$name" phone="$phone" pwLen=${password.length}');
        if (user != null) {
          debugPrint(
              '[LOGIN-LITE][${_ts()}] DB 유저: name=${user.name}, phone=${user.phone}');
        } else {
          debugPrint('[LOGIN-LITE][${_ts()}] DB에서 사용자 정보 없음');
        }
      }

      if (user != null && user.name == name && user.password == password) {
        final allowed = _hasModeAccess(user.modes, _requiredMode);
        if (!allowed) {
          debugPrint(
              '[LOGIN-LITE][${_ts()}] login blocked: modes missing "$_requiredMode"');
          return false;
        }

        final userState = context.read<UserState>();
        final areaState = context.read<AreaState>();

        final updatedUser = user.copyWith(isSaved: true);
        final areaToSet = updatedUser.areas.firstOrNull ?? '';
        final divisionToSet = updatedUser.divisions.firstOrNull ?? '';
        await AreaLoginSessionRefresher.refresh(
          context: context,
          areaState: areaState,
          division: divisionToSet,
          area: areaToSet,
          operationLabel: 'double',
        );
        debugPrint('[LOGIN-LITE][${_ts()}] AreaRecord 서버 강제 동기화 완료: $divisionToSet/$areaToSet');
        await userState.updateLoginUser(updatedUser);
        debugPrint('[LOGIN-LITE][${_ts()}] userState.updateLoginUser done');

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

        await prefs.setString('mode', 'lite');
        final currentRecord = areaState.currentRecord;
        final workSession = await WorkAreaSessionCoordinator.activate(
          currentArea: areaState.currentArea.trim(),
          division: divisionToSet,
          homeArea: areaToSet,
          mode: 'lite',
          currentIsHeadquarter: currentRecord?.isHeadquarter,
          homeIsHeadquarter:
              areaState.currentArea.trim() == areaToSet.trim()
                  ? currentRecord?.isHeadquarter
                  : null,
          source: 'legacy_double_login',
        );
        debugPrint(
          '[LOGIN-LITE][${_ts()}] work session sync area=${workSession.currentArea} mode=${workSession.mode} foreground=${workSession.foregroundServiceRunning} appFallback=${workSession.appFallbackListening}',
        );
        debugPrint(
          '[LOGIN-LITE][${_ts()}] SharedPreferences 저장 완료: phone=${prefs.getString('phone')}',
        );

        if (context.mounted) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            debugPrint(
                '[LOGIN-LITE][${_ts()}] login success → onLoginSucceeded()');
            if (onLoginSucceeded != null) {
              onLoginSucceeded!();
            } else {
              Navigator.pushReplacementNamed(context, AppRoutes.doubleCommute);
            }
          });
        }
        return true;
      }

      if (context.mounted) {
        debugPrint(
            '[LOGIN-LITE][${_ts()}] auth failed (name/password mismatch or no user)');
      }
      return false;
    } catch (e, st) {
      debugPrint('[LOGIN-LITE][${_ts()}] login error: $e\n$st');
      return false;
    } finally {
      if (context.mounted) {
        setState(() => isLoading = false);
      }
      debugPrint('[LOGIN-LITE][${_ts()}] set isLoading=false');
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
