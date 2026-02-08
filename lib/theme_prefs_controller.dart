import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'selector_hubs_package/brand_theme.dart';
import 'theme.dart';

/// 앱 전역 테마(색 패키지 + 테마 모드)를 SharedPreferences에서 로드/저장하고,
/// MaterialApp의 theme/darkTheme/themeMode를 제공하는 컨트롤러.
///
/// ✅ 지원 모드:
/// - system / light / dark / independent
///
/// ✅ independent(독립) 모드 특징:
/// - 프리셋이 배경/글자색/하이라이트 글자색/brightness까지 “자체 결정”
/// - MaterialApp의 themeMode는 강제로 light를 반환(ThemeMode enum에 independent가 없기 때문)
///   대신 buildLightTheme/buildDarkTheme가 동일한 독립 ThemeData를 반환하도록 구성
class ThemePrefsController extends ChangeNotifier {
  ThemePrefsController();

  // ✅ 최초 실행 기본값을 독립 Soft Linen으로 고정
  static const String _kDefaultPresetId = 'soft_linen';
  static const String _kDefaultThemeModeId = 'independent';

  bool _loaded = false;
  bool get loaded => _loaded;

  // ✅ (변경) 최초 프레임에서도 Soft Linen이 보이도록 필드 초기값 자체를 변경
  String _presetId = _kDefaultPresetId; // kBrandPresetKey
  String get presetId => _presetId;

  // ✅ (변경) 최초 프레임에서도 독립 모드가 적용되도록 초기값 변경
  String _themeModeId = _kDefaultThemeModeId; // kThemeModeKey: system|light|dark|independent
  String get themeModeId => _themeModeId;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();

    // ✅ (신규) “최초 실행” 판별: 두 키 모두 없을 때만 first-run로 간주
    final hasPresetKey = prefs.containsKey(kBrandPresetKey);
    final hasModeKey = prefs.containsKey(kThemeModeKey);
    final isFirstRun = !hasPresetKey && !hasModeKey;

    // ✅ (변경) prefs에 값이 없으면 Soft Linen/Independent로 폴백
    _presetId = (prefs.getString(kBrandPresetKey) ?? _kDefaultPresetId).trim();
    if (_presetId.isEmpty) _presetId = _kDefaultPresetId;

    _themeModeId = (prefs.getString(kThemeModeKey) ?? _kDefaultThemeModeId).trim();
    if (_themeModeId.isEmpty) _themeModeId = _kDefaultThemeModeId;

    // ✅ 저장된 조합이 모드 규칙에 맞는지 교정
    // ✅ (변경) 최초 실행이면 교정된 기본값을 prefs에 저장하여 “재실행해도 유지”
    await _ensureConsistency(persist: isFirstRun);

    _loaded = true;
    notifyListeners();
  }

  /// MaterialApp이 이해 가능한 ThemeMode로 매핑
  ///
  /// ✅ independent는 ThemeMode enum에 없으므로, ThemeMode.light로 강제하고
  /// ThemeData 자체를 독립 테마로 만들어 “항상 theme(=lightTheme)”가 쓰이게 합니다.
  ThemeMode get themeMode {
    switch (_themeModeId) {
      case 'light':
        return ThemeMode.light;
      case 'dark':
        return ThemeMode.dark;
      case 'system':
        return ThemeMode.system;
      case 'independent':
        return ThemeMode.light; // ✅ 강제
      default:
        return ThemeMode.system;
    }
  }

  Future<void> setPresetId(String id) async {
    id = id.trim();
    if (id.isEmpty) id = _kDefaultPresetId;
    if (_presetId == id) return;

    _presetId = id;

    // ✅ 모드-프리셋 조합 교정(필요 시 presetId가 바뀔 수도 있음)
    // ✅ persist=true → 사용자가 바꾼 값은 prefs에 저장되어 재실행 후에도 유지
    await _ensureConsistency(persist: true);

    notifyListeners();
  }

  Future<void> setThemeModeId(String id) async {
    id = id.trim();
    if (id.isEmpty) id = _kDefaultThemeModeId;
    if (_themeModeId == id) return;

    _themeModeId = id;

    // ✅ 모드-프리셋 조합 교정(필요 시 presetId가 바뀔 수도 있음)
    // ✅ persist=true → 사용자가 바꾼 값은 prefs에 저장되어 재실행 후에도 유지
    await _ensureConsistency(persist: true);

    notifyListeners();
  }

  /// 라이트 테마
  ThemeData buildLightTheme() {
    // ✅ 독립 모드면 “프리셋이 밝기까지 결정”하므로 별도 빌더 사용
    if (_themeModeId == 'independent') {
      return _buildIndependentTheme();
    }
    return _buildConceptThemeForBrightness(Brightness.light);
  }

  /// 다크 테마
  ThemeData buildDarkTheme() {
    // ✅ 독립 모드면 MaterialApp이 darkTheme를 쓰지 않게(ThemeMode.light 강제)
    // 해두었지만, 혹시 모를 상황에 대비해 동일한 독립 테마를 반환
    if (_themeModeId == 'independent') {
      return _buildIndependentTheme();
    }
    return _buildConceptThemeForBrightness(Brightness.dark);
  }

  // ─────────────────────────────────────────────────────────────
  // 내부 구현

  /// ✅ 저장 조합 일관성 보장
  /// - independent 모드: 독립 프리셋(토큰 있는 것)만 허용
  /// - 그 외 모드: 일반 프리셋(토큰 없는 것)만 허용
  ///
  /// persist=true면 SharedPreferences까지 반영
  Future<void> _ensureConsistency({required bool persist}) async {
    // themeModeId 정규화
    const validModes = {'system', 'light', 'dark', 'independent'};
    if (!validModes.contains(_themeModeId)) {
      _themeModeId = _kDefaultThemeModeId;
    }

    // presetId 정규화(존재하지 않는 id면 presetById가 system으로 떨어짐)
    final normalizedPreset = presetById(_presetId);
    _presetId = normalizedPreset.id;

    if (_themeModeId == 'independent') {
      // 독립 모드인데 독립 프리셋이 아니면 → Soft Linen 우선으로 교정
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
          // 독립 프리셋이 아예 없다면 안전하게 system으로 폴백
          _presetId = 'system';
          _themeModeId = 'system';
        }
      }
    } else {
      // system/light/dark인데 독립 프리셋이면 → system으로 교정
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

  ThemeData _buildConceptThemeForBrightness(Brightness brightness) {
    // ✅ 기존 appTheme의 textTheme를 유지하여 전체 타이포 일관성 확보
    final base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      textTheme: appTheme.textTheme,
    );

    final preset = presetById(_presetId);
    final accent = (preset.id == 'system' || preset.accent == null) ? base.colorScheme.primary : preset.accent!;

    final scheme = buildConceptScheme(
      brightness: brightness,
      accent: accent,
    );

    return base.copyWith(
      colorScheme: scheme,

      // (기존 유지) 컨셉 모드는 표면을 기본 배경으로
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
    // ✅ 독립 모드는 프리셋 토큰 기반 ThemeData를 생성
    final preset = presetById(_presetId);
    final t = preset.independentTokens;

    // 방어: 혹시 독립 모드인데 토큰이 없으면 컨셉(light)로 폴백
    if (t == null) {
      return _buildConceptThemeForBrightness(Brightness.light);
    }

    // ✅ textTheme 유지 + 프리셋이 밝기 결정
    final base = ThemeData(
      useMaterial3: true,
      brightness: t.brightness,
      textTheme: appTheme.textTheme,
    );

    // brand_theme.dart의 applyIndependentTheme가
    // - brightness 강제
    // - colorScheme 주입
    // - scaffoldBackgroundColor를 scheme.background로 반영
    // 등을 처리
    return applyIndependentTheme(base, preset.id);
  }
}
