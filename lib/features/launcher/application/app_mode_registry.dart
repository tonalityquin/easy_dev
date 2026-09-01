import 'app_mode_definition.dart';

class AppModeRegistry {
  const AppModeRegistry._();

  static const List<AppModeDefinition> modes = <AppModeDefinition>[
    AppModeDefinition(
      id: 'personal',
      koreanName: '개인형',
      englishName: 'personal',
      description: '모바일 직접 출차 요청',
      aliases: <String>{
        'personal',
        'mobile',
        'direct',
        '개인',
        '개인형',
        '개인용',
      },
      postLoginRoute: '/personal_page',
    ),
    AppModeDefinition(
      id: 'tablet',
      koreanName: '태블릿형',
      englishName: 'tablet',
      description: '태블릿 설치형',
      aliases: <String>{
        'tablet',
        '태블릿',
        '태블릿형',
        '태블릿 설치형',
      },
      postLoginRoute: '/tablet_page',
    ),
    AppModeDefinition(
      id: 'single',
      koreanName: '출퇴근 기록형',
      englishName: 'single',
      description: '출/퇴근 · 휴게시간',
      aliases: <String>{
        'single',
        '출퇴근',
        '출퇴근형',
        '출퇴근 기록형',
      },
      postLoginRoute: '/single_commute',
    ),
    AppModeDefinition(
      id: 'double',
      koreanName: '경량형',
      englishName: 'double',
      description: '입차 완료 · 출차 완료',
      aliases: <String>{
        'double',
        'lite',
        'light',
        '경량',
        '경량형',
      },
      postLoginRoute: '/double_commute',
    ),
    AppModeDefinition(
      id: 'triple',
      koreanName: '기본형',
      englishName: 'triple',
      description: '입차 완료 · 출차 요청 · 출차 완료',
      aliases: <String>{
        'triple',
        'normal',
        '기본',
        '기본형',
      },
      postLoginRoute: '/triple_commute',
    ),
    AppModeDefinition(
      id: 'minor',
      koreanName: '확장형',
      englishName: 'minor',
      description: '입차 요청 · 입차 완료 · 출차 요청 · 출차 완료',
      aliases: <String>{
        'minor',
        '확장',
        '확장형',
      },
      postLoginRoute: '/minor_commute',
    ),
  ];

  static String normalizeToken(String? raw) {
    return (raw ?? '')
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'\s+'), ' ');
  }

  static AppModeDefinition? find(String? raw) {
    final normalized = normalizeToken(raw);
    if (normalized.isEmpty || normalized == 'service') return null;
    for (final mode in modes) {
      if (mode.id == normalized ||
          mode.englishName == normalized ||
          mode.aliases.contains(normalized)) {
        return mode;
      }
    }
    return null;
  }

  static AppModeDefinition? findLegacy(String? raw) {
    final normalized = normalizeToken(raw);
    if (normalized == 'simple') return byId('single');
    return find(normalized);
  }

  static String? normalizeMode(String? raw) => find(raw)?.id;

  static String? normalizeLegacyMode(String? raw) => findLegacy(raw)?.id;

  static String normalizeModeOrService(String? raw) {
    final normalized = normalizeToken(raw);
    if (normalized == 'service' || normalized.isEmpty) return 'service';
    return findLegacy(normalized)?.id ?? 'service';
  }

  static List<AppModeDefinition> supportedModes(
    Iterable<String> rawModes, {
    Set<String>? allowedIds,
  }) {
    final ids = <String>{};
    for (final raw in rawModes) {
      final mode = findLegacy(raw);
      if (mode == null) continue;
      if (allowedIds != null && !allowedIds.contains(mode.id)) continue;
      ids.add(mode.id);
    }
    return <AppModeDefinition>[
      for (final mode in modes)
        if (ids.contains(mode.id)) mode,
    ];
  }

  static String persistedValue(String modeId) {
    switch (modeId) {
      case 'single':
        return 'single';
      case 'double':
        return 'lite';
      default:
        return modeId;
    }
  }

  static AppModeDefinition? byId(String? id) {
    final normalized = normalizeToken(id);
    for (final mode in modes) {
      if (mode.id == normalized) return mode;
    }
    return null;
  }
}
