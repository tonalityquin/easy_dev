import 'package:flutter/foundation.dart';

import '../../../app/models/account_role_diagnostics.dart';
import '../../dashboard/applications/common/firebase_google_auth_bridge.dart';
import '../../selector/application/dev_auth.dart';
import 'developer_account_authorization.dart';

class DeveloperStructurePermissionException implements Exception {
  const DeveloperStructurePermissionException();

  @override
  String toString() => '회사·지역의 생성·수정·삭제는 인증된 개발자 계정에서만 가능합니다.';
}

class DeveloperStructureWriteGuard {
  DeveloperStructureWriteGuard._();

  static const String developerEmail =
      DeveloperAccountAuthorization.developerEmail;

  static Future<void> requireAuthorized({
    required String operation,
    bool requireDeveloperMode = true,
  }) async {
    final developerMode = await DevAuth.isDevModeEnabled();
    final approval = DeveloperAccountAuthorization.isAuthorized;
    final user = FirebaseGoogleAuthBridge.instance.currentUser;
    final currentEmail = user?.email?.trim().toLowerCase();
    final signedIn = user != null && !user.isAnonymous;
    final initialMatch = signedIn && currentEmail == developerEmail;
    var tokenEmailMatch = false;
    var tokenVerified = false;
    var sessionUnchanged = false;
    var tokenError = false;

    if (user != null &&
        approval &&
        initialMatch &&
        (!requireDeveloperMode || developerMode)) {
      try {
        final tokenResult = await user.getIdTokenResult();
        final claims = tokenResult.claims;
        final tokenEmail =
            (claims?['email'] ?? '').toString().trim().toLowerCase();
        tokenEmailMatch = tokenEmail == developerEmail;
        tokenVerified = claims?['email_verified'] == true;
        final latest = FirebaseGoogleAuthBridge.instance.currentUser;
        sessionUnchanged = latest != null &&
            !latest.isAnonymous &&
            latest.email?.trim().toLowerCase() == developerEmail;
      } catch (_) {
        tokenError = true;
      }
    }

    final authorized = approval &&
        (!requireDeveloperMode || developerMode) &&
        initialMatch &&
        tokenEmailMatch &&
        tokenVerified &&
        sessionUnchanged &&
        !tokenError;

    if (developerMode) {
      AccountRoleDiagnostics.record(
        'dev_structure_write_auth operation=$operation outcome=${authorized ? 'allowed' : 'denied'} mode=$developerMode approval=$approval firebaseUser=$signedIn emailMatch=$initialMatch tokenEmailMatch=$tokenEmailMatch tokenVerified=$tokenVerified sessionUnchanged=$sessionUnchanged tokenError=$tokenError',
      );
    }
    if (!authorized) {
      if (developerMode) {
        debugPrint('[DEV_STRUCTURE_AUTH] operation=$operation result=denied');
      }
      throw const DeveloperStructurePermissionException();
    }
    if (developerMode) {
      debugPrint('[DEV_STRUCTURE_AUTH] operation=$operation result=allowed');
    }
  }
}
