import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../app/init/app_exit_service.dart';
import '../../../../app/init/app_navigator.dart';
import 'local_prefs_bottom_sheet.dart';
import 'sqlite_explorer_bottom_sheet.dart';

class DevQuickActions {
  DevQuickActions._();

  static GlobalKey<NavigatorState> get navigatorKey => AppNavigator.key;

  static final enabled = ValueNotifier<bool>(false);

  static const _kEnabledKey = 'dev_quick_actions_enabled_v1';
  static const _kBubbleXKey = 'dev_quick_actions_bubble_x_v1';
  static const _kBubbleYKey = 'dev_quick_actions_bubble_y_v1';

  static SharedPreferences? _prefs;
  static OverlayEntry? _entry;
  static bool _initialized = false;

  static bool _closing = false;
  static bool _opening = false;
  static Future<void>? _activeSheet;

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

  static Future<void> mountIfNeeded() async {
    if (!_initialized || _prefs == null) {
      await init();
    }
    if (enabled.value) _showOverlay();
  }

  static void setEnabled(bool value) => enabled.value = value;

  static void toggle() => enabled.value = !enabled.value;

  static BuildContext? _bestContext() {
    final state = navigatorKey.currentState;
    final overlayCtx = state?.overlay?.context;
    return overlayCtx ?? state?.context;
  }

  static Future<void> closeAnySheet() async {
    if (_closing) return;
    _closing = true;
    try {
      final ctx = _bestContext();
      if (ctx == null) return;

      final tracked = _activeSheet;
      if (tracked != null) {
        Navigator.of(ctx).maybePop();
        try {
          await tracked;
        } catch (_) {}
        await Future<void>.delayed(const Duration(milliseconds: 16));
        return;
      }

      final popped = await Navigator.of(ctx).maybePop();
      if (popped) {
        await Future<void>.delayed(const Duration(milliseconds: 220));
      }
    } finally {
      _closing = false;
    }
  }

  static Future<void> openSheetExclusively(
    Future<dynamic> Function(BuildContext ctx) openFn,
  ) async {
    if (_opening) return;
    _opening = true;
    try {
      await closeAnySheet();
      final ctx = _bestContext();
      if (ctx == null) return;

      final dynamic fut = openFn(ctx);
      if (fut is Future) {
        final Future<void> tracked = fut.then<void>((_) {});
        _activeSheet = tracked;
        try {
          await tracked;
        } finally {
          _activeSheet = null;
        }
      } else {
        await Future<void>.delayed(const Duration(milliseconds: 16));
      }
    } finally {
      _opening = false;
    }
  }

  static void _showOverlay() {
    if (_entry != null) return;
    final overlay = navigatorKey.currentState?.overlay;
    if (overlay == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _showOverlay());
      return;
    }
    _entry = OverlayEntry(
      builder: (_) => _DevBubble(
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

  static Offset _restorePos() {
    final dx = _prefs?.getDouble(_kBubbleXKey) ?? 12.0;
    final dy = _prefs?.getDouble(_kBubbleYKey) ?? 240.0;
    return Offset(dx, dy);
  }

  static Future<void> _savePos(Offset pos) async {
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.setDouble(_kBubbleXKey, pos.dx);
    await _prefs!.setDouble(_kBubbleYKey, pos.dy);
  }

  static Future<dynamic> showLocalPrefsSheet(BuildContext ctx) {
    return showModalBottomSheet(
      context: ctx,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const LocalPrefsBottomSheet(),
    );
  }

  static Future<dynamic> showSQLiteExplorerSheet(BuildContext ctx) {
    return SQLiteExplorerBottomSheet.showFullScreen(ctx);
  }
}

class _DevBubble extends StatefulWidget {
  final Offset initialPos;
  final Future<void> Function(Offset) onPosSave;

  const _DevBubble({required this.initialPos, required this.onPosSave});

  @override
  State<_DevBubble> createState() => _DevBubbleState();
}

class _DevBubbleState extends State<_DevBubble>
    with SingleTickerProviderStateMixin {
  static const double _bubbleSize = 56;
  static const double _iconSize = 22;
  static const double _chip = 44;
  static const double _dockHPad = 12;
  static const double _dockVPad = 8;
  static const double _gapMax = 20;
  static const double _gapMin = 10;
  static const double _dockRadius = 18;
  static const double _edgePad = 8;

  late Offset _pos;
  bool _clampedOnce = false;

  late final AnimationController _ctrl;
  late final Animation<double> _t;

  bool get _expanded => _ctrl.value > 0.001;

  @override
  void initState() {
    super.initState();
    _pos = widget.initialPos;
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 240));
    _t = CurvedAnimation(
      parent: _ctrl,
      curve: const _DevSpringCurve(),
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

    if (!_clampedOnce && screen != Size.zero) {
      _clampedOnce = true;
      _pos = _clampToScreen(_pos, screen, bottomInset);
    }

    final actions = <_DevDockAction>[
      _DevDockAction(
        icon: Icons.tune_rounded,
        label: '로컬 Prefs',
        color: const Color(0xFF1E88E5),
        onTap: () async {
          await _ctrl.reverse();
          await DevQuickActions.openSheetExclusively(
            (ctx) => DevQuickActions.showLocalPrefsSheet(ctx),
          );
        },
      ),
      _DevDockAction(
        icon: Icons.storage_rounded,
        label: 'SQLite',
        color: Colors.indigo,
        onTap: () async {
          await _ctrl.reverse();
          await DevQuickActions.openSheetExclusively(
            (ctx) => DevQuickActions.showSQLiteExplorerSheet(ctx),
          );
        },
      ),
      _DevDockAction(
        icon: Icons.power_settings_new_rounded,
        label: '앱 종료',
        color: Colors.redAccent,
        onTap: () async {
          await _ctrl.reverse();

          await DevQuickActions.closeAnySheet();

          final ctx = DevQuickActions._bestContext() ?? context;
          await AppExitService.exitApp(ctx);
        },
      ),
    ];

    final rightSpace = screen.width - (_pos.dx + _bubbleSize) - _edgePad;
    final leftSpace = _pos.dx - _edgePad;

    final count = actions.length;
    final minInnerWidth = count * _chip + (count - 1) * _gapMin;
    final neededAtMin = _dockHPad * 2 + minInnerWidth;

    final preferRight = rightSpace >= leftSpace;
    final canRight = rightSpace >= neededAtMin;
    final canLeft = leftSpace >= neededAtMin;
    final useRight = canRight || (!canLeft && preferRight);

    final avail =
        (useRight ? rightSpace : leftSpace).clamp(0.0, double.infinity);
    final gap = _calcGap(avail: avail, count: count);
    final innerWidth = (count * _chip + (count - 1) * gap).ceilToDouble();
    final dockWidth = (_dockHPad * 2 + innerWidth).ceilToDouble();
    final dockHeight = (_dockVPad * 2 + _chip).ceilToDouble();

    final dockLeft = useRight
        ? (_pos.dx + _bubbleSize + _edgePad)
        : (_pos.dx - dockWidth - _edgePad);
    final dockTop = _pos.dy + (_bubbleSize - dockHeight) / 2;

    return Stack(
      children: [
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
        Positioned(
          left: dockLeft,
          top: dockTop,
          child: IgnorePointer(
            ignoring: !_expanded,
            child: Transform.scale(
              scale: 0.96 + 0.04 * _t.value,
              alignment:
                  useRight ? Alignment.centerLeft : Alignment.centerRight,
              child: Opacity(
                opacity: _t.value,
                child: _DevGlassDock(
                  width: dockWidth,
                  height: dockHeight,
                  radius: _dockRadius,
                  hPad: _dockHPad,
                  vPad: _dockVPad,
                  child: _DevDockRow(
                    innerWidth: innerWidth,
                    chip: _chip,
                    iconSize: _iconSize,
                    actions: actions,
                  ),
                ),
              ),
            ),
          ),
        ),
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
              final snapX = (_pos.dx + _bubbleSize / 2) < screen.width / 2
                  ? 8.0
                  : screen.width - _bubbleSize - 8.0;
              setState(() => _pos = Offset(snapX, _pos.dy));
              await widget.onPosSave(_pos);
            },
            child: _DevGlassBubble(
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
    final minWidth = _DevBubbleState._dockHPad * 2 +
        count * _DevBubbleState._chip +
        (count - 1) * _DevBubbleState._gapMin;
    if (avail <= minWidth) return _DevBubbleState._gapMin;

    final maxWidth = _DevBubbleState._dockHPad * 2 +
        count * _DevBubbleState._chip +
        (count - 1) * _DevBubbleState._gapMax;
    if (avail >= maxWidth) return _DevBubbleState._gapMax;

    final t = (avail - minWidth) / (maxWidth - minWidth);
    return _DevBubbleState._gapMin +
        (_DevBubbleState._gapMax - _DevBubbleState._gapMin) * t.clamp(0, 1);
  }

  Offset _clampToScreen(Offset raw, Size screen, double bottomInset) {
    final maxX = (screen.width - _DevBubbleState._bubbleSize)
        .clamp(0.0, double.infinity);
    final maxY = (screen.height - _DevBubbleState._bubbleSize - bottomInset)
        .clamp(0.0, double.infinity);
    final dx = raw.dx.clamp(0.0, maxX);
    final dy = raw.dy.clamp(0.0, maxY);
    return Offset(dx, dy);
  }
}

class _DevGlassBubble extends StatelessWidget {
  final double size;
  final double progress;
  final VoidCallback onTap;

  const _DevGlassBubble({
    required this.size,
    required this.progress,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      label: '빠른 실행(개발)',
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
              border:
                  Border.all(color: Colors.white.withOpacity(0.35), width: 1),
              boxShadow: const [
                BoxShadow(
                  blurRadius: 18,
                  color: Colors.black26,
                  offset: Offset(0, 6),
                ),
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
                      Icons.developer_mode_rounded,
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

class _DevGlassDock extends StatelessWidget {
  final double width;
  final double height;
  final double radius;
  final double hPad;
  final double vPad;
  final Widget child;

  const _DevGlassDock({
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
              BoxShadow(
                blurRadius: 16,
                color: Colors.black26,
                offset: Offset(0, 8),
              ),
            ],
          ),
          child: child,
        ),
      ),
    );
  }
}

class _DevDockRow extends StatelessWidget {
  final double innerWidth;
  final double chip;
  final double iconSize;
  final List<_DevDockAction> actions;

  const _DevDockRow({
    required this.innerWidth,
    required this.chip,
    required this.iconSize,
    required this.actions,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: innerWidth,
      height: chip,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: actions
            .map(
              (a) => _DevDockIconButton(
                size: chip,
                icon: a.icon,
                iconSize: iconSize,
                bg: a.color,
                tooltip: a.label,
                onTap: a.onTap,
              ),
            )
            .toList(),
      ),
    );
  }
}

class _DevDockAction {
  final IconData icon;
  final String label;
  final Color color;
  final Future<void> Function() onTap;

  _DevDockAction({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });
}

class _DevDockIconButton extends StatelessWidget {
  final double size;
  final IconData icon;
  final double iconSize;
  final Color bg;
  final String tooltip;
  final Future<void> Function() onTap;

  const _DevDockIconButton({
    required this.size,
    required this.icon,
    required this.iconSize,
    required this.bg,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
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
                border: Border.all(
                  color: Colors.white.withOpacity(0.25),
                  width: 1,
                ),
                boxShadow: const [
                  BoxShadow(
                    blurRadius: 10,
                    color: Colors.black26,
                    offset: Offset(0, 4),
                  ),
                ],
              ),
              alignment: Alignment.center,
              child: Icon(icon, color: Colors.white, size: iconSize),
            ),
          ),
        ),
      ),
    );
  }
}

class _DevSpringCurve extends Curve {
  const _DevSpringCurve();

  @override
  double transform(double t) {
    final e = math.exp(-6 * t);
    final c = math.cos(10 * t);
    final y = 1 - e * c;
    return y.clamp(0.0, 1.0);
  }
}
