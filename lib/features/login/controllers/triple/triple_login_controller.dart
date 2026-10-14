import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../shared/auth/account_code_diagnostics.dart';
import '../../../../shared/auth/account_code_number.dart';
import '../../debug/login_debug_trace.dart';

import '../../../../app/di/routes.dart';

import '../../../../app/init/work_schedule_prefs.dart';
import '../../../../features/account/applications/user_state.dart';
import '../../../../features/account/domain/repositories/user_repository.dart';
import '../../../../shared/work_session/application/work_area_session_coordinator.dart';
import '../../../dev/application/area_state.dart';
import '../area_login_session_refresher.dart';
import '../../applications/triple/triple_login_network_service.dart';
import '../../applications/triple/triple_login_validate.dart';

String _ts() => DateTime.now().toIso8601String();

void _debug(Object? message) {
  LoginDebugTrace.log('triple', message);
}

class TripleLoginController {
  TripleLoginController(
      this.context, {
        this.onLoginSucceeded,
      });

  static const String _requiredMode = 'triple';

  final BuildContext context;
  final VoidCallback? onLoginSucceeded;

  final TextEditingController nameController = TextEditingController();
  final TextEditingController codeNumberController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();

  final FocusNode nameFocus = FocusNode();
  final FocusNode codeNumberFocus = FocusNode();
  final FocusNode passwordFocus = FocusNode();

  bool isLoading = false;
  bool obscurePassword = true;

  bool _hasModeAccess(List<String> modes, String required) {
    final req = required.trim().toLowerCase();

    bool matches(String raw) {
      final v = raw.trim().toLowerCase();

      if (req == 'triple') return v == 'triple' || v == 'normal';
      if (req == 'normal') return v == 'normal' || v == 'triple';

      return v == req;
    }

    return modes.any(matches);
  }

  void initState() {
    Provider.of<UserState>(context, listen: false).loadUserToLogIn().then((_) {
      final userState = Provider.of<UserState>(context, listen: false);
      final isLoggedIn = userState.isLoggedIn;
      _debug('[LOGIN-NORMAL][${_ts()}] autoLogin check → isLoggedIn=$isLoggedIn');

      if (!isLoggedIn || !context.mounted) return;

      final session = userState.session;
      final allowed = session != null && _hasModeAccess(session.modes, _requiredMode);
      if (!allowed) {
        _debug('[LOGIN-NORMAL][${_ts()}] autoLogin blocked: modes missing "$_requiredMode"');
        return;
      }

      WidgetsBinding.instance.addPostFrameCallback((_) {
        _debug('[LOGIN-NORMAL][${_ts()}] autoLogin → onLoginSucceeded()');
        if (onLoginSucceeded != null) {
          onLoginSucceeded!();
        } else {
          Navigator.pushReplacementNamed(context, AppRoutes.tripleCommute);
        }
      });
    });
  }

  Future<bool> login(StateSetter setState) async {
    final name = nameController.text.trim();
    final codeNumber = AccountCodeNumber.normalize(codeNumberController.text);
    final password = passwordController.text.trim();
    AccountCodeDiagnostics.record(
      'triple',
      'login_attempt',
      meta: <String, Object?>{
        'codeNumber': AccountCodeNumber.mask(codeNumber),
        'nameLength': name.length,
        'passwordLength': password.length,
      },
    );


    final codeNumberError = TripleLoginValidate.validateCodeNumber(codeNumber);
    final passwordError = TripleLoginValidate.validatePassword(password);

    if (name.isEmpty) {
      return false;
    }
    if (codeNumberError != null) {
      return false;
    }
    if (passwordError != null) {
      return false;
    }

    setState(() => isLoading = true);

    final isConn = await TripleLoginNetworkService().isConnected();
    _debug('[LOGIN-NORMAL][${_ts()}] isConnected=$isConn');
    if (!isConn) {
      if (context.mounted) {
        setState(() => isLoading = false);
      }
      return false;
    }

    try {
      final userRepository = context.read<UserRepository>();
      final user = await userRepository.getUserByAccountCode(codeNumber);
      AccountCodeDiagnostics.record(
        'triple',
        user == null ? 'account_not_found' : 'account_loaded',
        meta: <String, Object?>{'codeNumber': AccountCodeNumber.mask(codeNumber)},
      );

      if (context.mounted) {
        _debug('[LOGIN-NORMAL][${_ts()}] 입력값 name="$name" codeNumber="${AccountCodeNumber.mask(codeNumber)}" pwLen=${password.length}');
        if (user != null) {
          _debug('[LOGIN-NORMAL][${_ts()}] DB 유저: name=${user.name}, codeNumber=${AccountCodeNumber.mask(user.codeNumber)}');
        } else {
          _debug('[LOGIN-NORMAL][${_ts()}] DB에서 사용자 정보 없음');
        }
      }

      if (user != null && user.name == name && user.password == password) {
        final allowed = _hasModeAccess(user.modes, _requiredMode);
        if (!allowed) {
          _debug('[LOGIN-NORMAL][${_ts()}] login blocked: modes missing "$_requiredMode"');
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
          operationLabel: 'triple',
        );
        _debug('[LOGIN-NORMAL][${_ts()}] AreaRecord 서버 강제 동기화 완료: $divisionToSet/$areaToSet');
        await userState.updateLoginUser(updatedUser);
        AccountCodeDiagnostics.record(
          'triple',
          'login_success',
          meta: <String, Object?>{'codeNumber': AccountCodeNumber.mask(codeNumber)},
        );
        _debug('[LOGIN-NORMAL][${_ts()}] userState.updateLoginUser done');

        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('codeNumber', updatedUser.codeNumber);
        await prefs.setString('selectedArea', updatedUser.selectedArea ?? '');
        await prefs.setString('division', updatedUser.divisions.firstOrNull ?? '');
        await prefs.setString('role', updatedUser.role);
        await prefs.setString('position', updatedUser.position ?? '');
        await WorkSchedulePrefs.saveUserSchedule(prefs: prefs, user: updatedUser);
        await WorkSchedulePrefs.refreshReminderFromPrefs(prefs);

        await prefs.setString('mode', 'triple');
        final currentRecord = areaState.currentRecord;
        final workSession = await WorkAreaSessionCoordinator.activate(
          currentArea: areaState.currentArea.trim(),
          division: divisionToSet,
          homeArea: areaToSet,
          mode: 'triple',
          currentIsHeadquarter: currentRecord?.isHeadquarter,
          homeIsHeadquarter:
              areaState.currentArea.trim() == areaToSet.trim()
                  ? currentRecord?.isHeadquarter
                  : null,
          source: 'legacy_triple_login',
        );
        _debug(
          '[LOGIN-NORMAL][${_ts()}] work session sync area=${workSession.currentArea} mode=${workSession.mode} foreground=${workSession.foregroundServiceRunning} appFallback=${workSession.appFallbackListening}',
        );
        _debug(
          '[LOGIN-NORMAL][${_ts()}] SharedPreferences 저장 완료: codeNumber=${prefs.getString('codeNumber')}',
        );

        if (context.mounted) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _debug('[LOGIN-NORMAL][${_ts()}] login success → onLoginSucceeded()');
            if (onLoginSucceeded != null) {
              onLoginSucceeded!();
            } else {
              Navigator.pushReplacementNamed(context, AppRoutes.tripleCommute);
            }
          });
        }
        return true;
      }

      if (context.mounted) {
        _debug('[LOGIN-NORMAL][${_ts()}] auth failed (name/password mismatch or no user)');
      }
      return false;
    } catch (e, st) {
      _debug('[LOGIN-NORMAL][${_ts()}] login error: $e\n$st');
      return false;
    } finally {
      if (context.mounted) {
        setState(() => isLoading = false);
      }
      _debug('[LOGIN-NORMAL][${_ts()}] set isLoading=false');
    }
  }


  void togglePassword() {
    obscurePassword = !obscurePassword;
  }

  void formatCodeNumber(String value, StateSetter setState) {
    final formatted = AccountCodeNumber.format(value);
    setState(() {
      codeNumberController.value = TextEditingValue(
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
            (states) => states.contains(MaterialState.focused) ? cs.primary : cs.onSurfaceVariant,
      ),
      suffixIconColor: MaterialStateColor.resolveWith(
            (states) => states.contains(MaterialState.focused) ? cs.primary : cs.onSurfaceVariant,
      ),
    );
  }

  void dispose() {
    nameController.dispose();
    codeNumberController.dispose();
    passwordController.dispose();
    nameFocus.dispose();
    codeNumberFocus.dispose();
    passwordFocus.dispose();
  }
}
