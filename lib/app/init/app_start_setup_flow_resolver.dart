import 'app_start_flow_prefs.dart';
import 'app_start_user_purpose.dart';

enum AppStartSetupPhase {
  purpose,
  permissionNotice,
  permission,
  terms,
  privacy,
  accountDeletion,
  googleServices,
  complete,
}

class AppStartSetupSnapshot {
  const AppStartSetupSnapshot({
    required this.permissionDone,
    required this.purpose,
    required this.noticeDone,
    required this.termsDone,
    required this.privacyDone,
    required this.accountDeletionDone,
    required this.googleDone,
    required this.googleSkipped,
  });

  final bool permissionDone;
  final AppStartUserPurpose? purpose;
  final bool noticeDone;
  final bool termsDone;
  final bool privacyDone;
  final bool accountDeletionDone;
  final bool googleDone;
  final bool googleSkipped;

  AppStartSetupPhase get phase {
    if (!permissionDone) {
      if (purpose == null) return AppStartSetupPhase.purpose;
      if (!noticeDone) return AppStartSetupPhase.permissionNotice;
      return AppStartSetupPhase.permission;
    }

    if (purpose?.skipsPolicyAndPostSetup == true) {
      return AppStartSetupPhase.complete;
    }

    if (!termsDone) return AppStartSetupPhase.terms;
    if (!privacyDone) return AppStartSetupPhase.privacy;
    if (!accountDeletionDone) return AppStartSetupPhase.accountDeletion;

    if (purpose?.requiresGoogleServicesSetup == true &&
        !googleDone &&
        !googleSkipped) {
      return AppStartSetupPhase.googleServices;
    }

    return AppStartSetupPhase.complete;
  }

  bool get complete => phase == AppStartSetupPhase.complete;

  Map<String, Object?> toDebugMeta() {
    return <String, Object?>{
      'phase': phase.name,
      'permissionDone': permissionDone,
      'purpose': purpose?.storageValue ?? 'none',
      'noticeDone': noticeDone,
      'termsDone': termsDone,
      'privacyDone': privacyDone,
      'accountDeletionDone': accountDeletionDone,
      'googleDone': googleDone,
      'googleSkipped': googleSkipped,
    };
  }
}

class AppStartSetupFlowResolver {
  const AppStartSetupFlowResolver._();

  static Future<AppStartSetupSnapshot> resolve() async {
    await AppStartFlowPrefs.migrateFromLegacyIfNeeded();
    final permissionDone = await AppStartFlowPrefs.getPermissionTutorialDone();
    final purpose = await AppStartFlowPrefs.getUserPurpose();
    final noticeDone = await AppStartFlowPrefs.getPermissionNoticeDone();
    final termsDone = await AppStartFlowPrefs.getTermsOfServiceAgreed();
    final privacyDone = await AppStartFlowPrefs.getPrivacyPolicyAgreed();
    final accountDeletionDone =
        await AppStartFlowPrefs.getAccountDeletionPolicyAgreed();
    final googleDone = await AppStartFlowPrefs.getGoogleServicesSetupDone();
    final googleSkipped =
        await AppStartFlowPrefs.getGoogleServicesSetupSkipped();

    return AppStartSetupSnapshot(
      permissionDone: permissionDone,
      purpose: purpose,
      noticeDone: noticeDone,
      termsDone: termsDone,
      privacyDone: privacyDone,
      accountDeletionDone: accountDeletionDone,
      googleDone: googleDone,
      googleSkipped: googleSkipped,
    );
  }
}
