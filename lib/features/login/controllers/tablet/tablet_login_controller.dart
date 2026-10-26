import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../app/di/routes.dart';
import '../../../../app/utils/dev_firebase_debug_dialog.dart';
import '../../../../features/account/applications/tablet_account_diagnostics.dart';
import '../../../../features/account/applications/user_state.dart';
import '../../../../features/account/domain/models/tablet/tablet_model.dart';
import '../../../../features/account/domain/repositories/user_repository.dart';
import '../../../../features/tablet/applications/tablet_pad_mode_state.dart';
import '../../../../shared/auth/account_code_number.dart';
import '../../debug/login_debug_trace.dart';
import '../../../../shared/work_session/application/work_area_session_coordinator.dart';
import '../../../dev/application/area_state.dart';
import '../area_login_session_refresher.dart';
import '../../applications/tablet/tablet_login_network_service.dart';
import '../../applications/tablet/tablet_login_validate.dart';

String _ts() => DateTime.now().toIso8601String();

void _debug(Object? message) {
  LoginDebugTrace.log('tablet', message);
}


enum TabletIdentityFailureKind {
  none,
  invalidInput,
  networkError,
  accountNotFound,
  nameMismatch,
  ambiguousAccount,
  invalidAccountData,
  lookupError,
}

class TabletCredentialAuthenticationResult {
  const TabletCredentialAuthenticationResult({
    required this.success,
    required this.message,
    this.tablet,
    this.failureKind = TabletIdentityFailureKind.none,
  });

  final bool success;
  final String message;
  final TabletModel? tablet;
  final TabletIdentityFailureKind failureKind;
}

class TabletLoginController {
  TabletLoginController(
    this.context, {
    this.onLoginSucceeded,
  });

  final BuildContext context;
  final VoidCallback? onLoginSucceeded;

  final TextEditingController nameController = TextEditingController();
  final TextEditingController codeNumberController = TextEditingController();

  final FocusNode nameFocus = FocusNode();
  final FocusNode codeNumberFocus = FocusNode();

  bool isLoading = false;
  bool _inited = false;

  PadMode get _targetPadMode => PadMode.big;
  String get _savedMode => 'tablet';

  Future<bool> tryAutoLogin({bool navigateOnSuccess = true}) async {
    await Provider.of<UserState>(context, listen: false).loadTabletToLogIn();
    final isLoggedIn =
        Provider.of<UserState>(context, listen: false).isLoggedIn;
    _debug(
      '[LOGIN-TABLET][${_ts()}] autoLogin check → isLoggedIn=$isLoggedIn',
    );
    if (!isLoggedIn || !context.mounted) return false;

    context.read<TabletPadModeState>().setMode(_targetPadMode);
    if (navigateOnSuccess) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!context.mounted) return;
        _debug('[LOGIN-TABLET][${_ts()}] autoLogin → onLoginSucceeded()');
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

  Future<TabletCredentialAuthenticationResult> resolveIdentity({
    String? name,
    String? codeNumber,
  }) async {
    final resolvedName = (name ?? nameController.text).trim();
    final resolvedCodeNumber = AccountCodeNumber.normalize(
      codeNumber ?? codeNumberController.text,
    );

    if (resolvedName.isEmpty) {
      return const TabletCredentialAuthenticationResult(
        success: false,
        message: '이름을 다시 확인하세요.',
        failureKind: TabletIdentityFailureKind.invalidInput,
      );
    }

    final codeNumberError =
        TabletLoginValidate.validateCodeNumber(resolvedCodeNumber);
    if (codeNumberError != null) {
      return TabletCredentialAuthenticationResult(
        success: false,
        message: codeNumberError,
        failureKind: TabletIdentityFailureKind.invalidInput,
      );
    }

    final isConn = await TabletLoginNetworkService().isConnected();
    if (!isConn) {
      return const TabletCredentialAuthenticationResult(
        success: false,
        message: '네트워크 연결을 확인하세요.',
        failureKind: TabletIdentityFailureKind.networkError,
      );
    }

    try {
      final repo = context.read<UserRepository>();
      final candidates =
          await repo.searchTabletsByCodeNumber(resolvedCodeNumber);
      final matches = candidates
          .where((tablet) => tablet.name == resolvedName)
          .toList(growable: false);

      TabletAccountDiagnostics.record(
        'manual_identity_candidates_resolved',
        meta: <String, Object?>{
          'codeNumber': AccountCodeNumber.mask(resolvedCodeNumber),
          'candidateCount': candidates.length,
          'identityMatchCount': matches.length,
          'documentIds': candidates
              .map((tablet) => AccountCodeNumber.maskDocumentId(tablet.id))
              .join(','),
        },
      );

      if (matches.isEmpty) {
        return TabletCredentialAuthenticationResult(
          success: false,
          message: '입력한 계정 정보를 다시 확인하세요.',
          failureKind: candidates.isEmpty
              ? TabletIdentityFailureKind.accountNotFound
              : TabletIdentityFailureKind.nameMismatch,
        );
      }

      if (matches.length > 1) {
        TabletAccountDiagnostics.record(
          'manual_identity_ambiguous',
          meta: <String, Object?>{
            'codeNumber': AccountCodeNumber.mask(resolvedCodeNumber),
            'matchCount': matches.length,
            'documentIds': matches
                .map((tablet) => AccountCodeNumber.maskDocumentId(tablet.id))
                .join(','),
          },
        );
        return const TabletCredentialAuthenticationResult(
          success: false,
          message: '같은 계정 정보의 태블릿 계정이 여러 업무 지역에 존재합니다.',
          failureKind: TabletIdentityFailureKind.ambiguousAccount,
        );
      }

      final tablet = matches.single;
      final areaName = (tablet.selectedArea ??
              tablet.currentArea ??
              (tablet.areas.isNotEmpty ? tablet.areas.first : ''))
          .trim();
      if (areaName.isEmpty) {
        return const TabletCredentialAuthenticationResult(
          success: false,
          message: '태블릿 계정의 지역 정보가 없습니다.',
          failureKind: TabletIdentityFailureKind.invalidAccountData,
        );
      }

      return TabletCredentialAuthenticationResult(
        success: true,
        message: '${tablet.name}님의 태블릿 계정 정보를 확인했습니다.',
        tablet: tablet,
      );
    } catch (e, st) {
      await DevFirebaseDebugDialog.show(
        context: context,
        operation: 'tablet.resolveIdentity',
        error: e,
        stackTrace: st,
        details: <String, Object?>{
          'codeNumber': AccountCodeNumber.mask(resolvedCodeNumber),
          'nameLength': resolvedName.length,
          'targetMode': _savedMode,
          'controller': 'TabletLoginController',
        },
      );
      return const TabletCredentialAuthenticationResult(
        success: false,
        message: '태블릿형 계정 확인 중 오류가 발생했습니다.',
        failureKind: TabletIdentityFailureKind.lookupError,
      );
    }
  }

  Future<bool> activateAuthenticatedTablet(
    TabletModel tablet, {
    bool persistSession = true,
  }) async {
    try {
      final codeNumber = AccountCodeNumber.normalize(tablet.codeNumber);
      final userState = context.read<UserState>();
      final areaState = context.read<AreaState>();
      final areaName = (tablet.selectedArea ??
              tablet.currentArea ??
              (tablet.areas.isNotEmpty ? tablet.areas.first : ''))
          .trim();
      if (areaName.isEmpty) return false;

      final englishAreaName = tablet.englishSelectedAreaName ?? areaName;
      final canonicalId = AccountCodeNumber.documentId(
        codeNumber: codeNumber,
        area: areaName,
      );
      final sourceId = tablet.id;
      final sessionTablet = tablet.copyWith(
        id: canonicalId.isEmpty ? sourceId : canonicalId,
        currentArea: areaName,
        selectedArea: areaName,
        englishSelectedAreaName: englishAreaName,
        isSaved: persistSession ? true : tablet.isSaved,
      );
      TabletAccountDiagnostics.record(
        'authenticated_document_id_resolved',
        meta: <String, Object?>{
          'sourceId': AccountCodeNumber.maskDocumentId(sourceId),
          'documentId': AccountCodeNumber.maskDocumentId(sessionTablet.id),
          'migrationRequired': sourceId != sessionTablet.id,
          'persistSession': persistSession,
        },
      );
      final divisionToSet = sessionTablet.companyId;
      await AreaLoginSessionRefresher.refresh(
        context: context,
        areaState: areaState,
        division: divisionToSet,
        area: areaName,
        operationLabel: 'tablet',
      );
      _debug(
        '[LOGIN-TABLET][${_ts()}] AreaRecord 서버 강제 동기화 완료: $divisionToSet/$areaName',
      );

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('tabletCodeNumber', codeNumber);
      await prefs.remove('tabletPhone');
      await prefs.remove('phone');
      await prefs.remove('handle');
      await prefs.setString('selectedArea', areaName);
      await prefs.setString('englishSelectedAreaName', englishAreaName);
      await prefs.setString('mode', _savedMode);
      _debug(
        '[LOGIN-TABLET][${_ts()}] prefs saved (tabletCodeNumber/selectedArea/englishSelectedAreaName/mode=$_savedMode)',
      );

      if (persistSession) {
        await userState.updateLoginTablet(
          sessionTablet,
          previousId: sourceId == sessionTablet.id ? null : sourceId,
        );
      } else {
        userState.applyEphemeralLoginTablet(sessionTablet);
      }
      _debug(
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
      _debug(
        '[LOGIN-TABLET][${_ts()}] work session sync area=${workSession.currentArea} mode=${workSession.mode} foreground=${workSession.foregroundServiceRunning} appFallback=${workSession.appFallbackListening}',
      );

      return true;
    } catch (e, st) {
      _debug(
        '[LOGIN-TABLET][${_ts()}] activate authenticated tablet error: $e\n$st',
      );
      await DevFirebaseDebugDialog.show(
        context: context,
        operation: 'tablet.activateAuthenticatedTablet',
        error: e,
        stackTrace: st,
        details: <String, Object?>{
          'tabletId': tablet.id,
          'codeNumber': AccountCodeNumber.mask(tablet.codeNumber),
          'nameLength': tablet.name.length,
          'targetMode': _savedMode,
          'controller': 'TabletLoginController',
          'persistSession': persistSession,
        },
      );
      return false;
    }
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

  void dispose() {
    nameController.dispose();
    codeNumberController.dispose();
    nameFocus.dispose();
    codeNumberFocus.dispose();
  }
}
