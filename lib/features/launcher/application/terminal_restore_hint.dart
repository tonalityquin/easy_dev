import 'package:shared_preferences/shared_preferences.dart';

import 'app_mode_registry.dart';
import 'launcher_debug_account_override_store.dart';

class TerminalRestoreHint {
  const TerminalRestoreHint._();

  static const String accountKindPrefsKey = 'terminalAccountKind';

  static Future<String?> readAccountKindId({String? savedMode}) async {
    await LauncherDebugAccountOverrideStore.restoreIfNeeded(
      source: 'terminal_restore_hint',
    );
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final selectedArea = (prefs.getString('selectedArea') ?? '').trim();
    final phone = (prefs.getString('phone') ?? '').trim();
    final personalPhone = (prefs.getString('personalPhone') ?? '').trim();
    final personalAccountId =
        (prefs.getString('personalAccountId') ?? '').trim();
    final tabletPhone = (prefs.getString('tabletPhone') ?? '').trim();
    final handle = (prefs.getString('handle') ?? '').trim();
    final cachedUser = (prefs.getString('cachedUserJson') ?? '').trim();
    final hasUser =
        phone.isNotEmpty && selectedArea.isNotEmpty && cachedUser.isNotEmpty;
    final hasPersonal = selectedArea.isNotEmpty &&
        (personalPhone.isNotEmpty ||
            (personalAccountId.isNotEmpty && phone.isNotEmpty));
    final hasTablet =
        selectedArea.isNotEmpty && (tabletPhone.isNotEmpty || handle.isNotEmpty);

    bool available(String kind) {
      return switch (kind) {
        'user' => hasUser,
        'personal' => hasPersonal,
        'tablet' => hasTablet,
        _ => false,
      };
    }

    final stored =
        (prefs.getString(accountKindPrefsKey) ?? '').trim().toLowerCase();
    if (available(stored)) return stored;

    final mode = AppModeRegistry.findLegacy(savedMode ?? prefs.getString('mode'));
    final inferred = switch (mode?.id) {
      'personal' => 'personal',
      'tablet' => 'tablet',
      null => null,
      _ => 'user',
    };
    if (inferred != null && available(inferred)) {
      await prefs.setString(accountKindPrefsKey, inferred);
      return inferred;
    }

    final candidates = <String>[
      if (hasUser) 'user',
      if (hasPersonal) 'personal',
      if (hasTablet) 'tablet',
    ];
    if (candidates.length != 1) return null;
    final kind = candidates.single;
    await prefs.setString(accountKindPrefsKey, kind);
    return kind;
  }
}
