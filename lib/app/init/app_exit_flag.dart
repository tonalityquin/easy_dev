class AppExitFlag {
  static bool _exiting = false;

  static bool get isExiting => _exiting;

  static void beginExit() {
    _exiting = true;
  }

  static void reset() {
    _exiting = false;
  }
}
