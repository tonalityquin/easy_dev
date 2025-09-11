// lib/screens/commute_package/commute_outside_package/floating_controls/commute_outside_floating.dart
//
// 출근(Clock-in) 성공 후 표시되는 플로팅 액션 버블.
// - 탭 시: 기어 회전 + 미니 버튼 2개(휴식, 퇴근) 가로 펼침/접힘
// - 버튼 동작: 주입된 콜백(onBreak, onClockOut)을 그대로 호출
//
// 위치/상태는 SharedPreferences로 영속화(버블 좌표 + on/off).
// overlay는 AppNavigator.navigatorKey의 overlay를 사용.
//
// 사용법:
//   1) 앱 시작 시:
///        await CommuteOutsideFloating.init();         // pref 로드 + 리스너 세팅
///        // 첫 프레임 후
///        CommuteOutsideFloating.mountIfNeeded();      // enabled == true 면 오버레이 부착
//   2) 출근 성공 시:
///        CommuteOutsideFloating.configure(
///          onBreak: () async { ... },      // 기존 휴식 로직
///          onClockOut: () async { ... },   // 기존 퇴근 로직
///        );
///        await CommuteOutsideFloating.setEnabled(true); // on + 저장 + 오버레이
//   3) 퇴근 시:
///        await CommuteOutsideFloating.setEnabled(false); // off + 저장 + 오버레이 제거
//
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../utils/app_navigator.dart';

class CommuteOutsideFloating {
  CommuteOutsideFloating._();

  /// App 전체에서 사용하는 navigatorKey
  static GlobalKey<NavigatorState> get navigatorKey => AppNavigator.key;

  /// on/off 상태 (영속화 대상)
  static final enabled = ValueNotifier<bool>(false);

  // 주입되는 버튼 액션
  static Future<void> Function()? _onBreak;
  static Future<void> Function()? _onClockOut;

  /// 콜백 설정
  static void configure({
    required Future<void> Function()? onBreak,
    required Future<void> Function()? onClockOut,
  }) {
    _onBreak = onBreak;
    _onClockOut = onClockOut;
  }

  static OverlayEntry? _entry;
  static SharedPreferences? _prefs;

  // pref 키
  static const _kEnabledKey = 'co_floating_enabled_v1';
  static const _kBubbleX = 'co_floating_bubble_x_v1';
  static const _kBubbleY = 'co_floating_bubble_y_v1';

  /// 앱 시작 시 1회
  static Future<void> init() async {
    _prefs ??= await SharedPreferences.getInstance();

    // 저장된 on/off 복원
    enabled.value = _prefs!.getBool(_kEnabledKey) ?? false;

    // enabled 변경 시 저장 + 오버레이 토글
    enabled.addListener(() async {
      await _prefs?.setBool(_kEnabledKey, enabled.value);
      if (enabled.value) {
        _showOverlay();
      } else {
        _hideOverlay();
      }
    });
  }

  /// 외부에서 on/off 제어 (저장/토글은 listener가 처리)
  static Future<void> setEnabled(bool v) async {
    enabled.value = v;
  }

  /// 첫 프레임 이후 오버레이 필요 시 부착
  static void mountIfNeeded() {
    if (enabled.value) _showOverlay();
  }

  static void _showOverlay() {
    if (_entry != null) return;
    final overlay = navigatorKey.currentState?.overlay;
    if (overlay == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _showOverlay());
      return;
    }
    _entry = OverlayEntry(
      builder: (_) => _CommuteFloatingBubble(
        onBreak: () async {
          if (_onBreak != null) {
            await _onBreak!.call();
          } else {
            _toast('휴식 동작이 설정되지 않았습니다.');
          }
        },
        onClockOut: () async {
          if (_onClockOut != null) {
            await _onClockOut!.call();
          } else {
            _toast('퇴근 동작이 설정되지 않았습니다.');
          }
        },
        loadPos: _restoreBubblePos,
        savePos: _saveBubblePos,
      ),
    );
    overlay.insert(_entry!);
  }

  static void _hideOverlay() {
    _entry?.remove();
    _entry = null;
  }

  static Offset _restoreBubblePos() {
    final dx = _prefs?.getDouble(_kBubbleX) ?? 12.0;
    final dy = _prefs?.getDouble(_kBubbleY) ?? 200.0;
    return Offset(dx, dy);
  }

  static Future<void> _saveBubblePos(Offset pos) async {
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.setDouble(_kBubbleX, pos.dx);
    await _prefs!.setDouble(_kBubbleY, pos.dy);
  }

  static void _toast(String msg) {
    final ctx = navigatorKey.currentState?.context;
    if (ctx == null) return;
    ScaffoldMessenger.of(ctx).showSnackBar(
      SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating),
    );
  }
}

/// 내부 버블 위젯
class _CommuteFloatingBubble extends StatefulWidget {
  const _CommuteFloatingBubble({
    required this.onBreak,
    required this.onClockOut,
    required this.loadPos,
    required this.savePos,
  });

  final Future<void> Function() onBreak;
  final Future<void> Function() onClockOut;
  final Offset Function() loadPos;
  final Future<void> Function(Offset) savePos;

  @override
  State<_CommuteFloatingBubble> createState() => _CommuteFloatingBubbleState();
}

class _CommuteFloatingBubbleState extends State<_CommuteFloatingBubble>
    with SingleTickerProviderStateMixin {
  static const double _bubbleSize = 56;
  static const double _miniSize = 44;
  static const double _gap = 60;

  late Offset _pos;
  bool _clampedOnce = false;

  late final AnimationController _ctrl;
  late final Animation<double> _t; // 0~1

  bool get _expanded => _t.value > 0.001;

  @override
  void initState() {
    super.initState();
    _pos = widget.loadPos();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 220));
    _t = CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic, reverseCurve: Curves.easeInCubic);
    _ctrl.addListener(() => setState(() {}));
    _ctrl.addStatusListener((_) => setState(() {}));
  }

  @override
    void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _toggle() {
    if (_expanded) {
      _ctrl.reverse();
    } else {
      _ctrl.forward();
    }
    HapticFeedback.selectionClick();
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.maybeOf(context);
    final screen = media?.size ?? Size.zero;
    final bottomInset = media?.padding.bottom ?? 0;
    final cs = Theme.of(context).colorScheme;

    if (!_clampedOnce && screen != Size.zero) {
      _clampedOnce = true;
      _pos = _clamp(_pos, screen, bottomInset);
    }

    // 좌/우에 따라 버튼이 가로로 펼쳐짐
    final isLeft = (_pos.dx + _bubbleSize / 2) < (screen.width / 2);
    final dir = isLeft ? 1.0 : -1.0;
    final oBreak = Offset(dir * _gap * _t.value, 0);
    final oOut = Offset(dir * (_gap * 2) * _t.value, 0);

    return Stack(
      children: [
        if (_expanded)
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _toggle,
            ),
          ),

        // 미니: 휴식
        Positioned(
          left: _pos.dx + (_bubbleSize - _miniSize) / 2 + oBreak.dx,
          top: _pos.dy + (_bubbleSize - _miniSize) / 2 + oBreak.dy,
          child: IgnorePointer(
            ignoring: !_expanded,
            child: Opacity(
              opacity: _t.value,
              child: _MiniButton(
                size: _miniSize,
                color: cs.tertiaryContainer,
                icon: Icons.airline_seat_individual_suite_rounded,
                iconColor: cs.onTertiaryContainer,
                label: '휴식',
                onTap: () async {
                  HapticFeedback.selectionClick();
                  await _ctrl.reverse();
                  await widget.onBreak();
                },
              ),
            ),
          ),
        ),

        // 미니: 퇴근
        Positioned(
          left: _pos.dx + (_bubbleSize - _miniSize) / 2 + oOut.dx,
          top: _pos.dy + (_bubbleSize - _miniSize) / 2 + oOut.dy,
          child: IgnorePointer(
            ignoring: !_expanded,
            child: Opacity(
              opacity: _t.value,
              child: _MiniButton(
                size: _miniSize,
                color: cs.secondaryContainer,
                icon: Icons.logout_rounded,
                iconColor: cs.onSecondaryContainer,
                label: '퇴근',
                onTap: () async {
                  HapticFeedback.selectionClick();
                  await _ctrl.reverse();
                  await widget.onClockOut();
                },
              ),
            ),
          ),
        ),

        // 메인 버블(드래그 + 토글)
        Positioned(
          left: _pos.dx,
          top: _pos.dy,
          child: GestureDetector(
            onPanUpdate: (d) {
              setState(() {
                final next = Offset(_pos.dx + d.delta.dx, _pos.dy + d.delta.dy);
                _pos = _clamp(next, screen, bottomInset);
              });
            },
            onPanEnd: (_) async {
              final snapX = (_pos.dx + _bubbleSize / 2) < screen.width / 2
                  ? 8.0
                  : screen.width - _bubbleSize - 8.0;
              setState(() => _pos = Offset(snapX, _pos.dy));
              await widget.savePos(_pos);
            },
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: _toggle,
                customBorder: const CircleBorder(),
                child: AnimatedBuilder(
                  animation: _t,
                  builder: (_, __) {
                    return Container(
                      width: _bubbleSize,
                      height: _bubbleSize,
                      decoration: BoxDecoration(
                        color: cs.primary.withOpacity(0.5),
                        shape: BoxShape.circle,
                        border: Border.all(color: cs.onSurface.withOpacity(.08)),
                        boxShadow: const [BoxShadow(blurRadius: 10, color: Colors.black26)],
                      ),
                      alignment: Alignment.center,
                      child: Transform.rotate(
                        angle: _t.value * math.pi, // 0 → π
                        child: Icon(Icons.settings_rounded, color: Colors.white.withOpacity(0.95)),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Offset _clamp(Offset raw, Size screen, double bottomInset) {
    const s = _CommuteFloatingBubbleState._bubbleSize;
    final maxX = (screen.width - s).clamp(0.0, double.infinity);
    final maxY = (screen.height - s - bottomInset).clamp(0.0, double.infinity);
    return Offset(
      raw.dx.clamp(0.0, maxX),
      raw.dy.clamp(0.0, maxY),
    );
  }
}

class _MiniButton extends StatelessWidget {
  final double size;
  final Color color;
  final IconData icon;
  final Color iconColor;
  final String label;
  final VoidCallback onTap;

  const _MiniButton({
    required this.size,
    required this.color,
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            customBorder: const CircleBorder(),
            child: Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.black.withOpacity(.06)),
                boxShadow: const [BoxShadow(blurRadius: 8, color: Colors.black12)],
              ),
              alignment: Alignment.center,
              child: Icon(icon, color: iconColor),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.6),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(label, style: const TextStyle(color: Colors.white, fontSize: 11)),
        ),
      ],
    );
  }
}
