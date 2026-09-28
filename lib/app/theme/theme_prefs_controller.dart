import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'area_theme_registry.dart';
import 'brand_theme.dart';
import 'theme_debug_trace.dart';

enum AreaThemeChoice {
  defaultTheme,
  brand,
}

class ThemePrefsController extends ChangeNotifier {
  ThemePrefsController({ValueListenable<bool>? debugModeListenable})
      : _debugModeListenable = debugModeListenable {
    _debugModeListenable?.addListener(_handleDebugModeChanged);
  }

  static const int _schemaVersion = 4;
  static const String _schemaVersionKey = 'selector_theme_schema_version';
  static const String _areaOverridesKey = 'selector_area_theme_overrides_v1';
  static const String _areaThemeChoicesKey = 'selector_area_theme_choices_v1';
  static const String _debugPresetKey = 'selector_debug_brand_preset_v1';
  static const String _legacyThemeModeKey = 'selector_theme_mode_v1';

  final ValueListenable<bool>? _debugModeListenable;

  bool _loaded = false;
  bool _brandThemeEnabled = false;
  String _selectedArea = '';
  String? _debugPresetId;
  Map<String, AreaThemeChoice> _areaThemeChoices =
      <String, AreaThemeChoice>{};

  bool get loaded => _loaded;
  bool get brandThemeEnabled => _brandThemeEnabled;
  String get selectedArea => _selectedArea;
  bool get debugModeEnabled => _debugModeListenable?.value ?? false;
  String? get debugPresetId => _debugPresetId;
  bool get debugPresetStored => _debugPresetId != null;
  bool get debugOverrideAvailable => debugModeEnabled && debugPresetStored;
  bool get debugOverrideApplied =>
      _brandThemeEnabled && debugOverrideAvailable;
  bool get hasDebugOverride => debugOverrideAvailable;
  bool get isDebugOverrideActive => debugOverrideApplied;

  String? get areaRegisteredPresetId =>
      AreaThemeRegistry.registeredPresetIdFor(_selectedArea);
  bool get areaBrandAvailable => areaRegisteredPresetId != null;
  BrandPresetSpec? get areaRegisteredPreset {
    final id = areaRegisteredPresetId;
    if (id == null) return null;
    return presetById(id);
  }

  String get areaDefaultPresetId =>
      AreaThemeRegistry.defaultPresetIdFor(_selectedArea);

  AreaThemeChoice get normalThemeChoice {
    final stored = _areaThemeChoices[_selectedArea];
    if (stored != null) {
      if (stored == AreaThemeChoice.brand && !areaBrandAvailable) {
        return AreaThemeChoice.defaultTheme;
      }
      return stored;
    }
    return areaBrandAvailable
        ? AreaThemeChoice.brand
        : AreaThemeChoice.defaultTheme;
  }

  bool get normalChoiceStored =>
      _selectedArea.isNotEmpty && _areaThemeChoices.containsKey(_selectedArea);

  String? get userOverridePresetId =>
      normalChoiceStored ? normalPresetId : null;
  bool get isAutomatic => !normalChoiceStored;

  String get normalPresetId {
    if (normalThemeChoice == AreaThemeChoice.brand) {
      return areaRegisteredPresetId ?? kDefaultBrandPresetId;
    }
    return kDefaultBrandPresetId;
  }

  BrandPresetSpec get normalEffectivePreset => presetById(normalPresetId);
  String get requestedPresetId =>
      hasDebugOverride ? _debugPresetId! : normalPresetId;
  BrandPresetSpec get requestedPreset => presetById(requestedPresetId);
  String get presetId =>
      _brandThemeEnabled ? requestedPresetId : kDefaultBrandPresetId;
  BrandPresetSpec get effectivePreset => presetById(presetId);
  BrandPresetSpec get areaDefaultPreset => presetById(areaDefaultPresetId);

  Future<void> load() async {
    _brandThemeEnabled = false;
    final prefs = await SharedPreferences.getInstance();
    final storedVersion = prefs.getInt(_schemaVersionKey) ?? 0;
    final hadAreaOverrides = prefs.containsKey(_areaOverridesKey);
    final hadLegacyThemeMode = prefs.containsKey(_legacyThemeModeKey);

    _areaThemeChoices = _decodeAreaThemeChoices(
      prefs.getString(_areaThemeChoicesKey),
    );
    await _persistAreaThemeChoices(prefs);

    var storedDebugPreset = prefs.getString(_debugPresetKey)?.trim();
    final debugPresetMigrated =
        storedVersion < 4 && storedDebugPreset == kSamsungBonprimeBrandPresetId;
    if (debugPresetMigrated) {
      storedDebugPreset = kNamyangjuPrimeBrandPresetId;
      await prefs.setString(
        _debugPresetKey,
        kNamyangjuPrimeBrandPresetId,
      );
    }

    await prefs.setInt(_schemaVersionKey, _schemaVersion);
    await prefs.remove(_areaOverridesKey);
    await prefs.remove(_legacyThemeModeKey);

    if (storedVersion != _schemaVersion ||
        hadAreaOverrides ||
        hadLegacyThemeMode ||
        debugPresetMigrated) {
      ThemeDebugTrace.record(
        'theme_schema_migrated',
        source: 'theme_prefs_controller',
        details: <String, Object?>{
          'fromVersion': storedVersion,
          'toVersion': _schemaVersion,
          'areaOverridesRemoved': hadAreaOverrides,
          'legacyThemeModeRemoved': hadLegacyThemeMode,
          'debugPresetMigrated': debugPresetMigrated,
          'debugPresetMigrationFrom': debugPresetMigrated
              ? kSamsungBonprimeBrandPresetId
              : '-',
          'debugPresetMigrationTo': debugPresetMigrated
              ? kNamyangjuPrimeBrandPresetId
              : '-',
          'debugPreset': storedDebugPreset ?? '-',
          'areaThemeChoiceCount': _areaThemeChoices.length,
          'normalEffective': normalPresetId,
        },
      );
    }

    if (storedDebugPreset != null &&
        storedDebugPreset.isNotEmpty &&
        isKnownBrandPresetId(storedDebugPreset)) {
      _debugPresetId = storedDebugPreset;
    } else {
      _debugPresetId = null;
      if (prefs.containsKey(_debugPresetKey)) {
        await prefs.remove(_debugPresetKey);
      }
    }

    _loaded = true;
    await _persistLegacyEffectivePreset(prefs);
    ThemeDebugTrace.record(
      'theme_loaded',
      source: 'theme_prefs_controller',
      details: debugDetails,
    );
    notifyListeners();
  }

  Future<void> syncSelectedArea(
    String selectedArea, {
    required String source,
  }) async {
    final normalized = selectedArea.trim();
    if (_selectedArea == normalized) return;
    final beforeEffective = presetId;
    final beforeNormal = normalPresetId;
    _selectedArea = normalized;
    final afterEffective = presetId;
    final afterNormal = normalPresetId;
    final prefs = await SharedPreferences.getInstance();
    await _persistLegacyEffectivePreset(prefs);
    ThemeDebugTrace.record(
      'selected_area_synced',
      source: source,
      details: <String, Object?>{
        ...debugDetails,
        'beforeNormal': beforeNormal,
        'afterNormal': afterNormal,
        'beforeEffective': beforeEffective,
        'afterEffective': afterEffective,
      },
    );
    notifyListeners();
  }

  Future<void> setAreaThemeChoice(
    AreaThemeChoice choice, {
    required String source,
  }) async {
    final area = _selectedArea.trim();
    if (area.isEmpty) {
      ThemeDebugTrace.record(
        'area_theme_choice_rejected',
        source: source,
        details: <String, Object?>{
          ...debugDetails,
          'requestedChoice': _areaThemeChoiceValue(choice),
          'reason': 'selected_area_empty',
        },
      );
      return;
    }
    if (choice == AreaThemeChoice.brand && !areaBrandAvailable) {
      ThemeDebugTrace.record(
        'area_theme_choice_rejected',
        source: source,
        details: <String, Object?>{
          ...debugDetails,
          'requestedChoice': _areaThemeChoiceValue(choice),
          'reason': 'area_brand_unavailable',
        },
      );
      return;
    }

    final storedBefore = _areaThemeChoices[area];
    if (storedBefore == choice) {
      ThemeDebugTrace.record(
        'area_theme_choice_reaffirmed',
        source: source,
        details: debugDetails,
      );
      return;
    }

    final beforeEffective = presetId;
    final beforeNormal = normalPresetId;
    _areaThemeChoices[area] = choice;
    final prefs = await SharedPreferences.getInstance();
    await _persistAreaThemeChoices(prefs);
    await _persistLegacyEffectivePreset(prefs);
    ThemeDebugTrace.record(
      'area_theme_choice_changed',
      source: source,
      details: <String, Object?>{
        ...debugDetails,
        'beforeChoice': storedBefore == null
            ? 'automatic'
            : _areaThemeChoiceValue(storedBefore),
        'afterChoice': _areaThemeChoiceValue(choice),
        'beforeNormal': beforeNormal,
        'afterNormal': normalPresetId,
        'beforeEffective': beforeEffective,
        'afterEffective': presetId,
      },
    );
    notifyListeners();
  }

  Future<void> setPresetId(
    String id, {
    String source = 'user',
  }) async {
    final normalized = id.trim();
    if (!debugModeEnabled) {
      ThemeDebugTrace.record(
        'manual_preset_rejected',
        source: source,
        details: <String, Object?>{
          ...debugDetails,
          'requested': normalized,
          'reason': 'debug_mode_required',
        },
      );
      return;
    }
    await setDebugPresetId(normalized, source: source);
  }

  Future<void> clearPresetOverride({
    String source = 'user',
  }) async {
    if (!debugModeEnabled) {
      ThemeDebugTrace.record(
        'manual_preset_clear_rejected',
        source: source,
        details: <String, Object?>{
          ...debugDetails,
          'reason': 'debug_mode_required',
        },
      );
      return;
    }
    await clearDebugPreset(source: source);
  }

  Future<void> setDebugPresetId(
    String id, {
    String source = 'debug',
  }) async {
    final normalized = id.trim();
    if (!debugModeEnabled) {
      ThemeDebugTrace.record(
        'debug_override_rejected',
        source: source,
        details: <String, Object?>{
          ...debugDetails,
          'requested': normalized,
          'reason': 'debug_mode_disabled',
        },
      );
      return;
    }
    if (!isKnownBrandPresetId(normalized)) {
      ThemeDebugTrace.record(
        'debug_override_rejected',
        source: source,
        details: <String, Object?>{
          ...debugDetails,
          'requested': normalized,
          'reason': 'unknown_preset',
        },
      );
      return;
    }
    if (_debugPresetId == normalized) return;
    final beforeEffective = presetId;
    final beforeRequested = requestedPresetId;
    _debugPresetId = normalized;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_debugPresetKey, normalized);
    ThemeDebugTrace.record(
      'debug_override_changed',
      source: source,
      details: <String, Object?>{
        ...debugDetails,
        'beforeRequested': beforeRequested,
        'afterRequested': requestedPresetId,
        'beforeEffective': beforeEffective,
        'afterEffective': presetId,
      },
    );
    notifyListeners();
  }

  Future<void> clearDebugPreset({
    String source = 'debug',
  }) async {
    if (!debugModeEnabled) {
      ThemeDebugTrace.record(
        'debug_override_clear_rejected',
        source: source,
        details: <String, Object?>{
          ...debugDetails,
          'reason': 'debug_mode_disabled',
        },
      );
      return;
    }
    if (_debugPresetId == null) return;
    final beforeEffective = presetId;
    final beforeRequested = requestedPresetId;
    _debugPresetId = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_debugPresetKey);
    ThemeDebugTrace.record(
      'debug_override_cleared',
      source: source,
      details: <String, Object?>{
        ...debugDetails,
        'beforeRequested': beforeRequested,
        'afterRequested': requestedPresetId,
        'beforeEffective': beforeEffective,
        'afterEffective': presetId,
      },
    );
    notifyListeners();
  }

  void activateBrandTheme({
    required String source,
  }) {
    if (_brandThemeEnabled) return;
    final beforeEffective = presetId;
    _brandThemeEnabled = true;
    ThemeDebugTrace.record(
      'brand_theme_activated',
      source: source,
      details: <String, Object?>{
        ...debugDetails,
        'beforeEffective': beforeEffective,
        'afterEffective': presetId,
      },
    );
    notifyListeners();
  }

  void suspendBrandTheme({
    required String source,
  }) {
    if (!_brandThemeEnabled) return;
    final beforeEffective = presetId;
    _brandThemeEnabled = false;
    ThemeDebugTrace.record(
      'brand_theme_suspended',
      source: source,
      details: <String, Object?>{
        ...debugDetails,
        'beforeEffective': beforeEffective,
        'afterEffective': presetId,
      },
    );
    notifyListeners();
  }

  ThemeData buildTheme() {
    return buildBrandTheme(effectivePreset);
  }

  Map<String, Object?> get debugDetails {
    final requested = requestedPreset;
    final preset = effectivePreset;
    return <String, Object?>{
      'selectedArea': _selectedArea.isEmpty ? '-' : _selectedArea,
      'areaRegisteredPreset': areaRegisteredPresetId ?? '-',
      'areaBrandAvailable': areaBrandAvailable,
      'areaDefault': areaDefaultPresetId,
      'areaThemeChoice': _areaThemeChoiceValue(normalThemeChoice),
      'areaThemeChoiceStored': normalChoiceStored,
      'areaOverride': userOverridePresetId ?? '-',
      'normalEffective': normalPresetId,
      'brandThemeEnabled': _brandThemeEnabled,
      'debugMode': debugModeEnabled,
      'debugOverride': _debugPresetId ?? '-',
      'debugStored': debugPresetStored,
      'debugAvailable': debugOverrideAvailable,
      'debugActive': debugOverrideApplied,
      'requested': requested.id,
      'requestedBase': colorHex(requested.colors.base),
      'requestedBrand': colorHex(requested.colors.brand),
      'requestedAccent': colorHex(requested.colors.accent),
      'requestedContentRole': requested.colors.contentRole.name,
      'requestedContent': colorHex(requested.colors.content),
      'effective': preset.id,
      'base': colorHex(preset.colors.base),
      'brand': colorHex(preset.colors.brand),
      'accent': colorHex(preset.colors.accent),
      'contentRole': preset.colors.contentRole.name,
      'content': colorHex(preset.colors.content),
      'normalAutomatic': isAutomatic,
    };
  }

  Map<String, AreaThemeChoice> _decodeAreaThemeChoices(String? raw) {
    if (raw == null || raw.trim().isEmpty) {
      return <String, AreaThemeChoice>{};
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return <String, AreaThemeChoice>{};
      final result = <String, AreaThemeChoice>{};
      for (final entry in decoded.entries) {
        final area = entry.key.toString().trim();
        final value = entry.value?.toString().trim() ?? '';
        if (area.isEmpty) continue;
        final choice = _parseAreaThemeChoice(value);
        if (choice == null) continue;
        if (choice == AreaThemeChoice.brand &&
            !AreaThemeRegistry.hasBrandFor(area)) {
          continue;
        }
        result[area] = choice;
      }
      return result;
    } catch (_) {
      return <String, AreaThemeChoice>{};
    }
  }

  AreaThemeChoice? _parseAreaThemeChoice(String value) {
    if (value == 'default') return AreaThemeChoice.defaultTheme;
    if (value == 'brand') return AreaThemeChoice.brand;
    return null;
  }

  String _areaThemeChoiceValue(AreaThemeChoice choice) {
    return choice == AreaThemeChoice.brand ? 'brand' : 'default';
  }

  Future<void> _persistAreaThemeChoices(SharedPreferences prefs) async {
    if (_areaThemeChoices.isEmpty) {
      await prefs.remove(_areaThemeChoicesKey);
      return;
    }
    final keys = _areaThemeChoices.keys.toList(growable: false)..sort();
    final encoded = <String, String>{
      for (final key in keys)
        key: _areaThemeChoiceValue(_areaThemeChoices[key]!),
    };
    await prefs.setString(_areaThemeChoicesKey, jsonEncode(encoded));
  }

  Future<void> _persistLegacyEffectivePreset(SharedPreferences prefs) async {
    await prefs.setString(kBrandPresetKey, normalPresetId);
    await prefs.remove(_legacyThemeModeKey);
  }

  void _handleDebugModeChanged() {
    ThemeDebugTrace.record(
      'debug_mode_changed',
      source: 'theme_prefs_controller',
      details: debugDetails,
    );
    notifyListeners();
  }

  @override
  void dispose() {
    _debugModeListenable?.removeListener(_handleDebugModeChanged);
    super.dispose();
  }
}
