import 'package:shared_preferences/shared_preferences.dart';

import '../page/hot_keys/single_inside_hot_key_content.dart';
import 'single_inside_diagnostics.dart';

class SingleInsideHotKeyPrefs {
  SingleInsideHotKeyPrefs._();

  static const String _prefix = 'single_hotkey.v1';
  static const String _emptyValue = '__empty__';
  static const String _configuredSuffix = 'configured';
  static const String _emptyDefaultMigrationSuffix =
      'migration.empty_default_v2';

  static const List<SingleInsideHotKeyContent> _legacyAutoDefault =
      <SingleInsideHotKeyContent>[
    SingleInsideHotKeyContent.workRules,
    SingleInsideHotKeyContent.commuteSubmit,
    SingleInsideHotKeyContent.workManual,
    SingleInsideHotKeyContent.restTimeSubmit,
  ];

  static Future<SingleInsideHotKeyConfig> load({
    required String userId,
    required Set<SingleInsideHotKeyContent> allowed,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final keys = List<String>.generate(4, (index) => _key(userId, index + 1));
    final raw = keys.map(prefs.getString).toList(growable: false);
    final stored = keys.map(prefs.containsKey).toList(growable: false);
    final decoded = raw.map(_decode).toList(growable: false);
    final normalized = <SingleInsideHotKeyContent?>[
      for (final value in decoded) allowed.contains(value) ? value : null,
    ];
    final configured = prefs.getBool(_configuredKey(userId)) ?? false;
    final migrationKey = _emptyDefaultMigrationKey(userId);
    final migrationDone = prefs.getBool(migrationKey) ?? false;
    var migrationCompleted = migrationDone;
    var changed = false;
    var migratedLegacyDefault = false;

    for (var index = 0; index < 4; index++) {
      final value = decoded[index];
      final rawValue = (raw[index] ?? '').trim();
      if (stored[index] && value != null && !allowed.contains(value)) {
        changed = true;
      }
      if (stored[index] &&
          rawValue.isNotEmpty &&
          rawValue != _emptyValue &&
          value == null) {
        changed = true;
      }
    }

    if (!migrationDone) {
      final legacyAutoDefault = !configured &&
          stored.every((value) => value) &&
          List<bool>.generate(
            4,
            (index) => decoded[index] == _legacyAutoDefault[index],
          ).every((value) => value);
      if (legacyAutoDefault) {
        for (var index = 0; index < normalized.length; index++) {
          normalized[index] = null;
        }
        changed = true;
        migratedLegacyDefault = true;
      }
    }

    final dedupe = <SingleInsideHotKeyContent>{};
    for (var index = 0; index < normalized.length; index++) {
      final value = normalized[index];
      if (value == null) continue;
      if (!dedupe.add(value)) {
        normalized[index] = null;
        changed = true;
      }
    }

    final config = SingleInsideHotKeyConfig(
      slot1: normalized[0],
      slot2: normalized[1],
      slot3: normalized[2],
      slot4: normalized[3],
    );

    if (changed) {
      await save(
        userId: userId,
        config: config,
        markConfigured: false,
      );
    }
    if (!migrationDone) {
      await prefs.setBool(migrationKey, true);
      migrationCompleted = true;
    }

    SingleInsideDiagnostics.log(
      'hotkey',
      'prefs_load user=${_safeUser(userId)} configured=$configured migrationDone=$migrationCompleted migratedLegacyDefault=$migratedLegacyDefault slot1=${config.slot1?.name ?? 'empty'} slot2=${config.slot2?.name ?? 'empty'} slot3=${config.slot3?.name ?? 'empty'} slot4=${config.slot4?.name ?? 'empty'} allowed=${allowed.map((item) => item.name).join(',')}',
    );
    return config;
  }

  static Future<void> save({
    required String userId,
    required SingleInsideHotKeyConfig config,
    required bool markConfigured,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await _writeSlot(prefs, _key(userId, 1), config.slot1);
    await _writeSlot(prefs, _key(userId, 2), config.slot2);
    await _writeSlot(prefs, _key(userId, 3), config.slot3);
    await _writeSlot(prefs, _key(userId, 4), config.slot4);
    if (markConfigured) {
      await prefs.setBool(_configuredKey(userId), true);
    }
    final configured = prefs.getBool(_configuredKey(userId)) ?? false;
    SingleInsideDiagnostics.log(
      'hotkey',
      'prefs_save user=${_safeUser(userId)} configured=$configured markConfigured=$markConfigured slot1=${config.slot1?.name ?? 'empty'} slot2=${config.slot2?.name ?? 'empty'} slot3=${config.slot3?.name ?? 'empty'} slot4=${config.slot4?.name ?? 'empty'}',
    );
  }

  static String _key(String userId, int slot) {
    final normalized = userId.trim().isEmpty ? 'anonymous' : userId.trim();
    return '$_prefix.$normalized.slot$slot';
  }

  static String _configuredKey(String userId) {
    final normalized = userId.trim().isEmpty ? 'anonymous' : userId.trim();
    return '$_prefix.$normalized.$_configuredSuffix';
  }

  static String _emptyDefaultMigrationKey(String userId) {
    final normalized = userId.trim().isEmpty ? 'anonymous' : userId.trim();
    return '$_prefix.$normalized.$_emptyDefaultMigrationSuffix';
  }

  static SingleInsideHotKeyContent? _decode(String? raw) {
    final normalized = (raw ?? '').trim();
    if (normalized.isEmpty || normalized == _emptyValue) return null;
    for (final value in SingleInsideHotKeyContent.values) {
      if (value.name == normalized) return value;
    }
    return null;
  }

  static Future<void> _writeSlot(
    SharedPreferences prefs,
    String key,
    SingleInsideHotKeyContent? value,
  ) async {
    await prefs.setString(key, value?.name ?? _emptyValue);
  }

  static String _safeUser(String userId) {
    final value = userId.trim();
    if (value.length <= 6) return value.isEmpty ? '-' : value;
    return '${value.substring(0, 3)}...${value.substring(value.length - 2)}';
  }
}
