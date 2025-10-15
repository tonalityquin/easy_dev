// lib/offlines/tts/offline_tts_filters.dart
/// 오프라인 TTS 토글(메모리 상수) — 영구 저장 안 함.
/// 필요 시 SQLite에 설정 테이블을 두고 로딩/저장하도록 확장하세요.
class OfflineTtsFilters {
  /// 마스터 on/off
  static bool enabled = true;

  /// 상태별 on/off
  static bool parkingRequest = true;     // 입차 요청(생성)
  static bool departureRequest = true;   // 출차 요청(상태 전환)
  static bool departureCompleted = true; // 출차 완료(상태 전환)

  /// 간단 프리셋
  static void enableAll() {
    enabled = true;
    parkingRequest = true;
    departureRequest = true;
    departureCompleted = true;
  }

  static void disableAll() {
    enabled = false;
    parkingRequest = false;
    departureRequest = false;
    departureCompleted = false;
  }
}
