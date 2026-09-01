import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../app/init/app_start_user_purpose.dart';
import '../../../app/init/work_schedule_prefs.dart';
import '../../account/applications/user_state.dart';
import '../../account/domain/models/session_account.dart';
import '../../account/domain/models/tablet/tablet_model.dart';
import '../../account/domain/models/user/user_model.dart';
import '../../account/domain/repositories/user_repository.dart';
import '../../login/applications/double/double_login_network_service.dart';
import '../../login/controllers/area_login_session_refresher.dart';
import '../../login/controllers/personal/personal_login_controller.dart';
import '../../login/controllers/tablet/tablet_login_controller.dart';
import '../../tablet/applications/tablet_pad_mode_state.dart';
import '../../dev/application/area_state.dart';
import '../../dev/domain/repositories/area_repo_package/area_repository.dart';
import '../../headquarter/application/headquarter_dashboard_context.dart';
import '../../../shared/work_session/application/work_area_session_coordinator.dart';
import 'app_mode_definition.dart';
import 'app_mode_registry.dart';
import 'launcher_diagnostics.dart';
import 'terminal_restore_hint.dart';

enum TerminalAccountKind {
  user,
  personal,
  tablet,
}

enum TerminalSessionPersistence {
  persistent,
  ephemeral,
}

class TerminalAuthenticatedAccount {
  const TerminalAuthenticatedAccount({
    required this.kind,
    required this.displayName,
    required this.supportedModes,
    required this.activated,
    this.user,
    this.personalAccount,
    this.tablet,
  });

  final TerminalAccountKind kind;
  final String displayName;
  final List<AppModeDefinition> supportedModes;
  final bool activated;
  final UserModel? user;
  final PersonalAuthenticatedAccount? personalAccount;
  final TabletModel? tablet;

  TerminalAuthenticatedAccount copyWith({
    bool? activated,
    UserModel? user,
    PersonalAuthenticatedAccount? personalAccount,
    TabletModel? tablet,
  }) {
    return TerminalAuthenticatedAccount(
      kind: kind,
      displayName: displayName,
      supportedModes: supportedModes,
      activated: activated ?? this.activated,
      user: user ?? this.user,
      personalAccount: personalAccount ?? this.personalAccount,
      tablet: tablet ?? this.tablet,
    );
  }
}

class TerminalAccountAuthenticationResult {
  const TerminalAccountAuthenticationResult({
    required this.success,
    required this.message,
    this.account,
    this.copyText,
  });

  final bool success;
  final String message;
  final TerminalAuthenticatedAccount? account;
  final String? copyText;
}

class TerminalModeActivationResult {
  const TerminalModeActivationResult({
    required this.success,
    required this.message,
    this.firebaseAreaValidationReads = 0,
    this.verifiedAreaRecordReused = false,
  });

  final bool success;
  final String message;
  final int firebaseAreaValidationReads;
  final bool verifiedAreaRecordReused;
}

class TerminalAuthCoordinator {
  const TerminalAuthCoordinator._();

  static const String accountKindPrefsKey =
      TerminalRestoreHint.accountKindPrefsKey;

  static TerminalAccountKind? parseAccountKind(String? raw) {
    final value = (raw ?? '').trim().toLowerCase();
    switch (value) {
      case '1':
      case 'user':
      case 'staff':
      case '일반':
      case '일반계정':
      case '일반 계정':
      case '직원':
      case '직원계정':
        return TerminalAccountKind.user;
      case '2':
      case 'personal':
      case '개인':
      case '개인형':
      case '개인계정':
      case '개인 계정':
        return TerminalAccountKind.personal;
      case '3':
      case 'tablet':
      case '태블릿':
      case '태블릿형':
      case '태블릿계정':
      case '태블릿 계정':
        return TerminalAccountKind.tablet;
      default:
        return null;
    }
  }

  static TerminalAccountKind? inferAccountKindFromMode(String? rawMode) {
    final mode = AppModeRegistry.findLegacy(rawMode);
    if (mode == null) return null;
    if (mode.id == 'personal') return TerminalAccountKind.personal;
    if (mode.id == 'tablet') return TerminalAccountKind.tablet;
    return TerminalAccountKind.user;
  }

  static TerminalAccountKind? accountKindForPurpose(
    AppStartUserPurpose? purpose,
  ) {
    if (purpose == null) return null;
    return switch (purpose) {
      AppStartUserPurpose.branchEmployee => TerminalAccountKind.user,
      AppStartUserPurpose.headOfficeEmployee => TerminalAccountKind.user,
      AppStartUserPurpose.commuteRecorder => TerminalAccountKind.user,
      AppStartUserPurpose.tabletInstallation => TerminalAccountKind.tablet,
      AppStartUserPurpose.personal => TerminalAccountKind.personal,
    };
  }

  static int accountKindNumber(TerminalAccountKind kind) {
    return switch (kind) {
      TerminalAccountKind.user => 1,
      TerminalAccountKind.personal => 2,
      TerminalAccountKind.tablet => 3,
    };
  }

  static String accountKindId(TerminalAccountKind kind) {
    return switch (kind) {
      TerminalAccountKind.user => 'user',
      TerminalAccountKind.personal => 'personal',
      TerminalAccountKind.tablet => 'tablet',
    };
  }

  static String accountKindLabel(TerminalAccountKind kind) {
    return switch (kind) {
      TerminalAccountKind.user => '일반 계정',
      TerminalAccountKind.personal => '개인형 계정',
      TerminalAccountKind.tablet => '태블릿형 계정',
    };
  }

  static String sessionPersistenceId(TerminalSessionPersistence persistence) {
    return switch (persistence) {
      TerminalSessionPersistence.persistent => 'persistent',
      TerminalSessionPersistence.ephemeral => 'ephemeral',
    };
  }

  static Future<void> persistAccountKind(TerminalAccountKind kind) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(accountKindPrefsKey, accountKindId(kind));
  }

  static Future<TerminalAccountKind?> readLocalRestoreKind({
    String? savedMode,
  }) async {
    final kindId =
        await TerminalRestoreHint.readAccountKindId(savedMode: savedMode);
    final kind = parseAccountKind(kindId);
    LauncherDiagnostics.record(
      kind == null ? 'auth_local_restore_hint_none' : 'auth_local_restore_hint',
      meta: <String, Object?>{
        'accountKind': kind == null ? '' : accountKindId(kind),
        'firebaseReads': 0,
      },
    );
    return kind;
  }

  static List<AppModeDefinition> _userSupportedModes(List<String> rawModes) {
    return AppModeRegistry.supportedModes(
      rawModes,
      allowedIds: const <String>{'single', 'double', 'triple', 'minor'},
    );
  }

  static Future<TerminalAccountAuthenticationResult> tryRestoreAccount(
    BuildContext context, {
    required TerminalAccountKind kind,
    required String? savedMode,
  }) async {
    LauncherDiagnostics.record(
      'auth_account_restore_start',
      meta: <String, Object?>{
        'accountKind': accountKindId(kind),
        'savedMode': savedMode ?? '',
      },
    );

    try {
      final userState = context.read<UserState>();
      switch (kind) {
        case TerminalAccountKind.user:
          final existing = userState.session;
          if (existing is UserSessionAccount) {
            final modes = _userSupportedModes(existing.modes);
            await persistAccountKind(kind);
            return TerminalAccountAuthenticationResult(
              success: true,
              message: '기존 로그인 세션을 복원했습니다.',
              account: TerminalAuthenticatedAccount(
                kind: kind,
                displayName: existing.displayName,
                supportedModes: modes,
                activated: true,
                user: existing.user,
              ),
            );
          }

          LauncherDiagnostics.record(
            'auth_account_restore_user_area_first_start',
            meta: <String, Object?>{
              'savedModeIgnored': savedMode ?? '',
              'restoreStrategy': 'local_first_then_server',
              'modeIndependentHeadquarter': true,
            },
          );
          await userState.loadUserToLogInLocalOnly();
          var restored = userState.session;
          if (restored is! UserSessionAccount) {
            LauncherDiagnostics.record(
              'auth_account_restore_user_local_miss',
              meta: <String, Object?>{
                'savedModeIgnored': savedMode ?? '',
                'fallback': 'server_user_restore',
              },
            );
            await userState.loadUserToLogIn();
            restored = userState.session;
          }

          if (restored is! UserSessionAccount) {
            return const TerminalAccountAuthenticationResult(
              success: false,
              message: '수동 로그인이 필요합니다.',
            );
          }
          final modes = _userSupportedModes(restored.modes);
          await persistAccountKind(kind);
          return TerminalAccountAuthenticationResult(
            success: true,
            message: '기존 로그인 세션을 복원했습니다.',
            account: TerminalAuthenticatedAccount(
              kind: kind,
              displayName: restored.displayName,
              supportedModes: modes,
              activated: true,
              user: restored.user,
            ),
          );
        case TerminalAccountKind.personal:
          final prefs = await SharedPreferences.getInstance();
          final originalMode = prefs.getString('mode');
          if (AppModeRegistry.normalizeLegacyMode(originalMode) != 'personal') {
            await prefs.setString('mode', 'personal');
          }
          final controller = PersonalLoginController(context);
          bool success;
          try {
            success = await controller.tryRestoreSession(
              navigateOnSuccess: false,
            );
          } finally {
            controller.dispose();
          }
          if (originalMode == null || originalMode.trim().isEmpty) {
            await prefs.remove('mode');
          } else if (AppModeRegistry.normalizeLegacyMode(originalMode) != 'personal') {
            await prefs.setString('mode', originalMode);
          }
          if (!success) {
            return const TerminalAccountAuthenticationResult(
              success: false,
              message: '수동 로그인이 필요합니다.',
            );
          }
          await persistAccountKind(kind);
          return TerminalAccountAuthenticationResult(
            success: true,
            message: '기존 개인형 세션을 복원했습니다.',
            account: TerminalAuthenticatedAccount(
              kind: kind,
              displayName: controller.loggedInName ?? '사용자',
              supportedModes: <AppModeDefinition>[
                AppModeRegistry.byId('personal')!,
              ],
              activated: true,
            ),
          );
        case TerminalAccountKind.tablet:
          final existing = userState.session;
          if (existing is TabletSessionAccount) {
            await persistAccountKind(kind);
            context.read<TabletPadModeState>().setMode(PadMode.big);
            return TerminalAccountAuthenticationResult(
              success: true,
              message: '기존 태블릿 세션을 복원했습니다.',
              account: TerminalAuthenticatedAccount(
                kind: kind,
                displayName: existing.displayName,
                supportedModes: <AppModeDefinition>[
                  AppModeRegistry.byId('tablet')!,
                ],
                activated: true,
                tablet: existing.tablet,
              ),
            );
          }
          await userState.loadTabletToLogIn();
          final restored = userState.session;
          if (restored is! TabletSessionAccount) {
            return const TerminalAccountAuthenticationResult(
              success: false,
              message: '수동 로그인이 필요합니다.',
            );
          }
          context.read<TabletPadModeState>().setMode(PadMode.big);
          await persistAccountKind(kind);
          return TerminalAccountAuthenticationResult(
            success: true,
            message: '기존 태블릿 세션을 복원했습니다.',
            account: TerminalAuthenticatedAccount(
              kind: kind,
              displayName: restored.displayName,
              supportedModes: <AppModeDefinition>[
                AppModeRegistry.byId('tablet')!,
              ],
              activated: true,
              tablet: restored.tablet,
            ),
          );
      }
    } catch (error, stackTrace) {
      LauncherDiagnostics.record(
        'auth_account_restore_error',
        meta: <String, Object?>{
          'accountKind': accountKindId(kind),
          'error': error,
          'stack': stackTrace,
        },
      );
      return const TerminalAccountAuthenticationResult(
        success: false,
        message: '자동 로그인 정보를 확인하지 못했습니다.',
      );
    }
  }

  static Future<TerminalAccountAuthenticationResult> authenticateAccount(
    BuildContext context, {
    required TerminalAccountKind kind,
    required String name,
    required String phone,
    required String password,
    TerminalSessionPersistence persistence =
        TerminalSessionPersistence.persistent,
  }) async {
    final normalizedPhone = phone.replaceAll(RegExp(r'[^0-9]'), '');
    final maskedPhone = _maskPhone(normalizedPhone);
    LauncherDiagnostics.record(
      'auth_account_manual_start',
      meta: <String, Object?>{
        'accountKind': accountKindId(kind),
        'nameLength': name.trim().length,
        'phoneMasked': maskedPhone,
        'passwordLength': password.length,
        'sessionPersistence': sessionPersistenceId(persistence),
      },
    );

    void stateSetter(VoidCallback callback) {
      callback();
    }

    try {
      switch (kind) {
        case TerminalAccountKind.user:
          final connected = await DoubleLoginNetworkService().isConnected();
          if (!connected) {
            return const TerminalAccountAuthenticationResult(
              success: false,
              message: '네트워크 연결을 확인하세요.',
            );
          }
          final user = await context.read<UserRepository>().getUserByPhone(
                normalizedPhone,
              );
          if (user == null ||
              user.name != name.trim() ||
              user.password != password.trim()) {
            return const TerminalAccountAuthenticationResult(
              success: false,
              message: '입력한 로그인 정보를 다시 확인하세요.',
            );
          }
          final modes = _userSupportedModes(user.modes);
          if (persistence == TerminalSessionPersistence.persistent) {
            await persistAccountKind(kind);
          }
          final account = TerminalAuthenticatedAccount(
            kind: kind,
            displayName: user.name,
            supportedModes: modes,
            activated: false,
            user: user,
          );
          LauncherDiagnostics.record(
            'auth_account_manual_success',
            meta: <String, Object?>{
              'accountKind': accountKindId(kind),
              'phoneMasked': maskedPhone,
              'supportedModes': modes.map((mode) => mode.id).join(','),
              'firebaseCredentialQueries': 1,
              'firebaseSupportedModeQueries': 0,
              'sessionPersistence': sessionPersistenceId(persistence),
            },
          );
          return TerminalAccountAuthenticationResult(
            success: true,
            message: '${user.name}님, 로그인에 성공했습니다.',
            account: account,
          );
        case TerminalAccountKind.personal:
          final controller = PersonalLoginController(context);
          try {
            controller.nameController.text = name;
            controller.phoneController.text = normalizedPhone;
            controller.passwordController.text = password;
            final result = await controller.authenticateCredentials(
              stateSetter,
            );
            final personalAccount = result.account;
            if (!result.success || personalAccount == null) {
              return TerminalAccountAuthenticationResult(
                success: false,
                message: result.message,
                copyText: result.copyText,
              );
            }
            if (persistence == TerminalSessionPersistence.persistent) {
              await persistAccountKind(kind);
            }
            LauncherDiagnostics.record(
              'auth_account_manual_success',
              meta: <String, Object?>{
                'accountKind': accountKindId(kind),
                'phoneMasked': maskedPhone,
                'supportedModes': 'personal',
                'firebaseSupportedModeQueries': 0,
                'deferredActivation': true,
                'sessionPersistence': sessionPersistenceId(persistence),
              },
            );
            return TerminalAccountAuthenticationResult(
              success: true,
              message: result.message,
              account: TerminalAuthenticatedAccount(
                kind: kind,
                displayName: personalAccount.name,
                supportedModes: <AppModeDefinition>[
                  AppModeRegistry.byId('personal')!,
                ],
                activated: false,
                personalAccount: personalAccount,
              ),
              copyText: result.copyText,
            );
          } finally {
            controller.dispose();
          }
        case TerminalAccountKind.tablet:
          final controller = TabletLoginController(
            context,
            onLoginSucceeded: () {},
          );
          try {
            controller.nameController.text = name;
            controller.phoneController.text = normalizedPhone;
            controller.passwordController.text = password;
            final result = await controller.authenticateCredentials(
              stateSetter,
            );
            final tablet = result.tablet;
            if (!result.success || tablet == null) {
              return TerminalAccountAuthenticationResult(
                success: false,
                message: result.message,
              );
            }
            if (persistence == TerminalSessionPersistence.persistent) {
              await persistAccountKind(kind);
            }
            LauncherDiagnostics.record(
              'auth_account_manual_success',
              meta: <String, Object?>{
                'accountKind': accountKindId(kind),
                'phoneMasked': maskedPhone,
                'supportedModes': 'tablet',
                'firebaseSupportedModeQueries': 0,
                'deferredActivation': true,
                'sessionPersistence': sessionPersistenceId(persistence),
              },
            );
            return TerminalAccountAuthenticationResult(
              success: true,
              message: result.message,
              account: TerminalAuthenticatedAccount(
                kind: kind,
                displayName: tablet.name,
                supportedModes: <AppModeDefinition>[
                  AppModeRegistry.byId('tablet')!,
                ],
                activated: false,
                tablet: tablet,
              ),
            );
          } finally {
            controller.dispose();
          }
      }
    } catch (error, stackTrace) {
      LauncherDiagnostics.record(
        'auth_account_manual_error',
        meta: <String, Object?>{
          'accountKind': accountKindId(kind),
          'phoneMasked': maskedPhone,
          'sessionPersistence': sessionPersistenceId(persistence),
          'error': error,
          'stack': stackTrace,
        },
      );
      return const TerminalAccountAuthenticationResult(
        success: false,
        message: '로그인 처리 중 오류가 발생했습니다.',
      );
    }
  }

  static Future<TerminalModeActivationResult> activateHeadquarterContext(
    BuildContext context, {
    required TerminalAuthenticatedAccount account,
    required String targetArea,
    TerminalSessionPersistence persistence =
        TerminalSessionPersistence.persistent,
    AreaRecord? verifiedAreaRecord,
  }) async {
    if (account.kind != TerminalAccountKind.user) {
      return const TerminalModeActivationResult(
        success: false,
        message: '본사 대시보드는 일반 계정에서만 사용할 수 있습니다.',
      );
    }
    final user = account.user;
    if (user == null) {
      return const TerminalModeActivationResult(
        success: false,
        message: '로그인 세션을 활성화할 수 없습니다.',
      );
    }
    final areaToSet = targetArea.trim();
    final divisionToSet = user.divisions.firstOrNull ?? '';
    if (areaToSet.isEmpty ||
        !user.areas.any((value) => value.trim() == areaToSet)) {
      return const TerminalModeActivationResult(
        success: false,
        message: '선택한 본사 지역을 사용할 수 없습니다.',
      );
    }

    LauncherDiagnostics.record(
      'auth_headquarter_context_activation_start',
      meta: <String, Object?>{
        'accountKind': accountKindId(account.kind),
        'area': areaToSet,
        'division': divisionToSet,
        'alreadyActivated': account.activated,
        'modeIndependent': true,
        'persistMode': false,
        'storedModeFallback': false,
        'sessionPersistence': sessionPersistenceId(persistence),
        'firebaseAreaValidationReads': verifiedAreaRecord == null ? 1 : 0,
        'firebaseWorkAreaListReads': 0,
        'verifiedAreaRecordProvided': verifiedAreaRecord != null,
      },
    );

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      final storedModeBeforeHeadquarter =
          (prefs.getString('mode') ?? '').trim();
      final updatedUser = !account.activated &&
              persistence == TerminalSessionPersistence.persistent
          ? user.copyWith(
              isSaved: true,
              currentArea: areaToSet,
              selectedArea: areaToSet,
            )
          : user.copyWith(
              currentArea: areaToSet,
              selectedArea: areaToSet,
            );
      final areaState = context.read<AreaState>();
      var firebaseAreaValidationReads = 0;
      var verifiedAreaRecordReused = false;
      if (verifiedAreaRecord != null) {
        final record = verifiedAreaRecord;
        final recordMatches = record.name.trim() == areaToSet &&
            record.division.trim() == divisionToSet.trim() &&
            record.isHeadquarter;
        if (!recordMatches) {
          LauncherDiagnostics.record(
            'auth_headquarter_context_verification_failed',
            meta: <String, Object?>{
              'area': areaToSet,
              'division': divisionToSet,
              'verifiedRecordArea': record.name,
              'verifiedRecordDivision': record.division,
              'verifiedRecordIsHeadquarter': record.isHeadquarter,
              'firebaseAreaValidationReads': 0,
              'verifiedAreaRecordReused': false,
            },
          );
          return const TerminalModeActivationResult(
            success: false,
            message: '선택한 지역이 본사로 확인되지 않았습니다.',
          );
        }
        areaState.applyLocalAreaRecord(
          record,
          source: 'launcher_verified_headquarter',
          syncWorkSession: false,
        );
        verifiedAreaRecordReused = true;
      } else {
        firebaseAreaValidationReads = 1;
        await AreaLoginSessionRefresher.refresh(
          context: context,
          areaState: areaState,
          division: divisionToSet,
          area: areaToSet,
          operationLabel: 'headquarter',
        );
        if (areaState.currentRecord?.isHeadquarter != true) {
          LauncherDiagnostics.record(
            'auth_headquarter_context_verification_failed',
            meta: <String, Object?>{
              'area': areaToSet,
              'division': divisionToSet,
              'serverIsHeadquarter': areaState.currentRecord?.isHeadquarter,
              'firebaseAreaValidationReads': firebaseAreaValidationReads,
              'verifiedAreaRecordReused': false,
            },
          );
          return TerminalModeActivationResult(
            success: false,
            message: '선택한 지역이 본사로 확인되지 않았습니다.',
            firebaseAreaValidationReads: firebaseAreaValidationReads,
          );
        }
      }

      final userState = context.read<UserState>();
      if (persistence == TerminalSessionPersistence.ephemeral) {
        userState.applyEphemeralLoginUser(updatedUser);
      } else if (account.activated) {
        await userState.updateLoginUserLocalOnly(updatedUser);
      } else {
        await userState.updateLoginUser(updatedUser);
      }
      await prefs.setString('phone', updatedUser.phone);
      await prefs.setString('selectedArea', areaToSet);
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

      HeadquarterDashboardContext.clearMode(
        source: 'launcher_headquarter_activation',
      );
      final homeArea = updatedUser.areas.firstOrNull ?? '';
      final homeIsHeadquarter = homeArea.trim().isNotEmpty &&
              homeArea.trim() == areaToSet
          ? true
          : null;
      final sessionResult = await WorkAreaSessionCoordinator.activate(
        currentArea: areaToSet,
        division: divisionToSet,
        homeArea: homeArea,
        mode: '',
        currentIsHeadquarter: true,
        homeIsHeadquarter: homeIsHeadquarter,
        source: persistence == TerminalSessionPersistence.ephemeral
            ? 'launcher_debug_ephemeral_headquarter'
            : account.activated
                ? 'launcher_restore_headquarter'
                : 'launcher_manual_headquarter',
        persistMode: false,
        useStoredModeFallback: false,
      );
      await prefs.reload();
      final storedModeAfterHeadquarter =
          (prefs.getString('mode') ?? '').trim();
      if (persistence == TerminalSessionPersistence.persistent) {
        await persistAccountKind(account.kind);
      }
      LauncherDiagnostics.record(
        'auth_headquarter_context_activation_success',
        meta: <String, Object?>{
          'area': areaToSet,
          'division': divisionToSet,
          'modeIndependent': true,
          'persistMode': false,
          'storedModeFallback': false,
          'storedModeBefore': storedModeBeforeHeadquarter,
          'storedModeAfter': storedModeAfterHeadquarter,
          'storedModeRemoved': storedModeBeforeHeadquarter.isNotEmpty &&
              storedModeAfterHeadquarter.isEmpty,
          'ttsMode': sessionResult.mode,
          'foregroundServiceRunning': sessionResult.foregroundServiceRunning,
          'appFallbackListening': sessionResult.appFallbackListening,
          'firebaseAreaValidationReads': firebaseAreaValidationReads,
          'firebaseWorkAreaListReads': 0,
          'verifiedAreaRecordReused': verifiedAreaRecordReused,
          'firebaseUserWrites': account.activated ||
                  persistence == TerminalSessionPersistence.ephemeral
              ? 0
              : 1,
          'sessionPersistence': sessionPersistenceId(persistence),
        },
      );
      return TerminalModeActivationResult(
        success: true,
        message: '본사 대시보드를 시작합니다.',
        firebaseAreaValidationReads: firebaseAreaValidationReads,
        verifiedAreaRecordReused: verifiedAreaRecordReused,
      );
    } catch (error, stackTrace) {
      LauncherDiagnostics.record(
        'auth_headquarter_context_activation_error',
        meta: <String, Object?>{
          'area': areaToSet,
          'division': divisionToSet,
          'modeIndependent': true,
          'persistMode': false,
          'storedModeFallback': false,
          'sessionPersistence': sessionPersistenceId(persistence),
          'error': error,
          'stack': stackTrace,
        },
      );
      return const TerminalModeActivationResult(
        success: false,
        message: '본사 세션을 준비하지 못했습니다.',
      );
    }
  }

  static Future<TerminalModeActivationResult> activateMode(
    BuildContext context, {
    required TerminalAuthenticatedAccount account,
    required AppModeDefinition mode,
    String targetArea = '',
    TerminalSessionPersistence persistence =
        TerminalSessionPersistence.persistent,
    AreaRecord? verifiedAreaRecord,
  }) async {
    if (!account.supportedModes.any((item) => item.id == mode.id)) {
      return const TerminalModeActivationResult(
        success: false,
        message: '이 계정에서 지원하지 않는 모드입니다.',
      );
    }

    LauncherDiagnostics.record(
      'auth_mode_activation_start',
      meta: <String, Object?>{
        'accountKind': accountKindId(account.kind),
        'mode': mode.id,
        'alreadyActivated': account.activated,
        'targetArea': targetArea.trim(),
        'sessionPersistence': sessionPersistenceId(persistence),
      },
    );

    var activationAreaValidationReads = 0;
    var activationVerifiedAreaRecordReused = false;

    try {
      final prefs = await SharedPreferences.getInstance();
      if (account.kind == TerminalAccountKind.user &&
          (!account.activated || targetArea.trim().isNotEmpty)) {
        final user = account.user;
        if (user == null) {
          return const TerminalModeActivationResult(
            success: false,
            message: '로그인 세션을 활성화할 수 없습니다.',
          );
        }
        final requestedArea = targetArea.trim();
        final areaToSet = requestedArea.isNotEmpty
            ? requestedArea
            : user.areas.firstOrNull ?? '';
        final divisionToSet = user.divisions.firstOrNull ?? '';
        if (areaToSet.isEmpty ||
            !user.areas.any((value) => value.trim() == areaToSet)) {
          return const TerminalModeActivationResult(
            success: false,
            message: '선택한 업무 지역을 사용할 수 없습니다.',
          );
        }
        final updatedUser = !account.activated &&
                persistence == TerminalSessionPersistence.persistent
            ? user.copyWith(
                isSaved: true,
                currentArea: areaToSet,
                selectedArea: areaToSet,
              )
            : user.copyWith(
                currentArea: areaToSet,
                selectedArea: areaToSet,
              );
        final areaState = context.read<AreaState>();
        var firebaseAreaValidationReads = 0;
        var verifiedAreaRecordReused = false;
        if (verifiedAreaRecord != null) {
          final record = verifiedAreaRecord;
          final recordMatches = record.name.trim() == areaToSet &&
              record.division.trim() == divisionToSet.trim() &&
              !record.isHeadquarter;
          if (!recordMatches) {
            LauncherDiagnostics.record(
              'auth_work_area_verified_record_rejected',
              meta: <String, Object?>{
                'area': areaToSet,
                'division': divisionToSet,
                'mode': mode.id,
                'verifiedRecordArea': record.name,
                'verifiedRecordDivision': record.division,
                'verifiedRecordIsHeadquarter': record.isHeadquarter,
                'firebaseAreaValidationReads': 0,
              },
            );
            return const TerminalModeActivationResult(
              success: false,
              message: '선택한 업무 지역 정보를 확인할 수 없습니다.',
            );
          }
          areaState.applyLocalAreaRecord(
            record,
            source: 'launcher_verified_area',
            syncWorkSession: false,
          );
          verifiedAreaRecordReused = true;
        } else {
          firebaseAreaValidationReads = 1;
          await AreaLoginSessionRefresher.refresh(
            context: context,
            areaState: areaState,
            division: divisionToSet,
            area: areaToSet,
            operationLabel: mode.id,
          );
        }
        LauncherDiagnostics.record(
          'auth_work_area_activation_start',
          meta: <String, Object?>{
            'area': areaToSet,
            'division': divisionToSet,
            'restoredSession': account.activated,
            'firebaseAreaValidationReads': firebaseAreaValidationReads,
            'firebaseWorkAreaListReads': 0,
            'verifiedAreaRecordReused': verifiedAreaRecordReused,
          },
        );
        final serverModes = AppModeRegistry.supportedModes(
          areaState.currentRecord?.modes ?? const <String>[],
          allowedIds: <String>{mode.id},
        );
        if (serverModes.isEmpty || areaState.currentRecord?.isHeadquarter == true) {
          LauncherDiagnostics.record(
            'auth_work_area_mode_verification_failed',
            meta: <String, Object?>{
              'area': areaToSet,
              'division': divisionToSet,
              'mode': mode.id,
              'serverIsHeadquarter': areaState.currentRecord?.isHeadquarter,
              'firebaseAreaValidationReads': firebaseAreaValidationReads,
              'verifiedAreaRecordReused': verifiedAreaRecordReused,
            },
          );
          return TerminalModeActivationResult(
            success: false,
            message: '선택한 지역에서 해당 업무 모드를 사용할 수 없습니다.',
            firebaseAreaValidationReads: firebaseAreaValidationReads,
            verifiedAreaRecordReused: verifiedAreaRecordReused,
          );
        }
        activationAreaValidationReads = firebaseAreaValidationReads;
        activationVerifiedAreaRecordReused = verifiedAreaRecordReused;
        final userState = context.read<UserState>();
        if (persistence == TerminalSessionPersistence.ephemeral) {
          userState.applyEphemeralLoginUser(updatedUser);
        } else if (account.activated) {
          await userState.updateLoginUserLocalOnly(updatedUser);
        } else {
          await userState.updateLoginUser(updatedUser);
        }
        await prefs.setString('phone', updatedUser.phone);
        await prefs.setString('selectedArea', areaToSet);
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
        LauncherDiagnostics.record(
          'auth_work_area_activation_complete',
          meta: <String, Object?>{
            'area': areaToSet,
            'division': divisionToSet,
            'restoredSession': account.activated,
            'firebaseAreaValidationReads': firebaseAreaValidationReads,
            'firebaseWorkAreaListReads': 0,
            'verifiedAreaRecordReused': verifiedAreaRecordReused,
            'firebaseUserWrites': account.activated ||
                    persistence == TerminalSessionPersistence.ephemeral
                ? 0
                : 1,
          },
        );
      }

      if (!account.activated) {
        switch (account.kind) {
          case TerminalAccountKind.user:
            break;
          case TerminalAccountKind.personal:
            final personalAccount = account.personalAccount;
            if (personalAccount == null) {
              return const TerminalModeActivationResult(
                success: false,
                message: '개인형 로그인 세션을 활성화할 수 없습니다.',
              );
            }
            final controller = PersonalLoginController(context);
            try {
              final result = await controller.activateAuthenticatedAccount(
                personalAccount,
                persistSession:
                    persistence == TerminalSessionPersistence.persistent,
              );
              if (!result.success) {
                return TerminalModeActivationResult(
                  success: false,
                  message: result.message,
                );
              }
            } finally {
              controller.dispose();
            }
            break;
          case TerminalAccountKind.tablet:
            final tablet = account.tablet;
            if (tablet == null) {
              return const TerminalModeActivationResult(
                success: false,
                message: '태블릿형 로그인 세션을 활성화할 수 없습니다.',
              );
            }
            final controller = TabletLoginController(
              context,
              onLoginSucceeded: () {},
            );
            try {
              final success = await controller.activateAuthenticatedTablet(
                tablet,
                persistSession:
                    persistence == TerminalSessionPersistence.persistent,
              );
              if (!success) {
                return const TerminalModeActivationResult(
                  success: false,
                  message: '태블릿형 로그인 세션을 활성화하지 못했습니다.',
                );
              }
            } finally {
              controller.dispose();
            }
            break;
        }
      }

      final persistedMode = AppModeRegistry.persistedValue(mode.id);
      await prefs.setString('mode', persistedMode);
      final areaState = context.read<AreaState>();
      var ttsArea = areaState.currentArea.trim();
      if (ttsArea.isEmpty && account.user != null) {
        ttsArea = (account.user!.selectedArea ?? account.user!.currentArea ?? '').trim();
      }
      if (ttsArea.isEmpty && account.personalAccount != null) {
        ttsArea = account.personalAccount!.selectedArea.trim();
      }
      if (ttsArea.isEmpty && account.tablet != null) {
        ttsArea = (account.tablet!.selectedArea ?? account.tablet!.currentArea ?? '').trim();
      }
      var homeArea = '';
      var division = areaState.currentDivision.trim();
      if (account.user != null) {
        homeArea = account.user!.areas.firstOrNull ?? '';
        if (division.isEmpty) {
          division = account.user!.divisions.firstOrNull ?? '';
        }
      } else if (account.personalAccount != null) {
        homeArea = account.personalAccount!.selectedArea.trim();
      } else if (account.tablet != null) {
        homeArea = account.tablet!.areas.firstOrNull ?? '';
        if (division.isEmpty) {
          division = account.tablet!.divisions.firstOrNull ?? '';
        }
      }
      final currentRecord = areaState.currentRecord;
      final homeIsHeadquarter =
          homeArea.trim().isNotEmpty && homeArea.trim() == ttsArea
              ? currentRecord?.isHeadquarter
              : null;
      final ttsResult = await WorkAreaSessionCoordinator.activate(
        currentArea: ttsArea,
        division: division,
        homeArea: homeArea,
        mode: persistedMode,
        currentIsHeadquarter: currentRecord?.isHeadquarter,
        homeIsHeadquarter: homeIsHeadquarter,
        source: persistence == TerminalSessionPersistence.ephemeral
            ? 'launcher_debug_ephemeral_mode'
            : account.activated
                ? 'launcher_restore_mode'
                : 'launcher_manual_mode',
        persistMode: persistence == TerminalSessionPersistence.persistent,
      );
      LauncherDiagnostics.record(
        'plate_tts_session_activation',
        meta: <String, Object?>{
          'mode': persistedMode,
          'area': ttsArea,
          'foregroundServiceRunning': ttsResult.foregroundServiceRunning,
          'foregroundOwner': ttsResult.foregroundOwner,
          'appFallbackListening': ttsResult.appFallbackListening,
          'ready': ttsResult.ready,
        },
      );
      if (persistence == TerminalSessionPersistence.persistent) {
        await persistAccountKind(account.kind);
      }
      LauncherDiagnostics.record(
        'auth_mode_activation_success',
        meta: <String, Object?>{
          'accountKind': accountKindId(account.kind),
          'mode': mode.id,
          'targetArea': targetArea.trim(),
          'isHeadquarter': areaState.currentRecord?.isHeadquarter == true,
          'firebaseSupportedModeQueries': 0,
          'firebaseModeSelectionQueries': 0,
          'firebaseAreaValidationReads': activationAreaValidationReads,
          'verifiedAreaRecordReused': activationVerifiedAreaRecordReused,
          'sessionPersistence': sessionPersistenceId(persistence),
        },
      );
      return TerminalModeActivationResult(
        success: true,
        message: '${mode.koreanName} 모드를 시작합니다.',
        firebaseAreaValidationReads: activationAreaValidationReads,
        verifiedAreaRecordReused: activationVerifiedAreaRecordReused,
      );
    } catch (error, stackTrace) {
      LauncherDiagnostics.record(
        'auth_mode_activation_error',
        meta: <String, Object?>{
          'accountKind': accountKindId(account.kind),
          'mode': mode.id,
          'sessionPersistence': sessionPersistenceId(persistence),
          'error': error,
          'stack': stackTrace,
        },
      );
      return const TerminalModeActivationResult(
        success: false,
        message: '모드 세션을 준비하지 못했습니다.',
      );
    }
  }

  static String _maskPhone(String value) {
    if (value.length < 7) {
      return List<String>.filled(value.length, '*').join();
    }
    final start = value.substring(0, 3);
    final end = value.substring(value.length - 4);
    return '$start****$end';
  }
}
