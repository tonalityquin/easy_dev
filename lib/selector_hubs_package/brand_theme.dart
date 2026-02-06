import 'package:flutter/material.dart';

/// ✅ 컬러 프리셋 저장 키
const String kBrandPresetKey = 'selector_brand_preset_v1';

/// ✅ 테마 모드 저장 키 (system/light/dark/independent)
const String kThemeModeKey = 'selector_theme_mode_v1';

@immutable
class IndependentBrandTokens {
  const IndependentBrandTokens({
    required this.brightness,
    required this.background,
    required this.highlightText,
    required this.bodyText,
  });

  /// 독립 테마는 프리셋이 자체적으로 밝기를 결정합니다.
  final Brightness brightness;

  /// “배경색” (요구사항 그대로)
  final Color background;

  /// “하이라이트 글자색” (요구사항 그대로)
  final Color highlightText;

  /// “나머지 글자색” (요구사항 그대로)
  final Color bodyText;
}

@immutable
class BrandPresetSpec {
  const BrandPresetSpec({
    required this.id,
    required this.label,
    required this.accent,
    required this.preview,
    this.independentTokens,
  });

  final String id;
  final String label;

  /// 컨셉(포인트) 색. system은 null.
  final Color? accent;

  /// UI 프리뷰(3색 점)
  final List<Color> preview;

  /// ✅ 독립 테마 전용 토큰 (null이면 일반 프리셋)
  final IndependentBrandTokens? independentTokens;

  bool get isIndependentOnly => independentTokens != null;
}

List<BrandPresetSpec> brandPresets() {
  return const [
    // ─────────────────────────────────────────────────────────────
    // 일반(컨셉) 프리셋
    BrandPresetSpec(
      id: 'system',
      label: '시스템',
      accent: null,
      preview: [Color(0xFF9E9E9E), Color(0xFFBDBDBD), Color(0xFFE0E0E0)],
    ),
    BrandPresetSpec(
      id: 'black_yellow',
      label: 'Black + Yellow',
      accent: Color(0xFFFFC107),
      preview: [Color(0xFF0F1115), Color(0xFFFFC107), Color(0xFFFFFFFF)],
    ),
    BrandPresetSpec(
      id: 'navy_cyan',
      label: 'Navy + Cyan',
      accent: Color(0xFF00BCD4),
      preview: [Color(0xFF0B1220), Color(0xFF00BCD4), Color(0xFFF5F7FA)],
    ),
    BrandPresetSpec(
      id: 'charcoal_mint',
      label: 'Charcoal + Mint',
      accent: Color(0xFF2DD4BF),
      preview: [Color(0xFF1A1D21), Color(0xFF2DD4BF), Color(0xFFF8FAFC)],
    ),
    BrandPresetSpec(
      id: 'slate_orange',
      label: 'Slate + Orange',
      accent: Color(0xFFF97316),
      preview: [Color(0xFF111827), Color(0xFFF97316), Color(0xFFF9FAFB)],
    ),
    BrandPresetSpec(
      id: 'indigo_lime',
      label: 'Indigo + Lime',
      accent: Color(0xFF4F46E5),
      preview: [Color(0xFF111827), Color(0xFF4F46E5), Color(0xFFA3E635)],
    ),

    // ─────────────────────────────────────────────────────────────
    // ✅ 독립 프리셋(요구사항 반영)
    // 1) KB
    // 배경 RGB(96,89,78)   => 0xFF60594E
    // 하이라이트 글자 RGB(255,188,0) => 0xFFFFBC00
    // 나머지 글자 = white
    BrandPresetSpec(
      id: 'kb',
      label: 'KB',
      accent: Color(0xFFFFBC00),
      preview: [
        Color(0xFF60594E), // bg
        Color(0xFFFFBC00), // highlight text
        Color(0xFFFFFFFF), // body text
      ],
      independentTokens: IndependentBrandTokens(
        brightness: Brightness.dark,
        background: Color(0xFF60594E),
        highlightText: Color(0xFFFFBC00),
        bodyText: Color(0xFFFFFFFF),
      ),
    ),

    // 2) OS SSBP
    // 배경 = white
    // 하이라이트 글자 RGB(34,71,109) => 0xFF22476D
    // 나머지 글자 RGB(146,195,218)   => 0xFF92C3DA
    BrandPresetSpec(
      id: 'os_ssbp',
      label: 'OS SSBP',
      accent: Color(0xFF22476D),
      preview: [
        Color(0xFFFFFFFF), // bg
        Color(0xFF22476D), // highlight text
        Color(0xFF92C3DA), // body text
      ],
      independentTokens: IndependentBrandTokens(
        brightness: Brightness.light,
        background: Color(0xFFFFFFFF),
        highlightText: Color(0xFF22476D),
        bodyText: Color(0xFF92C3DA),
      ),
    ),

    // ─────────────────────────────────────────────────────────────
    // ✅ 추가 독립 프리셋 3) Cozy Cocoa (다크, 순백 미사용)
    // 배경: #1C1916
    // 하이라이트 글자: #F2B866
    // 나머지 글자: #E7E1D9
    BrandPresetSpec(
      id: 'cozy_cocoa',
      label: 'Cozy Cocoa',
      accent: Color(0xFFF2B866),
      preview: [
        Color(0xFF1C1916), // bg
        Color(0xFFF2B866), // highlight text
        Color(0xFFE7E1D9), // body text (NOT pure white)
      ],
      independentTokens: IndependentBrandTokens(
        brightness: Brightness.dark,
        background: Color(0xFF1C1916),
        highlightText: Color(0xFFF2B866),
        bodyText: Color(0xFFE7E1D9),
      ),
    ),

    // ✅ 추가 독립 프리셋 4) Soft Linen (라이트, 순백 미사용)
    // 배경: #F2EDE3 (크림/리넨 톤 — pure white 아님)
    // 하이라이트 글자: #2F6F6D (뮤트 틸)
    // 나머지 글자: #2C2A26 (웜 차콜)
    BrandPresetSpec(
      id: 'soft_linen',
      label: 'Soft Linen',
      accent: Color(0xFF2F6F6D),
      preview: [
        Color(0xFFF2EDE3), // bg (NOT pure white)
        Color(0xFF2F6F6D), // highlight text
        Color(0xFF2C2A26), // body text
      ],
      independentTokens: IndependentBrandTokens(
        brightness: Brightness.light,
        background: Color(0xFFF2EDE3),
        highlightText: Color(0xFF2F6F6D),
        bodyText: Color(0xFF2C2A26),
      ),
    ),
  ];
}

List<BrandPresetSpec> brandPresetsForThemeMode(String themeModeId) {
  final all = brandPresets();
  if (themeModeId == 'independent') {
    return all.where((p) => p.independentTokens != null).toList(growable: false);
  }
  // system/light/dark에서는 독립 프리셋 제외(혼선 방지)
  return all.where((p) => p.independentTokens == null).toList(growable: false);
}

BrandPresetSpec presetById(String id) {
  return brandPresets().firstWhere(
        (p) => p.id == id,
    orElse: () => brandPresets().first,
  );
}

@immutable
class ThemeModeSpec {
  const ThemeModeSpec({
    required this.id,
    required this.label,
    required this.icon,
  });

  final String id; // system | light | dark | independent
  final String label;
  final IconData icon;
}

List<ThemeModeSpec> themeModeSpecs() {
  return const [
    ThemeModeSpec(id: 'system', label: '시스템', icon: Icons.brightness_auto_rounded),
    ThemeModeSpec(id: 'light', label: '라이트', icon: Icons.light_mode_rounded),
    ThemeModeSpec(id: 'dark', label: '다크', icon: Icons.dark_mode_rounded),
    ThemeModeSpec(id: 'independent', label: '독립', icon: Icons.palette_rounded),
  ];
}

/// system/light/dark -> Brightness 결정
/// independent는 프리셋 토큰이 brightness를 결정하므로, 일반적으로 이 함수를 사용하지 않습니다.
Brightness resolveBrightness(String themeModeId, Brightness systemBrightness) {
  switch (themeModeId) {
    case 'light':
      return Brightness.light;
    case 'dark':
      return Brightness.dark;
    case 'system':
      return systemBrightness;
    case 'independent':
    default:
      return systemBrightness;
  }
}

/// ThemeData의 brightness를 강제(텍스트/아이콘/상태바 판단 등에 사용)
ThemeData withBrightness(ThemeData base, Brightness brightness) {
  final cs = base.colorScheme;
  return base.copyWith(
    brightness: brightness,
    colorScheme: cs.copyWith(brightness: brightness),
  );
}

Brightness _brightnessFor(Color c) => ThemeData.estimateBrightnessForColor(c);

Color _onColor(Color bg) => _brightnessFor(bg) == Brightness.dark ? Colors.white : Colors.black;

Color _lerp(Color a, Color b, double t) => Color.lerp(a, b, t)!;

/// ✅ "컨셉" ColorScheme: 표면(surfaces)은 중립(neutral)로 고정.
/// - primary만 accent로.
/// - surfaceTint는 투명(필터 방지).
ColorScheme buildConceptScheme({
  required Brightness brightness,
  required Color accent,
}) {
  final bool dark = brightness == Brightness.dark;

  // Neutral foundation (필터 방지 핵심: 표면을 중립으로 고정)
  final Color background = dark ? const Color(0xFF0B0F14) : const Color(0xFFF8FAFC);
  final Color surface = dark ? const Color(0xFF0F172A) : const Color(0xFFFFFFFF);
  final Color surfaceVariant = dark ? const Color(0xFF1F2937) : const Color(0xFFE2E8F0);
  final Color onSurface = dark ? const Color(0xFFE5E7EB) : const Color(0xFF0F172A);
  final Color onSurfaceVariant = dark ? const Color(0xFFCBD5E1) : const Color(0xFF334155);

  final Color outline = dark ? const Color(0xFF334155) : const Color(0xFFCBD5E1);
  final Color outlineVariant = dark ? const Color(0xFF1F2937) : const Color(0xFFE2E8F0);

  final Color surfaceContainerLow = dark ? const Color(0xFF111827) : const Color(0xFFF1F5F9);

  // Accent: primary only
  final Color primary = accent;
  final Color onPrimary = _onColor(primary);

  // primaryContainer: 컨셉 톤(연하게), 표면 전체를 물들이지 않도록 제한
  final Color primaryContainer = dark ? _lerp(primary, background, 0.65) : _lerp(primary, surface, 0.80);
  final Color onPrimaryContainer = _onColor(primaryContainer);

  // Secondary/Tertiary는 중립
  final Color secondary = dark ? const Color(0xFF94A3B8) : const Color(0xFF334155);
  final Color onSecondary = _onColor(secondary);
  final Color secondaryContainer = surfaceVariant;
  final Color onSecondaryContainer = onSurface;

  final Color tertiary = dark ? const Color(0xFFA3A3A3) : const Color(0xFF64748B);
  final Color onTertiary = _onColor(tertiary);
  final Color tertiaryContainer = surfaceContainerLow;
  final Color onTertiaryContainer = onSurface;

  // Error
  final Color error = const Color(0xFFB3261E);
  final Color onError = Colors.white;
  final Color errorContainer = dark ? const Color(0xFF5F1412) : const Color(0xFFF9DEDC);
  final Color onErrorContainer = dark ? const Color(0xFFF2B8B5) : const Color(0xFF410E0B);

  final Color inverseSurface = dark ? const Color(0xFFE5E7EB) : const Color(0xFF0F172A);
  final Color onInverseSurface = dark ? const Color(0xFF0F172A) : const Color(0xFFE5E7EB);
  final Color inversePrimary = dark ? _lerp(primary, Colors.white, 0.35) : _lerp(primary, Colors.black, 0.15);

  return ColorScheme(
    brightness: brightness,

    primary: primary,
    onPrimary: onPrimary,
    primaryContainer: primaryContainer,
    onPrimaryContainer: onPrimaryContainer,

    secondary: secondary,
    onSecondary: onSecondary,
    secondaryContainer: secondaryContainer,
    onSecondaryContainer: onSecondaryContainer,

    tertiary: tertiary,
    onTertiary: onTertiary,
    tertiaryContainer: tertiaryContainer,
    onTertiaryContainer: onTertiaryContainer,

    error: error,
    onError: onError,
    errorContainer: errorContainer,
    onErrorContainer: onErrorContainer,

    background: background,
    onBackground: onSurface,

    surface: surface,
    onSurface: onSurface,

    surfaceVariant: surfaceVariant,
    onSurfaceVariant: onSurfaceVariant,

    outline: outline,
    outlineVariant: outlineVariant,

    shadow: Colors.black,
    scrim: Colors.black,

    inverseSurface: inverseSurface,
    onInverseSurface: onInverseSurface,
    inversePrimary: inversePrimary,

    // ✅ 필터 느낌 방지: surfaceTint 제거
    surfaceTint: Colors.transparent,
  );
}

/// ✅ 독립 ColorScheme: 프리셋이 배경/글자색/하이라이트 글자색을 직접 결정.
/// - background/surface 계열을 프리셋 background로부터 파생.
/// - “나머지 글자색” 요구사항을 위해 onSurface/onBackground/onSurfaceVariant를 bodyText로 고정.
/// - surfaceTint는 투명(필터 방지).
ColorScheme buildIndependentScheme(IndependentBrandTokens t) {
  final dark = t.brightness == Brightness.dark;

  final bg = t.background;
  final on = t.bodyText;

  // 표면 파생(카드/섹션/시트 대비)
  final surface = dark ? _lerp(bg, Colors.black, 0.12) : _lerp(bg, Colors.white, 0.04);
  final surfaceVariant = dark ? _lerp(bg, Colors.black, 0.22) : _lerp(bg, Colors.black, 0.06);

  final outlineVariant = dark ? _lerp(bg, Colors.white, 0.18) : _lerp(bg, Colors.black, 0.12);
  final outline = outlineVariant;

  // ✅ 강조(하이라이트) “글자색”을 primary로 둠 (앱에서 강조 텍스트에 primary를 쓰면 일관되게 적용)
  final primary = t.highlightText;
  final onPrimary = _onColor(primary);

  final primaryContainer = dark ? _lerp(primary, bg, 0.78) : _lerp(primary, bg, 0.88);
  final onPrimaryContainer = _onColor(primaryContainer);

  return ColorScheme(
    brightness: t.brightness,

    primary: primary,
    onPrimary: onPrimary,
    primaryContainer: primaryContainer,
    onPrimaryContainer: onPrimaryContainer,

    // secondary/tertiary는 “나머지 글자색” 규칙을 깨지 않도록 bodyText 기반으로 통일
    secondary: on,
    onSecondary: _onColor(on),
    secondaryContainer: surfaceVariant,
    onSecondaryContainer: on,

    tertiary: on,
    onTertiary: _onColor(on),
    tertiaryContainer: surface,
    onTertiaryContainer: on,

    error: const Color(0xFFB3261E),
    onError: Colors.white,
    errorContainer: dark ? const Color(0xFF5F1412) : const Color(0xFFF9DEDC),
    onErrorContainer: dark ? const Color(0xFFF2B8B5) : const Color(0xFF410E0B),

    background: bg,
    onBackground: on,

    surface: surface,
    onSurface: on,

    surfaceVariant: surfaceVariant,
    onSurfaceVariant: on, // ✅ “나머지 글자색” 고정

    outline: outline,
    outlineVariant: outlineVariant,

    shadow: Colors.black,
    scrim: Colors.black,

    inverseSurface: dark ? Colors.white : Colors.black,
    onInverseSurface: dark ? Colors.black : Colors.white,
    inversePrimary: dark ? _lerp(primary, Colors.white, 0.35) : _lerp(primary, Colors.black, 0.15),

    // ✅ 필터 느낌 방지
    surfaceTint: Colors.transparent,
  );
}

/// ✅ ThemeData 적용(컨셉): scheme을 바꾸되, 표면 틴트를 끄고(필터 방지)
ThemeData applyBrandConceptTheme(ThemeData base, String presetId) {
  final preset = presetById(presetId);
  if (preset.id == 'system' || preset.accent == null) {
    return base;
  }

  final scheme = buildConceptScheme(
    brightness: base.brightness,
    accent: preset.accent!,
  );

  return base.copyWith(
    useMaterial3: true,
    colorScheme: scheme,
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

/// ✅ ThemeData 적용(독립): 프리셋 토큰 기준으로 배경/글자/하이라이트를 강제
ThemeData applyIndependentTheme(ThemeData base, String presetId) {
  final preset = presetById(presetId);
  final t = preset.independentTokens;
  if (t == null) return base;

  final base2 = withBrightness(base, t.brightness);
  final scheme = buildIndependentScheme(t);

  return base2.copyWith(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.background,
    appBarTheme: base2.appBarTheme.copyWith(
      backgroundColor: scheme.surface,
      foregroundColor: scheme.onSurface,
      surfaceTintColor: Colors.transparent,
    ),
    cardTheme: base2.cardTheme.copyWith(
      color: scheme.surface,
      surfaceTintColor: Colors.transparent,
    ),
    bottomSheetTheme: base2.bottomSheetTheme.copyWith(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
    ),
    dividerTheme: base2.dividerTheme.copyWith(
      color: scheme.outlineVariant.withOpacity(0.7),
      thickness: 1,
      space: 1,
    ),
  );
}
