import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../app/utils/access_gate_diagnostics.dart';
import '../../../app/utils/status_dialog.dart';
import 'developer_account_authorization.dart';

class AccountGroupAuthorization {
  AccountGroupAuthorization._();

  static const String developerPath =
      'developer_login_gate/authorization';
  static const String administratorPath =
      'administrator_login_gate/authorization';

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
        'started', source: source, group: group,
      );
      final document = await FirebaseFirestore.instance
          .doc(isDeveloper ? developerPath : administratorPath)
          .get(const GetOptions(source: Source.server));
      final allowed = document.data()?['allowedEmails'];
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
    if (!approved && context.mounted) {
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
