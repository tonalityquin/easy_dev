import 'package:flutter/material.dart';

const String kBrandPresetKey = 'selector_brand_preset_v1';
const String kDefaultBrandPresetId = 'soft_linen';
const String kKbBrandPresetId = 'kb';
const String kBelieversScBrandPresetId = 'believers_sc';
const String kNamyangjuPrimeBrandPresetId = 'namyangju_prime';
const String kSamsungBonprimeBrandPresetId = 'samsung_bonprime';
const String kHaneulHospitalBrandPresetId = 'haneul_hospital';
const String kYonseiBaroChukHospitalBrandPresetId =
    'yonsei_baro_chuk_hospital';
const String kSesotneunOrthopedicBrandPresetId = 'sesotneun_orthopedic';
const String kBukhangangMakguksuDakgalbiBrandPresetId =
    'bukhangang_makguksu_dakgalbi';

enum BrandContentRole {
  brand,
  accent,
}

@immutable
class BrandThemeColors {
  const BrandThemeColors({
    required this.base,
    required this.brand,
    required this.accent,
    required this.contentRole,
  });

  final Color base;
  final Color brand;
  final Color accent;
  final BrandContentRole contentRole;

  Color get content =>
      contentRole == BrandContentRole.brand ? brand : accent;

  Color get resolvedAccent => accent;

  Brightness get brightness => ThemeData.estimateBrightnessForColor(base);

  List<Color> get preview => <Color>[base, brand, accent];
}

@immutable
class BrandPresetSpec {
  const BrandPresetSpec({
    required this.id,
    required this.label,
    required this.colors,
  });

  final String id;
  final String label;
  final BrandThemeColors colors;

  List<Color> get preview => colors.preview;
}

const BrandPresetSpec kDefaultBrandPreset = BrandPresetSpec(
  id: kDefaultBrandPresetId,
  label: '기본',
  colors: BrandThemeColors(
    base: Color(0xFFF2EDE3),
    brand: Color(0xFF2F6F6D),
    accent: Color(0xFF2C2A26),
    contentRole: BrandContentRole.accent,
  ),
);

const BrandPresetSpec kKbBrandPreset = BrandPresetSpec(
  id: kKbBrandPresetId,
  label: 'KB',
  colors: BrandThemeColors(
    base: Color(0xFF60594E),
    brand: Color(0xFFFFBC00),
    accent: Color(0xFFFFFFFF),
    contentRole: BrandContentRole.accent,
  ),
);

const BrandPresetSpec kBelieversScBrandPreset = BrandPresetSpec(
  id: kBelieversScBrandPresetId,
  label: '빌리버스에스앤씨',
  colors: BrandThemeColors(
    base: Color(0xFFF4F8FB),
    brand: Color(0xFF56A4DB),
    accent: Color(0xFF4E4D4D),
    contentRole: BrandContentRole.accent,
  ),
);

const BrandPresetSpec kNamyangjuPrimeBrandPreset = BrandPresetSpec(
  id: kNamyangjuPrimeBrandPresetId,
  label: '남양주프라임',
  colors: BrandThemeColors(
    base: Color(0xFFF0F7FA),
    brand: Color(0xFF10639F),
    accent: Color(0xFF74BBCE),
    contentRole: BrandContentRole.brand,
  ),
);

const BrandPresetSpec kSamsungBonprimeBrandPreset = BrandPresetSpec(
  id: kSamsungBonprimeBrandPresetId,
  label: '삼성본프라임',
  colors: BrandThemeColors(
    base: Color(0xFFF2F6F8),
    brand: Color(0xFF183E5B),
    accent: Color(0xFF4584A2),
    contentRole: BrandContentRole.brand,
  ),
);

const BrandPresetSpec kHaneulHospitalBrandPreset = BrandPresetSpec(
  id: kHaneulHospitalBrandPresetId,
  label: '하늘병원',
  colors: BrandThemeColors(
    base: Color(0xFFF4F7F2),
    brand: Color(0xFF1D2683),
    accent: Color(0xFF73BB2B),
    contentRole: BrandContentRole.brand,
  ),
);


const BrandPresetSpec kYonseiBaroChukHospitalBrandPreset = BrandPresetSpec(
  id: kYonseiBaroChukHospitalBrandPresetId,
  label: '연세바로척병원',
  colors: BrandThemeColors(
    base: Color(0xFFE5F1F6),
    brand: Color(0xFF69A4C2),
    accent: Color(0xFF315F78),
    contentRole: BrandContentRole.accent,
  ),
);

const BrandPresetSpec kSesotneunOrthopedicBrandPreset = BrandPresetSpec(
  id: kSesotneunOrthopedicBrandPresetId,
  label: '세솟는정형외과',
  colors: BrandThemeColors(
    base: Color(0xFF232426),
    brand: Color(0xFFF2F363),
    accent: Color(0xFFFAFAF1),
    contentRole: BrandContentRole.accent,
  ),
);

const BrandPresetSpec kBukhangangMakguksuDakgalbiBrandPreset =
    BrandPresetSpec(
  id: kBukhangangMakguksuDakgalbiBrandPresetId,
  label: '북한강막국수닭갈비',
  colors: BrandThemeColors(
    base: Color(0xFFF7F4EA),
    brand: Color(0xFF696F7B),
    accent: Color(0xFFEDDA96),
    contentRole: BrandContentRole.brand,
  ),
);

List<BrandPresetSpec> brandPresets() {
  return const <BrandPresetSpec>[
    kDefaultBrandPreset,
    kKbBrandPreset,
    kBelieversScBrandPreset,
    kNamyangjuPrimeBrandPreset,
    kSamsungBonprimeBrandPreset,
    kHaneulHospitalBrandPreset,
    kYonseiBaroChukHospitalBrandPreset,
    kSesotneunOrthopedicBrandPreset,
    kBukhangangMakguksuDakgalbiBrandPreset,
  ];
}

BrandPresetSpec presetById(String id) {
  final normalized = id.trim();
  return brandPresets().firstWhere(
    (preset) => preset.id == normalized,
    orElse: () => kDefaultBrandPreset,
  );
}

bool isKnownBrandPresetId(String id) {
  final normalized = id.trim();
  return brandPresets().any((preset) => preset.id == normalized);
}

Color _mix(Color a, Color b, double amount) {
  return Color.lerp(a, b, amount.clamp(0.0, 1.0).toDouble())!;
}

Color _onColor(Color background) {
  return ThemeData.estimateBrightnessForColor(background) == Brightness.dark
      ? Colors.white
      : Colors.black;
}

ColorScheme buildBrandColorScheme(BrandThemeColors colors) {
  final brightness = colors.brightness;
  final dark = brightness == Brightness.dark;
  final base = colors.base;
  final brand = colors.brand;
  final content = colors.content;
  final accent = colors.accent;
  final surface = dark
      ? _mix(base, Colors.black, 0.10)
      : _mix(base, Colors.white, 0.16);
  final surfaceVariant = dark
      ? _mix(base, Colors.black, 0.20)
      : _mix(base, Colors.black, 0.06);
  final primaryContainer = dark
      ? _mix(brand, base, 0.72)
      : _mix(brand, base, 0.82);
  final outline = dark
      ? _mix(content, base, 0.60)
      : _mix(content, base, 0.68);
  final outlineVariant = dark
      ? _mix(content, base, 0.74)
      : _mix(content, base, 0.82);
  final secondary = accent;
  final secondaryContainer = dark
      ? _mix(accent, base, 0.70)
      : _mix(accent, base, 0.82);
  final tertiary = dark
      ? _mix(brand, accent, 0.38)
      : _mix(brand, accent, 0.52);
  final error = const Color(0xFFB3261E);
  final errorContainer = dark
      ? const Color(0xFF5F1412)
      : const Color(0xFFF9DEDC);
  final onErrorContainer = dark
      ? const Color(0xFFF2B8B5)
      : const Color(0xFF410E0B);
  final inverseSurface = dark ? Colors.white : Colors.black;
  final onInverseSurface = dark ? Colors.black : Colors.white;

  return ColorScheme(
    brightness: brightness,
    primary: brand,
    onPrimary: _onColor(brand),
    primaryContainer: primaryContainer,
    onPrimaryContainer: _onColor(primaryContainer),
    secondary: secondary,
    onSecondary: _onColor(secondary),
    secondaryContainer: secondaryContainer,
    onSecondaryContainer: content,
    tertiary: tertiary,
    onTertiary: _onColor(tertiary),
    tertiaryContainer: surface,
    onTertiaryContainer: content,
    error: error,
    onError: Colors.white,
    errorContainer: errorContainer,
    onErrorContainer: onErrorContainer,
    background: base,
    onBackground: content,
    surface: surface,
    onSurface: content,
    surfaceVariant: surfaceVariant,
    onSurfaceVariant: content,
    outline: outline,
    outlineVariant: outlineVariant,
    shadow: Colors.black,
    scrim: Colors.black,
    inverseSurface: inverseSurface,
    onInverseSurface: onInverseSurface,
    inversePrimary: dark
        ? _mix(brand, Colors.white, 0.35)
        : _mix(brand, Colors.black, 0.15),
    surfaceTint: Colors.transparent,
  );
}

ThemeData buildBrandTheme(BrandPresetSpec preset) {
  final scheme = buildBrandColorScheme(preset.colors);
  final base = ThemeData(
    useMaterial3: true,
    brightness: scheme.brightness,
    colorScheme: scheme,
  );
  final seededTextTheme = base.textTheme.copyWith(
    titleMedium: (base.textTheme.titleMedium ?? const TextStyle()).copyWith(
      fontSize: 16.0,
    ),
    bodyLarge: (base.textTheme.bodyLarge ?? const TextStyle()).copyWith(
      fontSize: 18.0,
    ),
    bodyMedium: (base.textTheme.bodyMedium ?? const TextStyle()).copyWith(
      fontSize: 16.0,
    ),
  );
  final textTheme = seededTextTheme.apply(
    bodyColor: scheme.onSurface,
    displayColor: scheme.onSurface,
  );

  return base.copyWith(
    colorScheme: scheme,
    textTheme: textTheme,
    scaffoldBackgroundColor: scheme.background,
    canvasColor: scheme.background,
    appBarTheme: base.appBarTheme.copyWith(
      backgroundColor: scheme.surface,
      foregroundColor: scheme.onSurface,
      surfaceTintColor: Colors.transparent,
    ),
    cardTheme: base.cardTheme.copyWith(
      color: scheme.surface,
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

String colorHex(Color color) {
  return '#${color.value.toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}';
}
