// lib/utils/app_exit_flag.dart

/// 사용자가 헤더의 "앱 종료" 버튼을 눌러
/// 명시적으로 앱 종료 플로우를 타는 중인지 표시하는 플래그.
class AppExitFlag {
  static bool _exiting = false;

  static bool get isExiting => _exiting;

  /// 앱 종료 플로우 시작
  static void beginExit() {
    _exiting = true;
  }

  /// 종료 플로우가 실패하거나, detach 이후 정리 완료 시 리셋
  static void reset() {
    _exiting = false;
  }
}
