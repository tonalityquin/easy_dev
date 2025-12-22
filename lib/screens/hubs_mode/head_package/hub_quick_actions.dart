// lib/screens/hubs_mode/head_package/hub_quick_actions.dart
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
import '../head_package/mgmt_package/field.dart' as mgmt;
import '../head_package/mgmt_package/statistics.dart' as mgmt_stats;
import '../head_package/roadmap_bottom_sheet.dart';
import '../head_package/head_tutorials.dart';

/// 본사 허브용 퀵 액션 플로팅 버블(오버레이)
/// - Dock: 버블 옆(가로) 위치에 붙이고, 아이콘은 세로로 쌓음(아이콘 많아도 안전)
/// - 내부는 constraints 기반으로 스크롤 자동 전환(오버플로우 방지)
/// - 단일 인스턴스 바텀시트 관리(연타/중복 오픈 방지)
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

  /// overlay 기반에서 push가 필요할 때 사용
  static BuildContext? currentContext() => _bestContext();

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
        await Future<void>.delayed(const Duration(milliseconds: 220));
      }
    } finally {
      _closing = false;
    }
  }

  /// (공용) 기존 시트를 닫은 뒤, 주어진 함수를 통해 “새 시트”를 연다.
  /// - 빠른 연타/연속 호출에 대비해 간단한 뮤텍스(_opening)로 직렬화
  /// - openFn은 showModalBottomSheet가 반환하는 Future<T?>를 반환해야 함(권장)
  static Future<T?> openSheetExclusively<T>(
      Future<T?> Function(BuildContext ctx) openFn,
      ) async {
    if (_opening) return null;
    _opening = true;
    try {
      await closeAnySheet();
      final ctx = _bestContext();
      if (ctx == null) return null;

      final Future<T?> fut = openFn(ctx);

      final Future<void> tracked = fut.then<void>((_) {});
      _activeSheet = tracked;

      try {
        final T? result = await fut; // 시트 종료까지 대기(결과값 수신)
        return result;
      } finally {
        _activeSheet = null;
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
  static const double _bubbleSize = 56; // 메인 FAB
  static const double _iconSize = 22; // Dock 안 아이콘
  static const double _chip = 44; // Dock 아이콘 터치 타깃(원칩)
  static const double _dockHPad = 12; // Dock 좌우 패딩
  static const double _dockVPad = 8; // Dock 상하 패딩
  static const double _vGap = 10; // 세로 간격
  static const double _dockRadius = 18; // Dock 코너
  static const double _edgePad = 8; // 버블-도크 사이 여백
  static const double _screenPad = 8; // 화면 가장자리 안전 여백

  late Offset _pos;
  bool _clampedOnce = false;

  late final AnimationController _ctrl;
  late final Animation<double> _t; // 0→1 전개 비율(모션)
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
      curve: const SpringCurve(),
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

  List<_DockAction> _buildActions(ColorScheme cs) {
    return <_DockAction>[
      _DockAction(
        icon: Icons.sticky_note_2_rounded,
        label: '메모',
        color: cs.secondaryContainer,
        onTap: () async {
          await _ctrl.reverse();
          await HeadHubActions.openSheetExclusively<dynamic>((ctx) {
            // 주의: HeadMemo.openPanel()이 "시트가 닫힐 때 완료되는 Future"를 반환하지 않으면
            // 단일 인스턴스 추적이 약해질 수 있습니다(오버플로우와는 무관).
            return HeadMemo.openPanel();
          });
        },
      ),
      _DockAction(
        icon: Icons.calendar_month_rounded,
        label: '본사 달력',
        color: const Color(0xFF43A047),
        onTap: () async {
          await _ctrl.reverse();
          await HeadHubActions.openSheetExclusively<dynamic>((ctx) {
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
          await HeadHubActions.openSheetExclusively<dynamic>((ctx) {
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
          await HeadHubActions.openSheetExclusively<dynamic>((ctx) {
            return hr_break.BreakCalendar.showAsBottomSheet(ctx);
          });
        },
      ),
      _DockAction(
        icon: Icons.map_rounded,
        label: '근무지 현황',
        color: const Color(0xFF00897B),
        onTap: () async {
          await _ctrl.reverse();
          await HeadHubActions.openSheetExclusively<dynamic>((ctx) {
            return mgmt.Field.showAsBottomSheet(ctx);
          });
        },
      ),
      _DockAction(
        icon: Icons.stacked_line_chart_rounded,
        label: '통계 비교',
        color: const Color(0xFF6A1B9A),
        onTap: () async {
          await _ctrl.reverse();
          await HeadHubActions.openSheetExclusively<dynamic>((ctx) {
            return mgmt_stats.Statistics.showAsBottomSheet(ctx);
          });
        },
      ),
      _DockAction(
        icon: Icons.edit_note_rounded,
        label: '향후 로드맵',
        color: const Color(0xFF7E57C2),
        onTap: () async {
          await _ctrl.reverse();
          await HeadHubActions.openSheetExclusively<dynamic>((ctx) {
            return showModalBottomSheet<dynamic>(
              context: ctx,
              isScrollControlled: true,
              useSafeArea: true,
              backgroundColor: Colors.transparent,
              builder: (_) => const RoadmapBottomSheet(),
            );
          });
        },
      ),
      _DockAction(
        icon: Icons.menu_book_rounded,
        label: '튜토리얼',
        color: const Color(0xFF00695C),
        onTap: () async {
          await _ctrl.reverse();

          // 1) 선택 바텀시트는 “시트”로 취급해 단일 인스턴스 관리
          final TutorialItem? selected =
          await HeadHubActions.openSheetExclusively<TutorialItem>((ctx) {
            return HeadTutorials.showPickerBottomSheet(ctx);
          });

          // 2) 선택 후에는 PDF 뷰어(일반 push)
          final ctx2 = HeadHubActions.currentContext();
          if (selected != null && ctx2 != null) {
            await TutorialPdfViewer.open(ctx2, selected);
          }
        },
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.maybeOf(context);
    final screen = media?.size ?? Size.zero;
    final topInset = media?.padding.top ?? 0;
    final bottomInset = media?.padding.bottom ?? 0;
    final cs = Theme.of(context).colorScheme;

    if (!_clampedOnce && screen != Size.zero) {
      _clampedOnce = true;
      _pos = _clampToScreen(_pos, screen, bottomInset);
    }

    final actions = _buildActions(cs);
    final count = actions.length;

    // Dock 폭: 한 칩(원형 버튼)이 안정적으로 들어가도록 여유를 둠(픽셀 라운딩 안전)
    final dockWidth = (_dockHPad * 2 + _chip + 4);

    // Dock 높이(자연 높이)
    final naturalDockHeight = (_dockVPad * 2 + count * _chip + (count - 1) * _vGap);

    // 화면 내에서 유지 가능한 최대 높이(넘으면 내부 스크롤로 처리)
    final safeTop = topInset + _screenPad;
    final safeBottom = bottomInset + _screenPad;
    final maxDockHeight =
    (screen.height - safeTop - safeBottom).clamp(0.0, double.infinity);

    final dockHeight = math.min(naturalDockHeight, maxDockHeight);

    // 좌/우 가용폭 계산
    final rightSpace = screen.width - (_pos.dx + _bubbleSize) - _edgePad - _screenPad;
    final leftSpace = _pos.dx - _edgePad - _screenPad;

    final preferRight = rightSpace >= leftSpace;
    final canRight = rightSpace >= dockWidth;
    final canLeft = leftSpace >= dockWidth;
    final useRight = canRight || (!canLeft && preferRight);

    // Dock 위치 계산:
    // - 첫 아이콘(리스트 0번째)이 버블 중앙 높이 근처에 오도록 top을 계산한 뒤 화면 내 clamp
    final bubbleCenterY = _pos.dy + _bubbleSize / 2;
    final dockTopCandidate = bubbleCenterY - (_dockVPad + _chip / 2);

    final maxTop = screen.height - safeBottom - dockHeight;
    final dockTop = dockTopCandidate.clamp(
      safeTop,
      maxTop >= safeTop ? maxTop : safeTop,
    );

    double dockLeft = useRight
        ? (_pos.dx + _bubbleSize + _edgePad)
        : (_pos.dx - dockWidth - _edgePad);

    // 화면 밖으로 나가지 않도록 최종 clamp
    dockLeft = dockLeft.clamp(
      _screenPad,
      (screen.width - dockWidth - _screenPad).clamp(_screenPad, double.infinity),
    );

    return Stack(
      children: [
        // ── Dim/Scrim + 터치 닫기 ─────────────────────────
        if (_expanded)
          Positioned.fill(
            child: GestureDetector(
              onTap: _toggleMenu,
              behavior: HitTestBehavior.opaque,
              child: AnimatedOpacity(
                opacity: 0.04 * _t.value,
                duration: const Duration(milliseconds: 120),
                child: const ColoredBox(color: Colors.black),
              ),
            ),
          ),

        // ── 글래스 Dock (세로 리스트, constraints 기반 자동 스크롤) ─────
        Positioned(
          left: dockLeft,
          top: dockTop,
          child: IgnorePointer(
            ignoring: !_expanded,
            child: Transform.scale(
              scale: 0.96 + 0.04 * _t.value,
              alignment: useRight ? Alignment.topLeft : Alignment.topRight,
              child: Opacity(
                opacity: _t.value,
                child: _GlassDock(
                  width: dockWidth,
                  height: dockHeight,
                  radius: _dockRadius,
                  hPad: _dockHPad,
                  vPad: _dockVPad,
                  child: _DockColumn(
                    chip: _chip,
                    iconSize: _iconSize,
                    gap: _vGap,
                    actions: actions,
                  ),
                ),
              ),
            ),
          ),
        ),

        // ── 메인 버블 ────────────────────────────────────
        Positioned(
          left: _pos.dx,
          top: _pos.dy,
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

  Offset _clampToScreen(Offset raw, Size screen, double bottomInset) {
    final maxX = (screen.width - _bubbleSize).clamp(0.0, double.infinity);
    final maxY =
    (screen.height - _bubbleSize - bottomInset).clamp(0.0, double.infinity);
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
              boxShadow: const [
                BoxShadow(
                  blurRadius: 18,
                  color: Colors.black26,
                  offset: Offset(0, 6),
                )
              ],
            ),
            child: Stack(
              fit: StackFit.expand,
              children: [
                Padding(
                  padding: const EdgeInsets.all(4),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.white.withOpacity(0.15),
                        width: 1,
                      ),
                    ),
                  ),
                ),
                Center(
                  child: Transform.rotate(
                    angle: progress * math.pi,
                    child: Icon(
                      Icons.settings_rounded,
                      color: cs.onSurface.withOpacity(0.9),
                    ),
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
// 글래스 Dock 컨테이너 + 아이콘 Column/List
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
            color: cs.surface.withOpacity(0.60),
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

/// 핵심 수정 포인트:
/// - 부모가 "스크롤 여부"를 계산하지 않음(라운딩/패딩 때문에 1~2px 오차 발생 가능)
/// - LayoutBuilder로 실제 constraints.maxHeight를 받고, 필요한 높이와 비교해
///   넘치면 ListView(스크롤), 아니면 Column(고정)으로 안전하게 전환
class _DockColumn extends StatelessWidget {
  final double chip;
  final double iconSize;
  final double gap;
  final List<_DockAction> actions;

  const _DockColumn({
    required this.chip,
    required this.iconSize,
    required this.gap,
    required this.actions,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxH = constraints.maxHeight;
        final neededH =
            actions.length * chip + (actions.length - 1) * gap;

        // 1~2px 라운딩 오차까지 흡수하기 위해 여유를 둠
        final useScroll = neededH > (maxH - 1.0);

        if (useScroll) {
          return ListView.separated(
            padding: EdgeInsets.zero,
            physics: const ClampingScrollPhysics(),
            itemCount: actions.length,
            separatorBuilder: (_, __) => SizedBox(height: gap),
            itemBuilder: (_, i) {
              final a = actions[i];
              return _DockIconButton(
                size: chip,
                icon: a.icon,
                iconSize: iconSize,
                bg: a.color,
                tooltip: a.label,
                onTap: a.onTap,
              );
            },
          );
        }

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (int i = 0; i < actions.length; i++) ...[
              _DockIconButton(
                size: chip,
                icon: actions[i].icon,
                iconSize: iconSize,
                bg: actions[i].color,
                tooltip: actions[i].label,
                onTap: actions[i].onTap,
              ),
              if (i != actions.length - 1) SizedBox(height: gap),
            ],
          ],
        );
      },
    );
  }
}

class _DockAction {
  final IconData icon;
  final String label;
  final Color color;
  final Future<void> Function() onTap;

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
  final Future<void> Function() onTap;

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
            HapticFeedback.selectionClick();
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
                boxShadow: const [
                  BoxShadow(blurRadius: 10, color: Colors.black26, offset: Offset(0, 4))
                ],
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
    final e = math.exp(-6 * t);
    final c = math.cos(10 * t);
    final y = 1 - e * c;
    return y.clamp(0.0, 1.0);
  }
}
