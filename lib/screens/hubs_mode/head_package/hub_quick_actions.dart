// lib/screens/head_package/hub_quick_actions.dart
import 'dart:math' as math;
import 'dart:ui'; // BackdropFilter: ImageFilter
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:shared_preferences/shared_preferences.dart';

import '../../../utils/app_navigator.dart';
import '../head_package/head_memo.dart';
import '../head_package/company_calendar_page.dart';
import '../head_package/hr_package/attendance_calendar.dart' as hr_att;
import '../head_package/hr_package/break_calendar.dart' as hr_break;

/// 본사 허브용 퀵 액션 플로팅 버블(오버레이)
/// - 글래스 Dock(가로 일렬 아이콘), 자동 간격/방향, 스프링 모션, 접근성/툴팁
class HeadHubActions {
  HeadHubActions._();

  static GlobalKey<NavigatorState> get navigatorKey => AppNavigator.key;

  /// 온/오프 토글 상태 (영속화)
  static final enabled = ValueNotifier<bool>(false);

  static const _kEnabledKey = 'head_hub_actions_enabled_v1';
  static const _kBubbleXKey = 'head_hub_actions_bubble_x_v1';
  static const _kBubbleYKey = 'head_hub_actions_bubble_y_v1';

  static SharedPreferences? _prefs;
  static OverlayEntry? _entry;
  static bool _initialized = false;

  // ▼▼▼ 바텀시트 “단일 인스턴스” 관리용 내부 상태 ▼▼▼
  static bool _closing = false;
  static bool _opening = false;

  /// 지금 떠 있는 바텀시트의 완료 Future 추적(완전히 닫힐 때 완료)
  static Future<void>? _activeSheet;

  /// 현재 가장 안전한 context (Navigator.overlay.context 우선)
  static BuildContext? _bestContext() {
    final state = navigatorKey.currentState;
    final overlayCtx = state?.overlay?.context;
    return overlayCtx ?? state?.context;
  }

  /// (공용) 열려있는 바텀시트를 닫고, 실제로 닫힐 때까지 기다림 (있으면 닫고, 없으면 no-op)
  static Future<void> closeAnySheet() async {
    if (_closing) return;
    _closing = true;
    try {
      final ctx = _bestContext();
      if (ctx == null) return;

      // 현재 추적 중인 시트가 있으면: dismiss 요청 후 그 Future가 끝날 때까지 대기
      final tracked = _activeSheet;
      if (tracked != null) {
        Navigator.of(ctx).maybePop(); // dismiss 요청
        try {
          await tracked; // 완전 종료까지 대기
        } catch (_) {
          // dismiss 중 pop이 이미 되었거나, 라우트가 사라지는 경우 등을 묵살
        }
        await Future<void>.delayed(const Duration(milliseconds: 16)); // 한 프레임 여유
        return;
      }

      // 추적중인 시트가 없으면 1회 팝 시도(필요 없으면 no-op)
      final popped = await Navigator.of(ctx).maybePop();
      if (popped) {
        // 일반 라우트/시트 애니메이션 여유
        await Future<void>.delayed(const Duration(milliseconds: 220));
      }
    } finally {
      _closing = false;
    }
  }

  /// (공용) 기존 시트를 닫은 뒤, 주어진 함수를 통해 “새 시트”를 연다.
  /// - 빠른 연타/연속 호출에 대비해 간단한 뮤텍스(_opening)로 직렬화
  /// - openFn은 반드시 showModalBottomSheet가 반환하는 Future를 반환해야 함
  static Future<void> openSheetExclusively(
      Future<dynamic> Function(BuildContext ctx) openFn,
      ) async {
    if (_opening) return;
    _opening = true;
    try {
      await closeAnySheet();
      final ctx = _bestContext();
      if (ctx == null) return;

      // openFn이 반환한 Future를 추적하여 완전 종료까지 기다림
      final dynamic fut = openFn(ctx);
      if (fut is Future) {
        final Future<void> tracked = fut.then<void>((_) {});
        _activeSheet = tracked;
        try {
          await tracked; // 시트가 닫힐 때까지 완료 대기
        } finally {
          _activeSheet = null;
        }
      } else {
        // Future를 반환하지 않는 경우를 대비한 최소 대기
        await Future<void>.delayed(const Duration(milliseconds: 16));
      }
    } finally {
      _opening = false;
    }
  }

  /// 초기화 1회
  static Future<void> init() async {
    if (_initialized) return;
    _prefs ??= await SharedPreferences.getInstance();
    enabled.value = _prefs!.getBool(_kEnabledKey) ?? false;

    // 토글 변경 → 저장 + 오버레이 토글
    enabled.addListener(() {
      _prefs?.setBool(_kEnabledKey, enabled.value);
      if (enabled.value) {
        _showOverlay();
      } else {
        _hideOverlay();
      }
    });
    _initialized = true;
  }

  /// 필요 시 지연 초기화 + 부착
  static Future<void> mountIfNeeded() async {
    if (!_initialized || _prefs == null) {
      await init();
    }
    if (enabled.value) _showOverlay();
  }

  /// 외부에서 스위치로 토글할 때 사용할 공개 API
  static void setEnabled(bool value) => enabled.value = value;
  static void toggle() => enabled.value = !enabled.value;

  static Offset _restorePos() {
    final dx = _prefs?.getDouble(_kBubbleXKey) ?? 12.0;
    final dy = _prefs?.getDouble(_kBubbleYKey) ?? 200.0;
    return Offset(dx, dy);
  }

  static Future<void> _savePos(Offset pos) async {
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.setDouble(_kBubbleXKey, pos.dx);
    await _prefs!.setDouble(_kBubbleYKey, pos.dy);
  }

  // ── 오버레이 라이프사이클 ──────────────────────────────
  static void _showOverlay() {
    if (_entry != null) return;
    final overlay = navigatorKey.currentState?.overlay;
    if (overlay == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _showOverlay());
      return;
    }
    _entry = OverlayEntry(
      builder: (context) => _HubBubble(
        initialPos: _restorePos(),
        onPosSave: _savePos,
      ),
    );
    overlay.insert(_entry!);
  }

  static void _hideOverlay() {
    _entry?.remove();
    _entry = null;
  }
}

class _HubBubble extends StatefulWidget {
  final Offset initialPos;
  final Future<void> Function(Offset) onPosSave;

  const _HubBubble({required this.initialPos, required this.onPosSave});

  @override
  State<_HubBubble> createState() => _HubBubbleState();
}

class _HubBubbleState extends State<_HubBubble> with SingleTickerProviderStateMixin {
  // ── 디자인 토큰 ─────────────────────────────────────────
  static const double _bubbleSize = 56;   // 메인 FAB
  static const double _iconSize = 22;     // Dock 안 아이콘
  static const double _chip = 44;         // Dock 아이콘 터치 타깃(원칩)
  static const double _dockHPad = 12;     // Dock 좌우 패딩
  static const double _dockVPad = 8;      // Dock 상하 패딩
  static const double _gapMax = 20;       // 아이콘 간 최대 간격
  static const double _gapMin = 10;       // 아이콘 간 최소 간격
  static const double _dockRadius = 18;   // Dock 코너
  static const double _edgePad = 8;       // 버블-도크 사이 여백

  late Offset _pos;
  bool _clampedOnce = false;

  late final AnimationController _ctrl;
  late final Animation<double> _t;    // 0→1 전개 비율(모션)
  bool get _expanded => _ctrl.value > 0.001;

  @override
  void initState() {
    super.initState();
    _pos = widget.initialPos;
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 240),
    );
    _t = CurvedAnimation(
      parent: _ctrl,
      curve: const SpringCurve(),          // 스프링 느낌의 이징
      reverseCurve: Curves.easeInCubic,
    )..addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _toggleMenu() {
    _expanded ? _ctrl.reverse() : _ctrl.forward();
    HapticFeedback.lightImpact();
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.maybeOf(context);
    final screen = media?.size ?? Size.zero;
    final bottomInset = media?.padding.bottom ?? 0;
    final cs = Theme.of(context).colorScheme;

    if (!_clampedOnce && screen != Size.zero) {
      _clampedOnce = true;
      _pos = _clampToScreen(_pos, screen, bottomInset);
    }

    // 좌/우 가용폭 계산
    final rightSpace = screen.width - (_pos.dx + _bubbleSize) - _edgePad;
    final leftSpace  = _pos.dx - _edgePad;

    // Dock의 필요 폭(아이콘 5개 기준) 산정
    const count = 5;
    final minInnerWidth = count * _chip + (count - 1) * _gapMin;
    final neededAtMin = _dockHPad * 2 + minInnerWidth;

    // 어느 쪽에 펼칠지 결정 (넉넉한 쪽 우선)
    final preferRight = rightSpace >= leftSpace;
    final canRight = rightSpace >= neededAtMin;
    final canLeft  = leftSpace  >= neededAtMin;
    final useRight = canRight || (!canLeft && preferRight);

    // 실제 펼칠 방향과 가용 폭
    final avail = (useRight ? rightSpace : leftSpace).clamp(0.0, double.infinity);

    // 실제 간격(gap) 계산(가용 폭에 맞춰 자동 보정)
    final gap = _calcGap(avail: avail, count: count);

    // Dock 내부 컨텐츠 폭(패딩 제외)
    final innerWidth = (count * _chip + (count - 1) * gap).ceilToDouble();

    // Dock 치수 계산(반올림으로 안전 보정)
    final dockWidth = (_dockHPad * 2 + innerWidth).ceilToDouble();
    final dockHeight = (_dockVPad * 2 + _chip).ceilToDouble();

    // Dock 위치 계산 (버블 중앙 기준 수직 정렬)
    final dockLeft = useRight
        ? (_pos.dx + _bubbleSize + _edgePad)
        : (_pos.dx - dockWidth - _edgePad);
    final dockTop = _pos.dy + (_bubbleSize - dockHeight) / 2;

    return Stack(
      children: [
        // ── Dim/Scrim + 터치 닫기 ─────────────────────────
        if (_expanded)
          Positioned.fill(
            child: GestureDetector(
              onTap: _toggleMenu,
              behavior: HitTestBehavior.opaque,
              child: AnimatedOpacity(
                opacity: 0.04 * _t.value, // 아주 옅은 딤
                duration: const Duration(milliseconds: 120),
                child: const ColoredBox(color: Colors.black),
              ),
            ),
          ),

        // ── 글래스 Dock (가로 일렬 아이콘) ─────────────────
        Positioned(
          left: dockLeft,
          top: dockTop,
          child: IgnorePointer(
            ignoring: !_expanded,
            child: Transform.scale(
              scale: 0.96 + 0.04 * _t.value, // 살짝 튀어나오는 스케일
              alignment: useRight ? Alignment.centerLeft : Alignment.centerRight,
              child: Opacity(
                opacity: _t.value,
                child: _GlassDock(
                  width: dockWidth,
                  height: dockHeight,
                  radius: _dockRadius,
                  hPad: _dockHPad,
                  vPad: _dockVPad,
                  child: _DockRow(
                    innerWidth: innerWidth,
                    chip: _chip,
                    iconSize: _iconSize,
                    actions: [
                      _DockAction(
                        icon: Icons.sticky_note_2_rounded,
                        label: '메모',
                        color: cs.secondaryContainer,
                        onTap: () async {
                          await _ctrl.reverse();
                          // ★ 기존 시트를 닫은 뒤 메모 시트 열기 (Future 반환/대기)
                          await HeadHubActions.openSheetExclusively((ctx) async {
                            return HeadMemo.openPanel(); // 내부에서 showModalBottomSheet 반환해야 함
                          });
                        },
                      ),
                      _DockAction(
                        icon: Icons.calendar_month_rounded,
                        label: '본사 달력',
                        color: const Color(0xFF43A047),
                        onTap: () async {
                          await _ctrl.reverse();
                          await HeadHubActions.openSheetExclusively((ctx) async {
                            return CompanyCalendarPage.showAsBottomSheet(ctx);
                          });
                        },
                      ),
                      _DockAction(
                        icon: Icons.how_to_reg_rounded,
                        label: '출·퇴근',
                        color: const Color(0xFF1565C0),
                        onTap: () async {
                          await _ctrl.reverse();
                          await HeadHubActions.openSheetExclusively((ctx) async {
                            return hr_att.AttendanceCalendar.showAsBottomSheet(ctx);
                          });
                        },
                      ),
                      _DockAction(
                        icon: Icons.free_breakfast_rounded,
                        label: '휴게 관리',
                        color: const Color(0xFF3949AB),
                        onTap: () async {
                          await _ctrl.reverse();
                          await HeadHubActions.openSheetExclusively((ctx) async {
                            return hr_break.BreakCalendar.showAsBottomSheet(ctx);
                          });
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),

        // ── 메인 버블 (글래스 링 + 회전 아이콘) ─────────────
        Positioned(
          left: _pos.dx,
          top:  _pos.dy,
          child: GestureDetector(
            onPanUpdate: (d) {
              setState(() {
                final next = Offset(_pos.dx + d.delta.dx, _pos.dy + d.delta.dy);
                _pos = _clampToScreen(next, screen, bottomInset);
              });
            },
            onPanEnd: (_) async {
              // 좌/우 엣지 스냅
              final snapX = (_pos.dx + _bubbleSize / 2) < screen.width / 2
                  ? 8.0
                  : screen.width - _bubbleSize - 8.0;
              setState(() => _pos = Offset(snapX, _pos.dy));
              await widget.onPosSave(_pos);
            },
            child: _GlassBubble(
              size: _bubbleSize,
              progress: _t.value,
              onTap: _toggleMenu,
            ),
          ),
        ),
      ],
    );
  }

  double _calcGap({required double avail, required int count}) {
    // avail: Dock 전체에 할당 가능한 폭(패딩 포함 X)
    // (avail - 좌우패딩 - 칩폭 합)을 간격으로 분배
    final minWidth = _dockHPad * 2 + count * _chip + (count - 1) * _gapMin;
    if (avail <= minWidth) return _gapMin;

    final maxWidth = _dockHPad * 2 + count * _chip + (count - 1) * _gapMax;
    if (avail >= maxWidth) return _gapMax;

    // 선형 보간
    final t = (avail - minWidth) / (maxWidth - minWidth);
    return _gapMin + (_gapMax - _gapMin) * t.clamp(0, 1);
  }

  Offset _clampToScreen(Offset raw, Size screen, double bottomInset) {
    final maxX = (screen.width  - _bubbleSize).clamp(0.0, double.infinity);
    final maxY = (screen.height - _bubbleSize - bottomInset).clamp(0.0, double.infinity);
    final dx = raw.dx.clamp(0.0, maxX);
    final dy = raw.dy.clamp(0.0, maxY);
    return Offset(dx, dy);
  }
}

// ───────────────────────────────────────────────────────────────
// 글래스 버블 (메인 트리거)
// ───────────────────────────────────────────────────────────────
class _GlassBubble extends StatelessWidget {
  final double size;
  final double progress; // 0~1
  final VoidCallback onTap;

  const _GlassBubble({
    required this.size,
    required this.progress,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Semantics(
      button: true,
      label: '빠른 실행',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  Colors.white.withOpacity(0.32),
                  Colors.white.withOpacity(0.08),
                ],
                center: Alignment.topLeft,
                radius: 1.2,
              ),
              border: Border.all(
                color: Colors.white.withOpacity(0.35),
                width: 1,
              ),
              boxShadow: const [BoxShadow(blurRadius: 18, color: Colors.black26, offset: Offset(0, 6))],
            ),
            child: Stack(
              fit: StackFit.expand,
              children: [
                // 내측 글로우 링
                Padding(
                  padding: const EdgeInsets.all(4),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white.withOpacity(0.15), width: 1),
                    ),
                  ),
                ),
                // 아이콘 (반바퀴 회전)
                Center(
                  child: Transform.rotate(
                    angle: progress * math.pi,
                    child: Icon(Icons.settings_rounded, color: cs.onSurface.withOpacity(0.9)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ───────────────────────────────────────────────────────────────
// 글래스 Dock 컨테이너 + 아이콘 Row
// ───────────────────────────────────────────────────────────────
class _GlassDock extends StatelessWidget {
  final double width;
  final double height;
  final double radius;
  final double hPad;
  final double vPad;
  final Widget child;

  const _GlassDock({
    required this.width,
    required this.height,
    required this.radius,
    required this.hPad,
    required this.vPad,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          width: width,
          height: height,
          padding: EdgeInsets.symmetric(horizontal: hPad, vertical: vPad),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(radius),
            color: cs.surface.withOpacity(0.60), // 반투명 글래스
            border: Border.all(color: Colors.white.withOpacity(0.35), width: 1),
            boxShadow: const [
              BoxShadow(blurRadius: 16, color: Colors.black26, offset: Offset(0, 8)),
            ],
          ),
          child: child,
        ),
      ),
    );
  }
}

class _DockRow extends StatelessWidget {
  final double innerWidth; // 패딩 제외한 Row의 가용 폭
  final double chip;
  final double iconSize;
  final List<_DockAction> actions;

  const _DockRow({
    required this.innerWidth,
    required this.chip,
    required this.iconSize,
    required this.actions,
  });

  @override
  Widget build(BuildContext context) {
    // Row가 정확히 innerWidth를 차지하도록 SizedBox로 감싸고,
    // 간격은 spaceBetween으로 균등 분배(반올림 오차로 인한 overflow 방지)
    return SizedBox(
      width: innerWidth,
      height: chip,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: actions
            .map((a) => _DockIconButton(
          size: chip,
          icon: a.icon,
          iconSize: iconSize,
          bg: a.color,
          tooltip: a.label,
          onTap: a.onTap,
        ))
            .toList(),
      ),
    );
  }
}

class _DockAction {
  final IconData icon;
  final String label;
  final Color color;
  final Future<void> Function() onTap; // ★ async 콜백을 안전하게 받기 위해 Future<void>로 명시
  _DockAction({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });
}

class _DockIconButton extends StatelessWidget {
  final double size;
  final IconData icon;
  final double iconSize;
  final Color bg;
  final String tooltip;
  final Future<void> Function() onTap; // ★ async 콜백

  const _DockIconButton({
    required this.size,
    required this.icon,
    required this.iconSize,
    required this.bg,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final on = Colors.white;
    return Semantics(
      button: true,
      label: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            // 여기서 Haptic 1회만, onTap 내부에선 중복 제거
            HapticFeedback.selectionClick();
            // 콜백은 async지만 InkWell 시그니처는 void Function() 이므로 그냥 실행만 하고 기다리진 않음
            onTap();
          },
          customBorder: const CircleBorder(),
          child: Tooltip(
            message: tooltip,
            child: Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                color: bg,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white.withOpacity(0.25), width: 1),
                boxShadow: const [BoxShadow(blurRadius: 10, color: Colors.black26, offset: Offset(0, 4))],
              ),
              alignment: Alignment.center,
              child: Icon(icon, color: on, size: iconSize),
            ),
          ),
        ),
      ),
    );
  }
}

// ───────────────────────────────────────────────────────────────
// 스프링 감쇠 곡선 (짧고 탄력 있게)
// ───────────────────────────────────────────────────────────────
class SpringCurve extends Curve {
  const SpringCurve();
  @override
  double transform(double t) {
    // 살짝 튀는 질감: overshoot을 억제한 감쇠 진동 형태
    // 0~1 입력 -> 0~1 출력
    // y = 1 - e^{-6t} * cos(10t)
    final e = math.exp(-6 * t);
    final c = math.cos(10 * t);
    final y = 1 - e * c;
    return y.clamp(0.0, 1.0);
  }
}
