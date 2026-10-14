import 'dart:async';
import 'dart:convert';

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
import '../../../launcher/application/app_mode_registry.dart';
import '../area_login_session_refresher.dart';
import '../../applications/single/single_login_network_service.dart';
import '../../applications/single/single_login_validate.dart';

String _ts() => DateTime.now().toIso8601String();

void _debug(Object? message) {
  LoginDebugTrace.log('single', message);
}

const String _prefsKeyCachedUser = 'cachedUserJson';

enum _LocalAreaRefreshResult {
  ready,
  fallbackToFirestore,
  failed,
}

class _SingleCachedCredentials {
  const _SingleCachedCredentials({
    required this.name,
    required this.codeNumber,
    required this.password,
    required this.modes,
  });

  final String name;
  final String codeNumber;
  final String password;
  final List<String> modes;
}

class SingleLoginController {
  SingleLoginController(
    this.context, {
    this.onLoginSucceeded,
  });

  static const String _requiredMode = 'single';

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

  bool _loginOperationInProgress = false;
  bool _loginCompleted = false;
  String _loadingLabel = '로그인';
  VoidCallback? _stateListener;

  String get loadingLabel => _loadingLabel;
  bool get interactionLocked => isLoading || _loginCompleted;
  String get buttonLabel {
    if (_loginCompleted) return '이동 중';
    if (isLoading) return _loadingLabel;
    return '로그인';
  }

  void bindStateListener(VoidCallback? listener) {
    _stateListener = listener;
  }

  void _notifyState() {
    if (!context.mounted) return;
    _stateListener?.call();
  }

  void _setLoading(
    bool value, {
    String? label,
    StateSetter? setState,
  }) {
    isLoading = value;
    _loadingLabel = value ? (label ?? '로그인 중') : '로그인';
    if (!context.mounted) return;
    if (setState != null) {
      setState(() {});
    } else {
      _notifyState();
    }
  }

  bool _beginLoginOperation({
    required String label,
    StateSetter? setState,
  }) {
    if (_loginOperationInProgress || _loginCompleted) {
      _debug(
        '[LOGIN-SINGLE][${_ts()}] login operation blocked: another login operation is already running',
      );
      return false;
    }
    _loginOperationInProgress = true;
    _setLoading(true, label: label, setState: setState);
    _debug(
      '[LOGIN-SINGLE][${_ts()}] login operation started: $label',
    );
    return true;
  }

  void _endLoginOperation({StateSetter? setState}) {
    _loginOperationInProgress = false;
    _setLoading(false, setState: setState);
    _debug('[LOGIN-SINGLE][${_ts()}] login operation finished');
  }

  bool _hasModeAccessFromList(List<String> modes, String required) {
    final req = required.trim().toLowerCase();

    bool matches(String raw) {
      final v = raw.trim().toLowerCase();

      return AppModeRegistry.normalizeLegacyMode(v) == req;
    }

    return modes.any(matches);
  }

  List<String> _extractModes(dynamic raw) {
    if (raw is List) {
      return raw.map((e) => e.toString()).toList();
    }
    return const <String>[];
  }

  _SingleCachedCredentials? _readCachedCredentials(
    SharedPreferences prefs,
  ) {
    final cachedJson = prefs.getString(_prefsKeyCachedUser);
    if (cachedJson == null || cachedJson.isEmpty) return null;

    try {
      final decoded = jsonDecode(cachedJson) as Map<String, dynamic>;
      final cachedName = (decoded['name'] as String?)?.trim() ?? '';
      final cachedCodeNumberRaw = (decoded['codeNumber'] ?? decoded['phone'] ?? '').toString().trim();
      final cachedCodeNumber = AccountCodeNumber.normalize(cachedCodeNumberRaw);
      final cachedPassword = (decoded['password'] as String?) ?? '';
      return _SingleCachedCredentials(
        name: cachedName,
        codeNumber: cachedCodeNumber,
        password: cachedPassword,
        modes: _extractModes(decoded['modes']),
      );
    } catch (error, stackTrace) {
      _debug(
        '[LOGIN-SINGLE][${_ts()}] cachedUserJson decode failed: $error\n$stackTrace',
      );
      return null;
    }
  }

  void _navigateAfterLogin() {
    _loginCompleted = true;
    _notifyState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!context.mounted) return;
      _debug('[LOGIN-SINGLE][${_ts()}] login success → navigation');
      if (onLoginSucceeded != null) {
        onLoginSucceeded!();
      } else {
        Navigator.pushReplacementNamed(context, AppRoutes.singleCommute);
      }
    });
  }

  Future<void> _syncWorkAreaSession({
    required String source,
  }) async {
    final areaState = context.read<AreaState>();
    final userState = context.read<UserState>();
    final currentArea = areaState.currentArea.trim();
    final homeArea = userState.area.trim();
    final currentRecord = areaState.currentRecord;
    final result = await WorkAreaSessionCoordinator.activate(
      currentArea: currentArea,
      division: areaState.currentDivision.trim().isNotEmpty
          ? areaState.currentDivision.trim()
          : userState.division.trim(),
      homeArea: homeArea,
      mode: 'single',
      currentIsHeadquarter: currentRecord?.isHeadquarter,
      homeIsHeadquarter:
          homeArea.isNotEmpty && homeArea == currentArea
              ? currentRecord?.isHeadquarter
              : null,
      source: source,
    );
    _debug(
      '[LOGIN-SINGLE][${_ts()}] work session sync source=$source area=${result.currentArea} mode=${result.mode} foreground=${result.foregroundServiceRunning} appFallback=${result.appFallbackListening}',
    );
  }

  Future<_LocalAreaRefreshResult> _refreshLocalSessionArea({
    required UserState userState,
    required String operationLabel,
  }) async {
    final session = userState.session;
    if (session == null) {
      _debug(
        '[LOGIN-SINGLE][${_ts()}] $operationLabel AreaRecord 동기화 중단: 로그인 세션 없음 → Firestore fallback',
      );
      return _LocalAreaRefreshResult.fallbackToFirestore;
    }

    final selectedArea = session.selectedArea.trim();
    final currentArea = session.currentArea.trim();
    final area = selectedArea.isNotEmpty ? selectedArea : currentArea;
    final division = session.divisions.firstOrNull?.trim() ?? '';

    if (area.isEmpty || division.isEmpty) {
      _debug(
        '[LOGIN-SINGLE][${_ts()}] $operationLabel legacy local session detected: division=$division, area=$area → Firestore fallback',
      );
      await userState.discardLocalLoginSession(
        source: '$operationLabel-legacy-fallback',
      );
      return _LocalAreaRefreshResult.fallbackToFirestore;
    }

    try {
      _debug(
        '[LOGIN-SINGLE][${_ts()}] $operationLabel AreaRecord 서버 강제 동기화 시작: division=$division, area=$area',
      );
      await AreaLoginSessionRefresher.refresh(
        context: context,
        areaState: context.read<AreaState>(),
        division: division,
        area: area,
        operationLabel: operationLabel,
      );
      _debug(
        '[LOGIN-SINGLE][${_ts()}] $operationLabel AreaRecord 서버 강제 동기화 완료: division=$division, area=$area',
      );
      return _LocalAreaRefreshResult.ready;
    } catch (error, stackTrace) {
      _debug(
        '[LOGIN-SINGLE][${_ts()}] $operationLabel AreaRecord 서버 강제 동기화 실패: $error\n$stackTrace',
      );
      await userState.discardLocalLoginSession(
        source: operationLabel,
      );
      return _LocalAreaRefreshResult.failed;
    }
  }

  Future<bool> _loginFromFirestoreCredentials({
    required SharedPreferences prefs,
    required String name,
    required String codeNumber,
    required String password,
    required String operationLabel,
  }) async {
    final isConnected = await SingleLoginNetworkService().isConnected();
    _debug(
      '[LOGIN-SINGLE][${_ts()}] $operationLabel isConnected=$isConnected',
    );
    if (!isConnected || !context.mounted) return false;

    try {
      final userRepository = context.read<UserRepository>();
      final user = await userRepository.getUserByAccountCode(codeNumber);
      AccountCodeDiagnostics.record(
        'single',
        user == null ? 'account_not_found' : 'account_loaded',
        meta: <String, Object?>{'codeNumber': AccountCodeNumber.mask(codeNumber)},
      );

      _debug(
        '[LOGIN-SINGLE][${_ts()}] $operationLabel 입력값 name="$name" codeNumber="${AccountCodeNumber.mask(codeNumber)}" pwLen=${password.length}',
      );
      if (user != null) {
        _debug(
          '[LOGIN-SINGLE][${_ts()}] $operationLabel DB 유저: name=${user.name}, codeNumber=${AccountCodeNumber.mask(user.codeNumber)}',
        );
      } else {
        _debug(
          '[LOGIN-SINGLE][${_ts()}] $operationLabel DB에서 사용자 정보 없음',
        );
      }

      if (user == null || user.name != name || user.password != password) {
        _debug(
          '[LOGIN-SINGLE][${_ts()}] $operationLabel auth failed',
        );
        return false;
      }

      final allowed = _hasModeAccessFromList(user.modes, _requiredMode);
      if (!allowed) {
        _debug(
          '[LOGIN-SINGLE][${_ts()}] $operationLabel login blocked: modes missing "$_requiredMode"',
        );
        return false;
      }

      final updatedUser = user.copyWith(isSaved: true);
      final areaToSet = updatedUser.areas.firstOrNull?.trim() ?? '';
      final divisionToSet = updatedUser.divisions.firstOrNull?.trim() ?? '';

      await AreaLoginSessionRefresher.refresh(
        context: context,
        areaState: context.read<AreaState>(),
        division: divisionToSet,
        area: areaToSet,
        operationLabel: operationLabel,
      );
      _debug(
        '[LOGIN-SINGLE][${_ts()}] $operationLabel AreaRecord 서버 강제 동기화 완료: $divisionToSet/$areaToSet',
      );

      final userState = context.read<UserState>();
      await userState.updateLoginUser(updatedUser);
      _debug(
        '[LOGIN-SINGLE][${_ts()}] $operationLabel userState.updateLoginUser done',
      );

      await prefs.setString('codeNumber', updatedUser.codeNumber);
      await prefs.setString('selectedArea', updatedUser.selectedArea ?? '');
      await prefs.setString(
        'division',
        updatedUser.divisions.firstOrNull ?? '',
      );
      await prefs.setString('role', updatedUser.role);
      await prefs.setString('position', updatedUser.position ?? '');
      await WorkSchedulePrefs.saveUserSchedule(
        prefs: prefs,
        user: updatedUser,
      );
      await WorkSchedulePrefs.refreshReminderFromPrefs(prefs);
      await prefs.setString('mode', 'single');
      _debug(
        '[LOGIN-SINGLE][${_ts()}] $operationLabel SharedPreferences 저장 완료: codeNumber=${prefs.getString('codeNumber')}',
      );

      await _syncWorkAreaSession(source: 'legacy_single_firestore_login');
      AccountCodeDiagnostics.record(
        'single',
        'login_success',
        meta: <String, Object?>{'codeNumber': AccountCodeNumber.mask(codeNumber)},
      );
      _navigateAfterLogin();
      return true;
    } catch (error, stackTrace) {
      _debug(
        '[LOGIN-SINGLE][${_ts()}] $operationLabel Firestore login error: $error\n$stackTrace',
      );
      return false;
    }
  }

  Future<bool> tryAutoLogin() async {
    if (!_beginLoginOperation(label: '로그인 정보 확인 중')) return false;

    try {
      final prefs = await SharedPreferences.getInstance();
      final cachedCredentials = _readCachedCredentials(prefs);
      final userState = Provider.of<UserState>(context, listen: false);

      await userState.loadUserToLogInLocalOnly();

      final isLoggedIn = userState.isLoggedIn;
      _debug(
        '[LOGIN-SINGLE][${_ts()}] autoLogin(local-only) → isLoggedIn=$isLoggedIn',
      );

      if (!isLoggedIn || !context.mounted) return false;

      final session = userState.session;
      final allowed = session != null &&
          _hasModeAccessFromList(session.modes, _requiredMode);
      if (!allowed) {
        _debug(
          '[LOGIN-SINGLE][${_ts()}] autoLogin blocked: modes missing "$_requiredMode"',
        );
        await userState.discardLocalLoginSession(
          source: 'single-auto-mode-blocked',
        );
        return false;
      }

      final areaResult = await _refreshLocalSessionArea(
        userState: userState,
        operationLabel: 'single-auto-local',
      );

      if (areaResult == _LocalAreaRefreshResult.ready) {
        if (!context.mounted || !userState.isLoggedIn) return false;
        await _syncWorkAreaSession(source: 'legacy_single_auto_login');
        _navigateAfterLogin();
        return true;
      }

      if (areaResult == _LocalAreaRefreshResult.fallbackToFirestore &&
          cachedCredentials != null &&
          context.mounted) {
        _debug(
          '[LOGIN-SINGLE][${_ts()}] autoLogin legacy division fallback → normal Firestore login',
        );
        return await _loginFromFirestoreCredentials(
          prefs: prefs,
          name: cachedCredentials.name,
          codeNumber: cachedCredentials.codeNumber,
          password: cachedCredentials.password,
          operationLabel: 'single-auto-legacy-fallback',
        );
      }
      return false;
    } finally {
      _endLoginOperation();
    }
  }

  void initState() {
    unawaited(tryAutoLogin());
  }

  Future<bool> login(StateSetter setState) async {
    if (_loginOperationInProgress || _loginCompleted) {
      _debug(
        '[LOGIN-SINGLE][${_ts()}] manual login ignored while login operation or navigation is running',
      );
      return false;
    }

    final name = nameController.text.trim();
    final codeNumber = AccountCodeNumber.normalize(codeNumberController.text);
    final password = passwordController.text.trim();
    AccountCodeDiagnostics.record(
      'single',
      'login_attempt',
      meta: <String, Object?>{
        'codeNumber': AccountCodeNumber.mask(codeNumber),
        'nameLength': name.length,
        'passwordLength': password.length,
      },
    );


    final codeNumberError = SingleLoginValidate.validateCodeNumber(codeNumber);
    final passwordError = SingleLoginValidate.validatePassword(password);

    if (name.isEmpty || codeNumberError != null || passwordError != null) {
      AccountCodeDiagnostics.record(
        'single',
        'validation_failed',
        meta: <String, Object?>{
          'nameEmpty': name.isEmpty,
          'codeNumberError': codeNumberError,
          'passwordError': passwordError,
        },
      );
      return false;
    }

    if (!_beginLoginOperation(
      label: '로그인 확인 중',
      setState: setState,
    )) {
      return false;
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      final cachedCredentials = _readCachedCredentials(prefs);

      if (cachedCredentials != null &&
          cachedCredentials.name == name &&
          cachedCredentials.codeNumber == codeNumber &&
          cachedCredentials.password == password) {
        final allowed =
            _hasModeAccessFromList(cachedCredentials.modes, _requiredMode);

        if (allowed) {
          _debug(
            '[LOGIN-SINGLE][${_ts()}] local-only login hit (cachedUserJson match)',
          );
          await prefs.setString('mode', 'single');

          final userState = context.read<UserState>();
          await userState.loadUserToLogInLocalOnly();
          final isLoggedIn = userState.isLoggedIn;
          _debug(
            '[LOGIN-SINGLE][${_ts()}] local-only login result → isLoggedIn=$isLoggedIn',
          );

          if (isLoggedIn && context.mounted) {
            final areaResult = await _refreshLocalSessionArea(
              userState: userState,
              operationLabel: 'single-local-credential',
            );

            if (areaResult == _LocalAreaRefreshResult.ready) {
              if (!context.mounted || !userState.isLoggedIn) return false;
              await _syncWorkAreaSession(
                source: 'legacy_single_local_login',
              );
              _navigateAfterLogin();
              return true;
            }

            if (areaResult == _LocalAreaRefreshResult.failed) {
              return false;
            }

            _debug(
              '[LOGIN-SINGLE][${_ts()}] local credential legacy division fallback → normal Firestore login',
            );
          } else {
            _debug(
              '[LOGIN-SINGLE][${_ts()}] local-only session restore failed → normal Firestore login',
            );
          }
        } else {
          _debug(
            '[LOGIN-SINGLE][${_ts()}] local-only blocked: modes missing "$_requiredMode" → fallback to Firestore',
          );
        }
      }

      return await _loginFromFirestoreCredentials(
        prefs: prefs,
        name: name,
        codeNumber: codeNumber,
        password: password,
        operationLabel: 'single',
      );
    } finally {
      _endLoginOperation(setState: setState);
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
    _stateListener = null;
    nameController.dispose();
    codeNumberController.dispose();
    passwordController.dispose();
    nameFocus.dispose();
    codeNumberFocus.dispose();
    passwordFocus.dispose();
  }
}
