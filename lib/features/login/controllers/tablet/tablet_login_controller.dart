import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../app/di/routes.dart';
import '../../../../app/utils/dev_firebase_debug_dialog.dart';
import '../../../../features/account/applications/user_state.dart';
import '../../../../features/account/domain/models/tablet/tablet_model.dart';
import '../../../../features/account/domain/repositories/user_repository.dart';
import '../../../../features/tablet/applications/tablet_pad_mode_state.dart';
import '../../../../shared/auth/tablet_phone.dart';
import '../../../../shared/work_session/application/work_area_session_coordinator.dart';
import '../../../dev/application/area_state.dart';
import '../area_login_session_refresher.dart';
import '../../applications/tablet/tablet_login_network_service.dart';
import '../../applications/tablet/tablet_login_validate.dart';

String _ts() => DateTime.now().toIso8601String();


class TabletCredentialAuthenticationResult {
  const TabletCredentialAuthenticationResult({
    required this.success,
    required this.message,
    this.tablet,
  });

  final bool success;
  final String message;
  final TabletModel? tablet;
}

class TabletLoginController {
  TabletLoginController(
    this.context, {
    this.onLoginSucceeded,
  });

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

  bool _inited = false;

  PadMode get _targetPadMode => PadMode.big;

  String get _savedMode => 'tablet';

  Future<bool> tryAutoLogin({bool navigateOnSuccess = true}) async {
    await Provider.of<UserState>(context, listen: false).loadTabletToLogIn();
    final isLoggedIn =
        Provider.of<UserState>(context, listen: false).isLoggedIn;
    debugPrint(
      '[LOGIN-TABLET][${_ts()}] autoLogin check → isLoggedIn=$isLoggedIn',
    );
    if (!isLoggedIn || !context.mounted) return false;

    context.read<TabletPadModeState>().setMode(_targetPadMode);
    if (navigateOnSuccess) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!context.mounted) return;
        debugPrint('[LOGIN-TABLET][${_ts()}] autoLogin → onLoginSucceeded()');
        if (onLoginSucceeded != null) {
          onLoginSucceeded!();
        } else {
          Navigator.pushReplacementNamed(context, AppRoutes.tablet);
        }
      });
    }
    return true;
  }

  void initState() {
    if (_inited) return;
    _inited = true;
    unawaited(tryAutoLogin());
  }

  Future<TabletCredentialAuthenticationResult> authenticateCredentials(
    StateSetter setState,
  ) async {
    setState(() => isLoading = true);
    try {
      return await _authenticateCredentialsCore();
    } finally {
      if (context.mounted) {
        setState(() => isLoading = false);
      }
    }
  }

  Future<TabletCredentialAuthenticationResult>
      _authenticateCredentialsCore() async {
    final name = nameController.text.trim();
    final phone = TabletPhone.normalize(phoneController.text);
    final password = passwordController.text.trim();

    if (name.isEmpty && phone.isEmpty && password == '00000') {
      return const TabletCredentialAuthenticationResult(
        success: true,
        message: '태블릿형 개발자 인증을 통과했습니다.',
      );
    }

    final phoneError = TabletLoginValidate.validatePhone(phone);
    final passwordError = TabletLoginValidate.validatePassword(password);

    if (name.isEmpty) {
      return const TabletCredentialAuthenticationResult(
        success: false,
        message: '이름을 다시 확인하세요.',
      );
    }
    if (phoneError != null) {
      return TabletCredentialAuthenticationResult(
        success: false,
        message: phoneError,
      );
    }
    if (passwordError != null) {
      return TabletCredentialAuthenticationResult(
        success: false,
        message: passwordError,
      );
    }

    final isConn = await TabletLoginNetworkService().isConnected();
    debugPrint('[LOGIN-TABLET][${_ts()}] isConnected=$isConn');
    if (!isConn) {
      return const TabletCredentialAuthenticationResult(
        success: false,
        message: '네트워크 연결을 확인하세요.',
      );
    }

    try {
      final repo = context.read<UserRepository>();
      final tablet = await repo.getTabletByPhone(phone);

      if (context.mounted) {
        debugPrint(
          '[LOGIN-TABLET][${_ts()}] input name="$name" phone=${TabletPhone.mask(phone)} pwLen=${password.length}',
        );
        if (tablet != null) {
          debugPrint(
            '[LOGIN-TABLET][${_ts()}] DB tablet: name=${tablet.name}, phone=${TabletPhone.mask(tablet.phone)} id=${tablet.id}',
          );
        } else {
          debugPrint(
            '[LOGIN-TABLET][${_ts()}] DB no tablet for phone=${TabletPhone.mask(phone)}',
          );
        }
      }

      if (tablet == null ||
          tablet.name != name ||
          tablet.password != password) {
        if (context.mounted) {
          debugPrint(
            '[LOGIN-TABLET][${_ts()}] auth failed (name/password mismatch or no tablet)',
          );
        }
        return const TabletCredentialAuthenticationResult(
          success: false,
          message: '입력한 로그인 정보를 다시 확인하세요.',
        );
      }

      final areaName = (tablet.selectedArea ??
              tablet.currentArea ??
              (tablet.areas.isNotEmpty ? tablet.areas.first : ''))
          .trim();
      debugPrint(
        '[LOGIN-TABLET][${_ts()}] resolved areaName="$areaName" from tablet.selected/current/areas',
      );
      if (areaName.isEmpty) {
        return const TabletCredentialAuthenticationResult(
          success: false,
          message: '태블릿 계정의 지역 정보가 없습니다.',
        );
      }

      return TabletCredentialAuthenticationResult(
        success: true,
        message: '${tablet.name}님, 태블릿형 계정 인증에 성공했습니다.',
        tablet: tablet,
      );
    } catch (e, st) {
      debugPrint('[LOGIN-TABLET][${_ts()}] login error: $e\n$st');
      await DevFirebaseDebugDialog.show(
        context: context,
        operation: 'tablet.authenticateCredentials',
        error: e,
        stackTrace: st,
        details: <String, Object?>{
          'phone': TabletPhone.mask(phone),
          'nameLength': name.length,
          'passwordLength': password.length,
          'targetMode': _savedMode,
          'controller': 'TabletLoginController',
        },
      );
      return const TabletCredentialAuthenticationResult(
        success: false,
        message: '태블릿형 로그인 처리 중 오류가 발생했습니다.',
      );
    }
  }

  Future<bool> activateAuthenticatedTablet(
    TabletModel tablet, {
    bool persistSession = true,
  }) async {
    try {
      final phone = TabletPhone.normalize(tablet.phone);
      final userState = context.read<UserState>();
      final areaState = context.read<AreaState>();
      final areaName = (tablet.selectedArea ??
              tablet.currentArea ??
              (tablet.areas.isNotEmpty ? tablet.areas.first : ''))
          .trim();
      if (areaName.isEmpty) return false;

      final englishAreaName = tablet.englishSelectedAreaName ?? areaName;
      final sessionTablet = tablet.copyWith(
        currentArea: areaName,
        selectedArea: areaName,
        englishSelectedAreaName: englishAreaName,
        isSaved: persistSession ? true : tablet.isSaved,
      );
      final divisionToSet = sessionTablet.divisions.firstOrNull ?? '';
      await AreaLoginSessionRefresher.refresh(
        context: context,
        areaState: areaState,
        division: divisionToSet,
        area: areaName,
        operationLabel: 'tablet',
      );
      debugPrint(
        '[LOGIN-TABLET][${_ts()}] AreaRecord 서버 강제 동기화 완료: $divisionToSet/$areaName',
      );

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('tabletPhone', phone);
      await prefs.remove('handle');
      await prefs.setString('selectedArea', areaName);
      await prefs.setString('englishSelectedAreaName', englishAreaName);
      await prefs.setString('mode', _savedMode);
      debugPrint(
        '[LOGIN-TABLET][${_ts()}] prefs saved (tabletPhone/selectedArea/englishSelectedAreaName/mode=$_savedMode)',
      );

      if (persistSession) {
        await userState.updateLoginTablet(sessionTablet);
      } else {
        userState.applyEphemeralLoginTablet(sessionTablet);
      }
      debugPrint(
        '[LOGIN-TABLET][${_ts()}] userState session applied persistence=${persistSession ? 'persistent' : 'ephemeral'}',
      );

      context.read<TabletPadModeState>().setMode(_targetPadMode);

      final currentRecord = areaState.currentRecord;
      final workSession = await WorkAreaSessionCoordinator.activate(
        currentArea: areaState.currentArea.trim(),
        division: divisionToSet,
        homeArea: sessionTablet.areas.firstOrNull ?? areaName,
        mode: _savedMode,
        currentIsHeadquarter: currentRecord?.isHeadquarter,
        homeIsHeadquarter:
            areaState.currentArea.trim() ==
                    (sessionTablet.areas.firstOrNull ?? areaName).trim()
                ? currentRecord?.isHeadquarter
                : null,
        source: persistSession
            ? 'legacy_tablet_login'
            : 'launcher_debug_ephemeral_tablet',
        persistMode: persistSession,
      );
      debugPrint(
        '[LOGIN-TABLET][${_ts()}] work session sync area=${workSession.currentArea} mode=${workSession.mode} foreground=${workSession.foregroundServiceRunning} appFallback=${workSession.appFallbackListening}',
      );

      return true;
    } catch (e, st) {
      debugPrint(
        '[LOGIN-TABLET][${_ts()}] activate authenticated tablet error: $e\n$st',
      );
      await DevFirebaseDebugDialog.show(
        context: context,
        operation: 'tablet.activateAuthenticatedTablet',
        error: e,
        stackTrace: st,
        details: <String, Object?>{
          'tabletId': tablet.id,
          'phone': TabletPhone.mask(tablet.phone),
          'nameLength': tablet.name.length,
          'targetMode': _savedMode,
          'controller': 'TabletLoginController',
          'persistSession': persistSession,
        },
      );
      return false;
    }
  }

  Future<bool> login(StateSetter setState) async {
    final name = nameController.text.trim();
    final phone = TabletPhone.normalize(phoneController.text);
    final password = passwordController.text.trim();

    if (name.isEmpty && phone.isEmpty && password == '00000') {
      debugPrint('[LOGIN-TABLET][${_ts()}] backdoor bypass');
      return true;
    }

    setState(() => isLoading = true);
    try {
      final credential = await _authenticateCredentialsCore();
      final tablet = credential.tablet;
      if (!credential.success || tablet == null) {
        return false;
      }

      final activated = await activateAuthenticatedTablet(tablet);
      if (!activated) return false;

      if (context.mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!context.mounted) return;
          debugPrint(
            '[LOGIN-TABLET][${_ts()}] login success → onLoginSucceeded()',
          );
          if (onLoginSucceeded != null) {
            onLoginSucceeded!();
          } else {
            Navigator.pushReplacementNamed(context, AppRoutes.tablet);
          }
        });
      }
      return true;
    } finally {
      if (context.mounted) {
        setState(() => isLoading = false);
      }
      debugPrint('[LOGIN-TABLET][${_ts()}] set isLoading=false');
    }
  }

  void togglePassword() {
    obscurePassword = !obscurePassword;
  }

  void formatPhoneNumber(String value, StateSetter setState) {
    final numbersOnly = value.replaceAll(RegExp(r'[^0-9]'), '');
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
        borderSide: BorderSide(color: cs.primary, width: 1.8),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: cs.error),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: cs.error, width: 1.8),
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
