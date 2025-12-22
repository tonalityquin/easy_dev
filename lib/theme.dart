import 'package:flutter/material.dart';

@immutable
class AppCardPalette extends ThemeExtension<AppCardPalette> {
  const AppCardPalette({
    required this.serviceBase,
    required this.serviceDark,
    required this.serviceLight,
    required this.simpleBase,
    required this.simpleDark,
    required this.simpleLight,
    required this.liteBase,
    required this.liteDark,
    required this.liteLight,
    required this.tabletBase,
    required this.tabletDark,
    required this.tabletLight,
    required this.communityBase,
    required this.communityDark,
    required this.communityLight,
    required this.faqBase,
    required this.faqDark,
    required this.faqLight,
    required this.headquarterBase,
    required this.headquarterDark,
    required this.headquarterLight,
    required this.devBase,
    required this.devDark,
    required this.devLight,
    required this.parkingBase,
    required this.parkingDark,
    required this.parkingLight,
  });

  /// Selector 카드(서비스)
  final Color serviceBase;
  final Color serviceDark;
  final Color serviceLight;

  /// Selector 카드(약식)
  final Color simpleBase;
  final Color simpleDark;
  final Color simpleLight;

  /// Selector 카드(경량)
  final Color liteBase;
  final Color liteDark;
  final Color liteLight;

  /// Selector 카드(태블릿)
  final Color tabletBase;
  final Color tabletDark;
  final Color tabletLight;

  /// Selector 카드(커뮤니티)
  final Color communityBase;
  final Color communityDark;
  final Color communityLight;

  /// Selector 카드(FAQ)
  final Color faqBase;
  final Color faqDark;
  final Color faqLight;

  /// Selector 카드(본사)
  final Color headquarterBase;
  final Color headquarterDark;
  final Color headquarterLight;

  /// Selector 카드(개발)
  final Color devBase;
  final Color devDark;
  final Color devLight;

  /// Selector 카드(오프라인 서비스)
  final Color parkingBase;
  final Color parkingDark;
  final Color parkingLight;

  static AppCardPalette of(BuildContext context) {
    // Theme에 확장이 주입되지 않은 경우(테스트/단독 위젯 실행 등) 안전하게 fallback
    return Theme.of(context).extension<AppCardPalette>() ?? AppCardPalette.light;
  }

  static const AppCardPalette light = AppCardPalette(
    // Service
    serviceBase: Color(0xFF0D47A1),
    serviceDark: Color(0xFF09367D),
    serviceLight: Color(0xFF5472D3),

    // Simple
    simpleBase: Color(0xFF00897B),
    simpleDark: Color(0xFF00695C),
    simpleLight: Color(0xFF80CBC4),

    // Lite (BlueGrey)
    liteBase: Color(0xFF546E7A),
    liteDark: Color(0xFF37474F),
    liteLight: Color(0xFFB0BEC5),

    // Tablet
    tabletBase: Color(0xFF00ACC1),
    tabletDark: Color(0xFF00838F),
    tabletLight: Color(0xFF4DD0E1),

    // Community
    communityBase: Color(0xFF26A69A),
    communityDark: Color(0xFF1E8077),
    communityLight: Color(0xFF64D8CB),

    // FAQ
    faqBase: Color(0xFF3949AB),
    faqDark: Color(0xFF283593),
    faqLight: Color(0xFF7986CB),

    // Headquarter
    headquarterBase: Color(0xFF1E88E5),
    headquarterDark: Color(0xFF1565C0),
    headquarterLight: Color(0xFF64B5F6),

    // Dev
    devBase: Color(0xFF6A1B9A),
    devDark: Color(0xFF4A148C),
    devLight: Color(0xFFCE93D8),

    // Parking (Offline Service)
    parkingBase: Color(0xFFF4511E),
    parkingDark: Color(0xFFD84315),
    parkingLight: Color(0xFFFFAB91),
  );

  @override
  AppCardPalette copyWith({
    Color? serviceBase,
    Color? serviceDark,
    Color? serviceLight,
    Color? simpleBase,
    Color? simpleDark,
    Color? simpleLight,
    Color? liteBase,
    Color? liteDark,
    Color? liteLight,
    Color? tabletBase,
    Color? tabletDark,
    Color? tabletLight,
    Color? communityBase,
    Color? communityDark,
    Color? communityLight,
    Color? faqBase,
    Color? faqDark,
    Color? faqLight,
    Color? headquarterBase,
    Color? headquarterDark,
    Color? headquarterLight,
    Color? devBase,
    Color? devDark,
    Color? devLight,
    Color? parkingBase,
    Color? parkingDark,
    Color? parkingLight,
  }) {
    return AppCardPalette(
      serviceBase: serviceBase ?? this.serviceBase,
      serviceDark: serviceDark ?? this.serviceDark,
      serviceLight: serviceLight ?? this.serviceLight,
      simpleBase: simpleBase ?? this.simpleBase,
      simpleDark: simpleDark ?? this.simpleDark,
      simpleLight: simpleLight ?? this.simpleLight,
      liteBase: liteBase ?? this.liteBase,
      liteDark: liteDark ?? this.liteDark,
      liteLight: liteLight ?? this.liteLight,
      tabletBase: tabletBase ?? this.tabletBase,
      tabletDark: tabletDark ?? this.tabletDark,
      tabletLight: tabletLight ?? this.tabletLight,
      communityBase: communityBase ?? this.communityBase,
      communityDark: communityDark ?? this.communityDark,
      communityLight: communityLight ?? this.communityLight,
      faqBase: faqBase ?? this.faqBase,
      faqDark: faqDark ?? this.faqDark,
      faqLight: faqLight ?? this.faqLight,
      headquarterBase: headquarterBase ?? this.headquarterBase,
      headquarterDark: headquarterDark ?? this.headquarterDark,
      headquarterLight: headquarterLight ?? this.headquarterLight,
      devBase: devBase ?? this.devBase,
      devDark: devDark ?? this.devDark,
      devLight: devLight ?? this.devLight,
      parkingBase: parkingBase ?? this.parkingBase,
      parkingDark: parkingDark ?? this.parkingDark,
      parkingLight: parkingLight ?? this.parkingLight,
    );
  }

  @override
  AppCardPalette lerp(ThemeExtension<AppCardPalette>? other, double t) {
    if (other is! AppCardPalette) return this;
    return AppCardPalette(
      serviceBase: Color.lerp(serviceBase, other.serviceBase, t)!,
      serviceDark: Color.lerp(serviceDark, other.serviceDark, t)!,
      serviceLight: Color.lerp(serviceLight, other.serviceLight, t)!,
      simpleBase: Color.lerp(simpleBase, other.simpleBase, t)!,
      simpleDark: Color.lerp(simpleDark, other.simpleDark, t)!,
      simpleLight: Color.lerp(simpleLight, other.simpleLight, t)!,
      liteBase: Color.lerp(liteBase, other.liteBase, t)!,
      liteDark: Color.lerp(liteDark, other.liteDark, t)!,
      liteLight: Color.lerp(liteLight, other.liteLight, t)!,
      tabletBase: Color.lerp(tabletBase, other.tabletBase, t)!,
      tabletDark: Color.lerp(tabletDark, other.tabletDark, t)!,
      tabletLight: Color.lerp(tabletLight, other.tabletLight, t)!,
      communityBase: Color.lerp(communityBase, other.communityBase, t)!,
      communityDark: Color.lerp(communityDark, other.communityDark, t)!,
      communityLight: Color.lerp(communityLight, other.communityLight, t)!,
      faqBase: Color.lerp(faqBase, other.faqBase, t)!,
      faqDark: Color.lerp(faqDark, other.faqDark, t)!,
      faqLight: Color.lerp(faqLight, other.faqLight, t)!,
      headquarterBase: Color.lerp(headquarterBase, other.headquarterBase, t)!,
      headquarterDark: Color.lerp(headquarterDark, other.headquarterDark, t)!,
      headquarterLight: Color.lerp(headquarterLight, other.headquarterLight, t)!,
      devBase: Color.lerp(devBase, other.devBase, t)!,
      devDark: Color.lerp(devDark, other.devDark, t)!,
      devLight: Color.lerp(devLight, other.devLight, t)!,
      parkingBase: Color.lerp(parkingBase, other.parkingBase, t)!,
      parkingDark: Color.lerp(parkingDark, other.parkingDark, t)!,
      parkingLight: Color.lerp(parkingLight, other.parkingLight, t)!,
    );
  }
}

final ThemeData appTheme = ThemeData(
  primarySwatch: Colors.blue,
  scaffoldBackgroundColor: Colors.white,
  appBarTheme: const AppBarTheme(
    backgroundColor: Colors.blue,
    foregroundColor: Colors.white,
    elevation: 0,
  ),
  textTheme: const TextTheme(
    // 기존 cards.dart에서 titleMedium을 사용하므로, 전역에서 기본값을 정의해두면 일관성이 좋아집니다.
    titleMedium: TextStyle(fontSize: 16.0, color: Colors.black),
    bodyLarge: TextStyle(fontSize: 18.0, color: Colors.black),
    bodyMedium: TextStyle(fontSize: 16.0, color: Colors.black),
  ),
  extensions: const <ThemeExtension<dynamic>>[
    AppCardPalette.light,
  ],
);
