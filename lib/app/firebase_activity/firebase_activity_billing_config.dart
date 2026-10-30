enum FirebaseBillingEdition { standard, enterprise }

class FirebaseActivityBillingConfig {
  const FirebaseActivityBillingConfig._();

  static const FirebaseBillingEdition edition = FirebaseBillingEdition.standard;
  static const String region = 'us-central1';
  static const bool settingsVerified = false;
  static const bool offlinePersistenceEnabled = true;
  static const String pricingDate = '2026-10-30';
  static const String priceReference = 'us-central1 기본 공개 단가 예시';
  static const String exchangeRateReference = '2026-10-30 참고 환율';
  static const double krwPerUsd = 1340.53;
  static const double standardReadUsdPer100k = 0.03;
  static const double standardWriteUsdPer100k = 0.09;
  static const double standardDeleteUsdPer100k = 0.01;
  static const double enterpriseReadUsdPerMillion = 0.05;
  static const double enterpriseWriteUsdPerMillion = 0.26;
  static const double enterpriseRealtimeUsdPerMillion = 0.30;

  static bool get validRates =>
      krwPerUsd > 0 && region.isNotEmpty &&
      standardReadUsdPer100k > 0 && standardWriteUsdPer100k > 0 &&
      standardDeleteUsdPer100k > 0 && enterpriseReadUsdPerMillion > 0 &&
      enterpriseWriteUsdPerMillion > 0 && enterpriseRealtimeUsdPerMillion > 0;

  static String get confidenceLabel => !validRates
      ? '요금 설정 오류'
      : settingsVerified ? '리전·에디션 확인' : '예시 요금 가정';

  static String get editionLabel => edition == FirebaseBillingEdition.standard
      ? 'Standard'
      : 'Enterprise';
}
