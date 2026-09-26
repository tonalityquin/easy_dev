import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'area_theme_registry.dart';
import 'brand_theme.dart';
import 'theme_debug_trace.dart';

class ThemePrefsController extends ChangeNotifier {
  ThemePrefsController();

  static const int _schemaVersion = 2;
  static const String _schemaVersionKey = 'selector_theme_schema_version';
  static const String _areaOverridesKey = 'selector_area_theme_overrides_v1';
  static const String _legacyThemeModeKey = 'selector_theme_mode_v1';

  bool _loaded = false;
  String _selectedArea = '';
  Map<String, String> _areaOverrides = <String, String>{};

  bool get loaded => _loaded;
  String get selectedArea => _selectedArea;
  String get areaDefaultPresetId =>
      AreaThemeRegistry.defaultPresetIdFor(_selectedArea);
  String? get userOverridePresetId {
    if (_selectedArea.isEmpty) return null;
    final value = _areaOverrides[_selectedArea];
    if (value == null || !isKnownBrandPresetId(value)) return null;
    return value;
  }

  bool get isAutomatic => userOverridePresetId == null;
  String get presetId => userOverridePresetId ?? areaDefaultPresetId;
  BrandPresetSpec get effectivePreset => presetById(presetId);
  BrandPresetSpec get areaDefaultPreset => presetById(areaDefaultPresetId);

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final storedVersion = prefs.getInt(_schemaVersionKey) ?? 0;
    if (storedVersion != _schemaVersion) {
      _areaOverrides = <String, String>{};
      await prefs.setInt(_schemaVersionKey, _schemaVersion);
      await prefs.setString(_areaOverridesKey, jsonEncode(_areaOverrides));
      await prefs.setString(kBrandPresetKey, kDefaultBrandPresetId);
      await prefs.remove(_legacyThemeModeKey);
      ThemeDebugTrace.record(
        'theme_schema_migrated',
        source: 'theme_prefs_controller',
        details: const <String, Object?>{
          'effective': kDefaultBrandPresetId,
        },
      );
    } else {
      _areaOverrides = _decodeOverrides(prefs.getString(_areaOverridesKey));
      await _persistOverrides(prefs);
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
    final before = presetId;
    _selectedArea = normalized;
    final after = presetId;
    final prefs = await SharedPreferences.getInstance();
    await _persistLegacyEffectivePreset(prefs);
    ThemeDebugTrace.record(
      'selected_area_synced',
      source: source,
      details: <String, Object?>{
        ...debugDetails,
        'beforeEffective': before,
        'afterEffective': after,
      },
    );
    notifyListeners();
  }

  Future<void> setPresetId(
    String id, {
    String source = 'user',
  }) async {
    final normalized = id.trim();
    if (!isKnownBrandPresetId(normalized)) {
      ThemeDebugTrace.record(
        'user_override_rejected',
        source: source,
        details: <String, Object?>{
          ...debugDetails,
          'requested': normalized,
        },
      );
      return;
    }
    if (_selectedArea.isEmpty) {
      ThemeDebugTrace.record(
        'user_override_rejected',
        source: source,
        details: <String, Object?>{
          ...debugDetails,
          'requested': normalized,
          'reason': 'selected_area_empty',
        },
      );
      return;
    }
    final before = presetId;
    if (_areaOverrides[_selectedArea] == normalized) return;
    _areaOverrides[_selectedArea] = normalized;
    final prefs = await SharedPreferences.getInstance();
    await _persistOverrides(prefs);
    await _persistLegacyEffectivePreset(prefs);
    ThemeDebugTrace.record(
      'user_override_changed',
      source: source,
      details: <String, Object?>{
        ...debugDetails,
        'beforeEffective': before,
        'afterEffective': presetId,
      },
    );
    notifyListeners();
  }

  Future<void> clearPresetOverride({
    String source = 'user',
  }) async {
    if (_selectedArea.isEmpty) return;
    if (!_areaOverrides.containsKey(_selectedArea)) return;
    final before = presetId;
    _areaOverrides.remove(_selectedArea);
    final prefs = await SharedPreferences.getInstance();
    await _persistOverrides(prefs);
    await _persistLegacyEffectivePreset(prefs);
    ThemeDebugTrace.record(
      'user_override_cleared',
      source: source,
      details: <String, Object?>{
        ...debugDetails,
        'beforeEffective': before,
        'afterEffective': presetId,
      },
    );
    notifyListeners();
  }

  ThemeData buildTheme() {
    return buildBrandTheme(effectivePreset);
  }

  Map<String, Object?> get debugDetails {
    final preset = effectivePreset;
    return <String, Object?>{
      'selectedArea': _selectedArea.isEmpty ? '-' : _selectedArea,
      'areaDefault': areaDefaultPresetId,
      'override': userOverridePresetId ?? '-',
      'effective': preset.id,
      'base': colorHex(preset.colors.base),
      'brand': colorHex(preset.colors.brand),
      'content': colorHex(preset.colors.content),
      'automatic': isAutomatic,
    };
  }

  Map<String, String> _decodeOverrides(String? raw) {
    if (raw == null || raw.trim().isEmpty) return <String, String>{};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return <String, String>{};
      final result = <String, String>{};
      for (final entry in decoded.entries) {
        final area = entry.key.toString().trim();
        final preset = entry.value.toString().trim();
        if (area.isEmpty || !isKnownBrandPresetId(preset)) continue;
        result[area] = preset;
      }
      return result;
    } catch (_) {
      return <String, String>{};
    }
  }

  Future<void> _persistOverrides(SharedPreferences prefs) async {
    final sortedKeys = _areaOverrides.keys.toList(growable: false)..sort();
    final normalized = <String, String>{
      for (final key in sortedKeys) key: _areaOverrides[key]!,
    };
    _areaOverrides = normalized;
    await prefs.setString(_areaOverridesKey, jsonEncode(normalized));
  }

  Future<void> _persistLegacyEffectivePreset(SharedPreferences prefs) async {
    await prefs.setString(kBrandPresetKey, presetId);
    await prefs.remove(_legacyThemeModeKey);
  }
}
