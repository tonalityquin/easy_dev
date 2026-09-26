import 'brand_theme.dart';

class AreaThemeRegistry {
  AreaThemeRegistry._();

  static const Map<String, String> _bindings = <String, String>{};

  static String? registeredPresetIdFor(String selectedArea) {
    final normalized = selectedArea.trim();
    if (normalized.isEmpty) return null;
    return _bindings[normalized];
  }

  static String defaultPresetIdFor(String selectedArea) {
    final registered = registeredPresetIdFor(selectedArea);
    if (registered != null && isKnownBrandPresetId(registered)) {
      return registered;
    }
    return kDefaultBrandPresetId;
  }
}
