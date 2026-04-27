import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'brand_theme.dart';

class ThemePrefsController extends ChangeNotifier {
  ThemePrefsController();

  static const String _kDefaultPresetId = 'soft_linen';
  static const String _kDefaultThemeModeId = 'independent';

  bool _loaded = false;

  bool get loaded => _loaded;

  String _presetId = _kDefaultPresetId;

  String get presetId => _presetId;

  String _themeModeId = _kDefaultThemeModeId;

  String get themeModeId => _themeModeId;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();

    final hasPresetKey = prefs.containsKey(kBrandPresetKey);
    final hasModeKey = prefs.containsKey(kThemeModeKey);
    final isFirstRun = !hasPresetKey && !hasModeKey;

    _presetId = (prefs.getString(kBrandPresetKey) ?? _kDefaultPresetId).trim();
    if (_presetId.isEmpty) _presetId = _kDefaultPresetId;

    _themeModeId =
        (prefs.getString(kThemeModeKey) ?? _kDefaultThemeModeId).trim();
    if (_themeModeId.isEmpty) _themeModeId = _kDefaultThemeModeId;

    await _ensureConsistency(persist: isFirstRun);

    _loaded = true;
    notifyListeners();
  }

  ThemeMode get themeMode {
    switch (_themeModeId) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      case 'system':
        return ThemeMode.system;
      case 'independent':
        return ThemeMode.light;
      default:
        return ThemeMode.system;
    }
  }

  Future<void> setPresetId(String id) async {
    id = id.trim();
    if (id.isEmpty) id = _kDefaultPresetId;
    if (_presetId == id) return;

    _presetId = id;

    await _ensureConsistency(persist: true);

    notifyListeners();
  }

  Future<void> setThemeModeId(String id) async {
    id = id.trim();
    if (id.isEmpty) id = _kDefaultThemeModeId;
    if (_themeModeId == id) return;

    _themeModeId = id;

    await _ensureConsistency(persist: true);

    notifyListeners();
  }

  ThemeData buildLightTheme() {
    if (_themeModeId == 'independent') {
      return _buildIndependentTheme();
    }
    return _buildConceptThemeForBrightness(Brightness.light);
  }

  ThemeData buildDarkTheme() {
    if (_themeModeId == 'independent') {
      return _buildIndependentTheme();
    }
    return _buildConceptThemeForBrightness(Brightness.dark);
  }

  Future<void> _ensureConsistency({required bool persist}) async {
    const validModes = {'system', 'light', 'dark', 'independent'};
    if (!validModes.contains(_themeModeId)) {
      _themeModeId = _kDefaultThemeModeId;
    }

    final normalizedPreset = presetById(_presetId);
    _presetId = normalizedPreset.id;

    if (_themeModeId == 'independent') {
      final cur = presetById(_presetId);
      if (cur.independentTokens == null) {
        final candidates = brandPresetsForThemeMode('independent');
        if (candidates.isNotEmpty) {
          final preferred = candidates.firstWhere(
            (p) => p.id == _kDefaultPresetId,
            orElse: () => candidates.first,
          );
          _presetId = preferred.id;
        } else {
          _presetId = 'system';
          _themeModeId = 'system';
        }
      }
    } else {
      final cur = presetById(_presetId);
      if (cur.independentTokens != null) {
        _presetId = 'system';
      }
    }

    if (!persist) return;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(kBrandPresetKey, _presetId);
    await prefs.setString(kThemeModeKey, _themeModeId);
  }

  TextTheme _seedTextTheme(ThemeData base) {
    final t = base.textTheme;

    return t.copyWith(
      titleMedium:
          (t.titleMedium ?? const TextStyle()).copyWith(fontSize: 16.0),
      bodyLarge: (t.bodyLarge ?? const TextStyle()).copyWith(fontSize: 18.0),
      bodyMedium: (t.bodyMedium ?? const TextStyle()).copyWith(fontSize: 16.0),
    );
  }

  TextTheme _applySchemeTextColors(TextTheme textTheme, ColorScheme scheme) {
    return textTheme.apply(
      bodyColor: scheme.onSurface,
      displayColor: scheme.onSurface,
    );
  }

  ThemeData _buildConceptThemeForBrightness(Brightness brightness) {
    final base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
    );

    final preset = presetById(_presetId);

    final accent = (preset.id == 'system' || preset.accent == null)
        ? base.colorScheme.primary
        : preset.accent!;

    final scheme = buildConceptScheme(
      brightness: brightness,
      accent: accent,
    );

    final textTheme = _applySchemeTextColors(_seedTextTheme(base), scheme);

    return base.copyWith(
      colorScheme: scheme,
      textTheme: textTheme,
      scaffoldBackgroundColor: scheme.surface,
      appBarTheme: base.appBarTheme.copyWith(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        surfaceTintColor: Colors.transparent,
      ),
      cardTheme: base.cardTheme.copyWith(
        color: scheme.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
      ),
      bottomSheetTheme: base.bottomSheetTheme.copyWith(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
      ),
      dividerTheme: base.dividerTheme.copyWith(
        color: scheme.outlineVariant,
        thickness: 1,
        space: 1,
      ),
    );
  }

  ThemeData _buildIndependentTheme() {
    final preset = presetById(_presetId);
    final t = preset.independentTokens;

    if (t == null) {
      return _buildConceptThemeForBrightness(Brightness.light);
    }

    final base = ThemeData(
      useMaterial3: true,
      brightness: t.brightness,
    );

    final themed = applyIndependentTheme(base, preset.id);

    final scheme = themed.colorScheme;
    final textTheme = _applySchemeTextColors(_seedTextTheme(themed), scheme);

    return themed.copyWith(
      textTheme: textTheme,
    );
  }
}
