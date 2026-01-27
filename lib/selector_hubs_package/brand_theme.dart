import 'package:flutter/material.dart';

/// ✅ 컬러 프리셋 저장 키
const String kBrandPresetKey = 'selector_brand_preset_v1';

/// ✅ 테마 모드 저장 키 (system/light/dark)
const String kThemeModeKey = 'selector_theme_mode_v1';

@immutable
class BrandPresetSpec {
  const BrandPresetSpec({
    required this.id,
    required this.label,
    required this.accent,
    required this.preview,
  });

  final String id;
  final String label;

  /// 컨셉(포인트) 색. system은 null.
  final Color? accent;

  /// UI 프리뷰(3색 점)
  final List<Color> preview;
}

List<BrandPresetSpec> brandPresets() {
  return const [
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
  ];
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

  final String id; // system | light | dark
  final String label;
  final IconData icon;
}

List<ThemeModeSpec> themeModeSpecs() {
  return const [
    ThemeModeSpec(id: 'system', label: '시스템', icon: Icons.brightness_auto_rounded),
    ThemeModeSpec(id: 'light', label: '라이트', icon: Icons.light_mode_rounded),
    ThemeModeSpec(id: 'dark', label: '다크', icon: Icons.dark_mode_rounded),
  ];
}

/// system/light/dark -> Brightness 결정
Brightness resolveBrightness(String themeModeId, Brightness systemBrightness) {
  switch (themeModeId) {
    case 'light':
      return Brightness.light;
    case 'dark':
      return Brightness.dark;
    case 'system':
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

/// ✅ ThemeData 적용: scheme을 바꾸되, 표면 틴트를 끄고(필터 방지)
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
