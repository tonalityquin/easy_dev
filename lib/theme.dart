import 'package:flutter/material.dart';

@immutable
class AppCardPalette extends ThemeExtension<AppCardPalette> {
  const AppCardPalette({
    required this.serviceBase,
    required this.serviceDark,
    required this.serviceLight,
    required this.singleBase,
    required this.singleDark,
    required this.singleLight,
    required this.doubleBase,
    required this.doubleDark,
    required this.doubleLight,
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
    required this.tripleBase,
    required this.tripleDark,
    required this.tripleLight,

    // ✅ 신규: Minor(마이너)
    required this.minorBase,
    required this.minorDark,
    required this.minorLight,

    required this.parkingBase,
    required this.parkingDark,
    required this.parkingLight,
  });

  /// Selector 카드(서비스)
  final Color serviceBase;
  final Color serviceDark;
  final Color serviceLight;

  /// Selector 카드(약식)
  final Color singleBase;
  final Color singleDark;
  final Color singleLight;

  /// Selector 카드(경량)
  final Color doubleBase;
  final Color doubleDark;
  final Color doubleLight;

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

  /// Selector 카드(트리플)
  final Color tripleBase;
  final Color tripleDark;
  final Color tripleLight;

  /// ✅ Selector 카드(마이너)
  final Color minorBase;
  final Color minorDark;
  final Color minorLight;

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
    singleBase: Color(0xFF00897B),
    singleDark: Color(0xFF00695C),
    singleLight: Color(0xFF80CBC4),

    // Lite (BlueGrey)
    doubleBase: Color(0xFF546E7A),
    doubleDark: Color(0xFF37474F),
    doubleLight: Color(0xFFB0BEC5),

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

    // Triple (Signature: Pink)
    tripleBase: Color(0xFFD81B60),
    tripleDark: Color(0xFFAD1457),
    tripleLight: Color(0xFFF48FB1),

    // ✅ Minor (Signature: Amber/Gold 계열로 기존 컬러들과 겹침 최소화)
    // - triple(Pink), service(Blue), dev(Purple), parking(Orange)와 겹치지 않게 “Amber” 톤으로 배치
    minorBase: Color(0xFFFFB300), // Amber 600
    minorDark: Color(0xFFFF8F00), // Amber 800
    minorLight: Color(0xFFFFE082), // Amber 200

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
    Color? singleBase,
    Color? singleDark,
    Color? singleLight,
    Color? doubleBase,
    Color? doubleDark,
    Color? doubleLight,
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
    Color? tripleBase,
    Color? tripleDark,
    Color? tripleLight,

    // ✅ 신규: Minor
    Color? minorBase,
    Color? minorDark,
    Color? minorLight,

    Color? parkingBase,
    Color? parkingDark,
    Color? parkingLight,
  }) {
    return AppCardPalette(
      serviceBase: serviceBase ?? this.serviceBase,
      serviceDark: serviceDark ?? this.serviceDark,
      serviceLight: serviceLight ?? this.serviceLight,
      singleBase: singleBase ?? this.singleBase,
      singleDark: singleDark ?? this.singleDark,
      singleLight: singleLight ?? this.singleLight,
      doubleBase: doubleBase ?? this.doubleBase,
      doubleDark: doubleDark ?? this.doubleDark,
      doubleLight: doubleLight ?? this.doubleLight,
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
      tripleBase: tripleBase ?? this.tripleBase,
      tripleDark: tripleDark ?? this.tripleDark,
      tripleLight: tripleLight ?? this.tripleLight,

      // ✅ Minor
      minorBase: minorBase ?? this.minorBase,
      minorDark: minorDark ?? this.minorDark,
      minorLight: minorLight ?? this.minorLight,

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
      singleBase: Color.lerp(singleBase, other.singleBase, t)!,
      singleDark: Color.lerp(singleDark, other.singleDark, t)!,
      singleLight: Color.lerp(singleLight, other.singleLight, t)!,
      doubleBase: Color.lerp(doubleBase, other.doubleBase, t)!,
      doubleDark: Color.lerp(doubleDark, other.doubleDark, t)!,
      doubleLight: Color.lerp(doubleLight, other.doubleLight, t)!,
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
      tripleBase: Color.lerp(tripleBase, other.tripleBase, t)!,
      tripleDark: Color.lerp(tripleDark, other.tripleDark, t)!,
      tripleLight: Color.lerp(tripleLight, other.tripleLight, t)!,

      // ✅ Minor lerp 추가
      minorBase: Color.lerp(minorBase, other.minorBase, t)!,
      minorDark: Color.lerp(minorDark, other.minorDark, t)!,
      minorLight: Color.lerp(minorLight, other.minorLight, t)!,

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
