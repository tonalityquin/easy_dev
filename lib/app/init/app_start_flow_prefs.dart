import 'package:shared_preferences/shared_preferences.dart';

class AppStartFlowPrefs {
  static const String legacyTutorialResultKey = 'app_start_tutorial_result';
  static const String usedBeforeKey = 'app_used_before';

  static const String permissionTutorialDoneKey =
      'app_start_permission_tutorial_done_v1';
  static const String selectorScreenTutorialDoneKey =
      'app_start_selector_screen_tutorial_done_v1';

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

  static Future<bool> getPermissionTutorialDone() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(permissionTutorialDoneKey) ?? false;
  }

  static Future<void> setPermissionTutorialDone(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(permissionTutorialDoneKey, value);
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
  }

  static Future<void> resetTutorialFlags() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(permissionTutorialDoneKey, false);
    await prefs.setBool(selectorScreenTutorialDoneKey, false);
    await prefs.setBool(termsOfServiceAgreedKey, false);
    await prefs.setBool(privacyPolicyAgreedKey, false);
    await prefs.setBool(accountDeletionPolicyAgreedKey, false);
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
