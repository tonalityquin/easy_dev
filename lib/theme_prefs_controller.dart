import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'selector_hubs_package/brand_theme.dart';
import 'theme.dart';

/// 앱 전역 테마(색 패키지 + 테마 모드)를 SharedPreferences에서 로드/저장하고,
/// MaterialApp의 theme/darkTheme/themeMode를 제공하는 컨트롤러.
class ThemePrefsController extends ChangeNotifier {
  ThemePrefsController();

  bool _loaded = false;
  bool get loaded => _loaded;

  String _presetId = 'system'; // kBrandPresetKey
  String get presetId => _presetId;

  String _themeModeId = 'system'; // kThemeModeKey: system|light|dark
  String get themeModeId => _themeModeId;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _presetId = (prefs.getString(kBrandPresetKey) ?? 'system').trim();
    if (_presetId.isEmpty) _presetId = 'system';

    _themeModeId = (prefs.getString(kThemeModeKey) ?? 'system').trim();
    if (_themeModeId.isEmpty) _themeModeId = 'system';

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
      default:
        return ThemeMode.system;
    }
  }

  Future<void> setPresetId(String id) async {
    if (id.trim().isEmpty) id = 'system';
    if (_presetId == id) return;
    _presetId = id;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(kBrandPresetKey, _presetId);

    notifyListeners();
  }

  Future<void> setThemeModeId(String id) async {
    if (id.trim().isEmpty) id = 'system';
    if (_themeModeId == id) return;
    _themeModeId = id;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(kThemeModeKey, _themeModeId);

    notifyListeners();
  }

  /// 라이트 테마(컨셉 scheme)
  ThemeData buildLightTheme() {
    return _buildThemeForBrightness(Brightness.light);
  }

  /// 다크 테마(컨셉 scheme)
  ThemeData buildDarkTheme() {
    return _buildThemeForBrightness(Brightness.dark);
  }

  ThemeData _buildThemeForBrightness(Brightness brightness) {
    // ✅ 기존 appTheme의 textTheme를 유지하여 전체 타이포 일관성 확보
    final base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      textTheme: appTheme.textTheme,
    );

    final preset = presetById(_presetId);
    final accent =
    (preset.id == 'system' || preset.accent == null) ? base.colorScheme.primary : preset.accent!;

    final scheme = buildConceptScheme(
      brightness: brightness,
      accent: accent,
    );

    return base.copyWith(
      colorScheme: scheme,
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
}
