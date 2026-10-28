import '../../../app/firebase_activity/firebase_activity_monitor.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../app/utils/access_gate_diagnostics.dart';
import '../../../app/utils/status_dialog.dart';
import '../../selector/application/dev_auth.dart';
import 'login_gate_paths.dart';
import 'developer_account_authorization.dart';

class AccountGroupAuthorization {
  AccountGroupAuthorization._();

  static const String developerPath =
      LoginGatePaths.developer;
  static const String administratorPath =
      LoginGatePaths.administrator;

  static final ValueNotifier<bool> lastVerified = ValueNotifier<bool>(false);

  static Future<bool> verify({required String source}) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      lastVerified.value = false;
      AccessGateDiagnostics.record(
        'denied',
        source: source,
        reason: 'firebase_auth_missing',
      );
      return false;
    }

    try {
      final token = await user.getIdTokenResult(true);
      final claims = token.claims ?? <String, dynamic>{};
      final email = (claims['email'] ?? '').toString().trim().toLowerCase();
      final isDeveloper =
          DeveloperAccountAuthorization.allowedEmails.contains(email);
      final group = isDeveloper ? 'developer' : 'administrator';
      if (isDeveloper) {
        final firebaseClaims = claims['firebase'];
        final provider = firebaseClaims is Map
            ? firebaseClaims['sign_in_provider']?.toString()
            : null;
        if (claims['email_verified'] != true || provider != 'google.com') {
          lastVerified.value = false;
          AccessGateDiagnostics.record(
            'denied',
            source: source,
            group: group,
            reason: 'developer_identity_claims_invalid',
          );
          return false;
        }
      }
      if (!isDeveloper && user.isAnonymous) {
        lastVerified.value = false;
        AccessGateDiagnostics.record(
          'denied', source: source, group: group,
          reason: 'anonymous_administrator_not_allowed',
        );
        return false;
      }
      final firebaseClaims = claims['firebase'];
      final provider = firebaseClaims is Map
          ? firebaseClaims['sign_in_provider']?.toString()
          : null;
      if (!isDeveloper && (claims['email_verified'] != true ||
          provider != 'google.com' || email.isEmpty)) {
        lastVerified.value = false;
        AccessGateDiagnostics.record(
          'denied', source: source, group: group,
          reason: 'administrator_google_identity_required',
        );
        return false;
      }
      AccessGateDiagnostics.record(
        'started',
        source: source,
        group: group,
        reason: isDeveloper ? developerPath : administratorPath,
      );
      final document = await FirebaseActivityMonitor.track(FirebaseActivityKind.read, () => FirebaseFirestore.instance
          .doc(isDeveloper ? developerPath : administratorPath)
          .get(const GetOptions(source: Source.server)), source: 'account_group_authorization.get');
      final allowed = document.data()?['allow'];
      final approved = document.exists && document.data()?['enabled'] == true &&
          (isDeveloper || (allowed is List && allowed.contains(email)));
      lastVerified.value = approved;
      AccessGateDiagnostics.record(
        approved ? 'approved' : 'denied',
        source: source,
        group: group,
        reason: approved ? 'server_enabled' : 'server_disabled_or_missing',
      );
      return approved;
    } catch (error) {
      lastVerified.value = false;
      AccessGateDiagnostics.record(
        'failed',
        source: source,
        reason: error is FirebaseException ? error.code : error.runtimeType.toString(),
      );
      return false;
    }
  }

  static Future<bool> verifyWithStatus(
    BuildContext context, {
    required String source,
  }) async {
    final approved = await verify(source: source);
    if (!context.mounted) return approved;

    final developerMode = await DevAuth.isDevModeEnabled();
    if (!context.mounted) return approved;

    if (developerMode) {
      AccessGateDiagnostics.record(
        'status_open',
        source: source,
        reason: approved ? 'approved' : 'denied',
      );
      await StatusDialog.show(
        context,
        title: approved ? '서버 접근 승인 완료' : '서버 접근 승인 실패',
        tone: approved ? StatusDialogTone.success : StatusDialogTone.failure,
        description: approved
            ? '서버 접근 승인이 확인되었습니다.'
            : '현재 계정의 서버 접근 승인이 확인되지 않았습니다.',
        copyText: AccessGateDiagnostics.debugPrintCode,
        copyButtonLabel: 'debugPrint 코드 복사',
        visibleDuration: Duration.zero,
        transitionDuration: const Duration(milliseconds: 320),
        useCommonUi: true,
        awaitManualClose: true,
      );
      return approved;
    }

    if (!approved) {
      await StatusDialog.showFailure(
        context,
        title: '서버 접근 승인 실패',
        description: '현재 계정의 서버 접근 승인이 확인되지 않았습니다.',
        visibleDuration: const Duration(seconds: 4),
        useCommonUi: true,
      );
    }
    return approved;
  }
}
