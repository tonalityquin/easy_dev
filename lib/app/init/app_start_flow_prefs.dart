import 'package:shared_preferences/shared_preferences.dart';

import 'app_start_user_purpose.dart';

class AppStartFlowPrefs {
  static const String legacyTutorialResultKey = 'app_start_tutorial_result';
  static const String usedBeforeKey = 'app_used_before';

  static const String permissionTutorialDoneKey =
      'app_start_permission_tutorial_done_v1';
  static const String permissionTutorialPurposeKey =
      'app_start_permission_tutorial_purpose_v1';
  static const String userPurposeKey = 'app_start_user_purpose_v1';
  static const String permissionNoticeDoneKey =
      'app_start_permission_notice_done_v1';
  static const String selectorScreenTutorialDoneKey =
      'app_start_selector_screen_tutorial_done_v1';
  static const String googleServicesSetupDoneKey =
      'app_start_google_services_setup_done_v1';
  static const String googleServicesSetupSkippedKey =
      'app_start_google_services_setup_skipped_v1';

  static const String termsOfServiceAgreedKey =
      'app_start_terms_of_service_agreed_v1';
  static const String privacyPolicyAgreedKey =
      'app_start_privacy_policy_agreed_v1';
  static const String accountDeletionPolicyAgreedKey =
      'app_start_account_deletion_policy_agreed_v1';

  static const String legacyYes = 'yes';
  static const String legacyUsageTutorialDoneKey =
      'app_start_usage_tutorial_done_v1';

  static Future<void> migrateFromLegacyIfNeeded() async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys();

    final hasPerm = keys.contains(permissionTutorialDoneKey);
    final hasSelector = keys.contains(selectorScreenTutorialDoneKey);
    if (hasPerm && hasSelector) return;

    if (!hasSelector && keys.contains(legacyUsageTutorialDoneKey)) {
      final v = prefs.getBool(legacyUsageTutorialDoneKey) ?? false;
      await prefs.setBool(selectorScreenTutorialDoneKey, v);
    }

    final legacy = prefs.getString(legacyTutorialResultKey);
    if (legacy == legacyYes) {
      if (!hasPerm) await prefs.setBool(permissionTutorialDoneKey, true);
      if (!(prefs.getKeys().contains(selectorScreenTutorialDoneKey))) {
        await prefs.setBool(selectorScreenTutorialDoneKey, true);
      }
      return;
    }

    if (!hasPerm) await prefs.setBool(permissionTutorialDoneKey, false);
    if (!(prefs.getKeys().contains(selectorScreenTutorialDoneKey))) {
      await prefs.setBool(selectorScreenTutorialDoneKey, false);
    }
  }

  static Future<AppStartUserPurpose?> getUserPurpose() async {
    final prefs = await SharedPreferences.getInstance();
    return parseAppStartUserPurpose(prefs.getString(userPurposeKey));
  }

  static Future<void> setUserPurpose(AppStartUserPurpose purpose) async {
    final prefs = await SharedPreferences.getInstance();
    final previous = prefs.getString(userPurposeKey);
    final next = purpose.storageValue;
    await prefs.setString(userPurposeKey, next);
    if (previous != next) {
      await prefs.setBool(permissionTutorialDoneKey, false);
      await prefs.remove(permissionTutorialPurposeKey);
      await prefs.setBool(permissionNoticeDoneKey, false);
    }
  }

  static Future<bool> getPermissionNoticeDone() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(permissionNoticeDoneKey) ?? false;
  }

  static Future<void> setPermissionNoticeDone(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(permissionNoticeDoneKey, value);
  }

  static Future<bool> getPermissionTutorialDone() async {
    final prefs = await SharedPreferences.getInstance();
    final done = prefs.getBool(permissionTutorialDoneKey) ?? false;
    if (!done) return false;

    final purpose = parseAppStartUserPurpose(prefs.getString(userPurposeKey));
    if (purpose == null) return true;

    final completedPurpose = prefs.getString(permissionTutorialPurposeKey);
    return completedPurpose == purpose.storageValue;
  }

  static Future<void> setPermissionTutorialDone(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(permissionTutorialDoneKey, value);
    if (!value) {
      await prefs.remove(permissionTutorialPurposeKey);
      return;
    }

    final purpose = parseAppStartUserPurpose(prefs.getString(userPurposeKey));
    if (purpose == null) {
      await prefs.remove(permissionTutorialPurposeKey);
      return;
    }

    await prefs.setString(permissionTutorialPurposeKey, purpose.storageValue);
  }

  static Future<bool> getGoogleServicesSetupDone() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(googleServicesSetupDoneKey) ?? false;
  }

  static Future<void> setGoogleServicesSetupDone(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(googleServicesSetupDoneKey, value);
    if (value) {
      await prefs.setBool(googleServicesSetupSkippedKey, false);
    }
  }

  static Future<bool> getGoogleServicesSetupSkipped() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(googleServicesSetupSkippedKey) ?? false;
  }

  static Future<void> setGoogleServicesSetupSkipped(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(googleServicesSetupSkippedKey, value);
    if (value) {
      await prefs.setBool(googleServicesSetupDoneKey, false);
    }
  }

  static Future<bool> getSelectorScreenTutorialDone() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(selectorScreenTutorialDoneKey) ?? false;
  }

  static Future<void> setSelectorScreenTutorialDone(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(selectorScreenTutorialDoneKey, value);
  }

  static Future<bool> getTermsOfServiceAgreed() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(termsOfServiceAgreedKey) ?? false;
  }

  static Future<void> setTermsOfServiceAgreed(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(termsOfServiceAgreedKey, value);
  }

  static Future<bool> getPrivacyPolicyAgreed() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(privacyPolicyAgreedKey) ?? false;
  }

  static Future<void> setPrivacyPolicyAgreed(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(privacyPolicyAgreedKey, value);
  }

  static Future<bool> getAccountDeletionPolicyAgreed() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(accountDeletionPolicyAgreedKey) ?? false;
  }

  static Future<void> setAccountDeletionPolicyAgreed(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(accountDeletionPolicyAgreedKey, value);
  }

  static Future<bool> getAllPolicyConsentsDone() async {
    final terms = await getTermsOfServiceAgreed();
    if (!terms) return false;

    final privacy = await getPrivacyPolicyAgreed();
    if (!privacy) return false;

    return getAccountDeletionPolicyAgreed();
  }

  static Future<void> resetPolicyConsents() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(termsOfServiceAgreedKey, false);
    await prefs.setBool(privacyPolicyAgreedKey, false);
    await prefs.setBool(accountDeletionPolicyAgreedKey, false);
    await prefs.setBool(googleServicesSetupDoneKey, false);
    await prefs.setBool(googleServicesSetupSkippedKey, false);
  }

  static Future<void> resetTutorialFlags() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(permissionTutorialDoneKey, false);
    await prefs.remove(permissionTutorialPurposeKey);
    await prefs.remove(userPurposeKey);
    await prefs.setBool(permissionNoticeDoneKey, false);
    await prefs.setBool(selectorScreenTutorialDoneKey, false);
    await prefs.setBool(termsOfServiceAgreedKey, false);
    await prefs.setBool(privacyPolicyAgreedKey, false);
    await prefs.setBool(accountDeletionPolicyAgreedKey, false);
    await prefs.setBool(googleServicesSetupDoneKey, false);
    await prefs.setBool(googleServicesSetupSkippedKey, false);
  }

  static Future<bool> getUsedBefore() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(usedBeforeKey) ?? false;
  }

  static Future<void> setUsedBefore(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(usedBeforeKey, value);
  }
}
