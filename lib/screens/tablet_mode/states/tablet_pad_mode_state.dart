import 'package:flutter/foundation.dart';

/// 태블릿 화면 모드
/// - big   : 좌측 목록 + 우측 검색(상단) + 키패드(하단 45%)
/// - small : 좌측 목록 + 우측 키패드(패널 높이 100%)
/// - show  : 좌측 패널만 전체 화면
/// - mobile: 단일 화면(상단 입력 표시 + 하단 키패드) — 좌/우 패널 분할 없음
enum PadMode { big, small, show, mobile }

class TabletPadModeState extends ChangeNotifier {
  // ✅ 기본값을 mobile로 변경
  PadMode _mode = PadMode.mobile;

  PadMode get mode => _mode;

  bool get isBig => _mode == PadMode.big;
  bool get isSmall => _mode == PadMode.small;
  bool get isShow => _mode == PadMode.show;
  bool get isMobile => _mode == PadMode.mobile;

  void setMode(PadMode next) {
    if (_mode == next) return;
    _mode = next;
    notifyListeners();
  }
}
