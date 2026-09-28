import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'area_theme_registry.dart';
import 'brand_theme.dart';
import 'theme_debug_trace.dart';

class ThemePrefsController extends ChangeNotifier {
  ThemePrefsController({ValueListenable<bool>? debugModeListenable})
      : _debugModeListenable = debugModeListenable {
    _debugModeListenable?.addListener(_handleDebugModeChanged);
  }

  static const int _schemaVersion = 4;
  static const String _schemaVersionKey = 'selector_theme_schema_version';
  static const String _areaOverridesKey = 'selector_area_theme_overrides_v1';
  static const String _debugPresetKey = 'selector_debug_brand_preset_v1';
  static const String _legacyThemeModeKey = 'selector_theme_mode_v1';

  final ValueListenable<bool>? _debugModeListenable;

  bool _loaded = false;
  bool _brandThemeEnabled = false;
  String _selectedArea = '';
  String? _debugPresetId;

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

  String get areaDefaultPresetId =>
      AreaThemeRegistry.defaultPresetIdFor(_selectedArea);

  String? get userOverridePresetId => null;
  bool get isAutomatic => true;
  String get normalPresetId => areaDefaultPresetId;
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
      'areaDefault': areaDefaultPresetId,
      'areaOverride': '-',
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
      'requestedAccent': colorHex(requested.colors.resolvedAccent),
      'requestedContent': colorHex(requested.colors.content),
      'effective': preset.id,
      'base': colorHex(preset.colors.base),
      'brand': colorHex(preset.colors.brand),
      'accent': colorHex(preset.colors.resolvedAccent),
      'content': colorHex(preset.colors.content),
      'normalAutomatic': true,
    };
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
