import 'brand_theme.dart';

class AreaThemeRegistry {
  AreaThemeRegistry._();

  static const Map<String, String> _bindings = <String, String>{
    'KB라이프역삼': kKbBrandPresetId,
    'belivussnc': kBelieversScBrandPresetId,
    'britishArea': kSesotneunOrthopedicBrandPresetId,
    '남양주프라임정형외과': kNamyangjuPrimeBrandPresetId,
    '북한강막국수닭갈비': kBukhangangMakguksuDakgalbiBrandPresetId,
    '빌리버스에스앤씨테스트': kBelieversScBrandPresetId,
    '삼성본프라임정형외과': kSamsungBonprimeBrandPresetId,
    '세솟는정형외과': kSesotneunOrthopedicBrandPresetId,
    '연세바로척병원': kYonseiBaroChukHospitalBrandPresetId,
    '하늘병원': kHaneulHospitalBrandPresetId,
  };

  static String? registeredPresetIdFor(String selectedArea) {
    final normalized = selectedArea.trim();
    if (normalized.isEmpty) return null;
    final registered = _bindings[normalized];
    if (registered == null || !isKnownBrandPresetId(registered)) return null;
    return registered;
  }

  static bool hasBrandFor(String selectedArea) {
    return registeredPresetIdFor(selectedArea) != null;
  }

  static String defaultPresetIdFor(String selectedArea) {
    return registeredPresetIdFor(selectedArea) ?? kDefaultBrandPresetId;
  }
}
