import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../app/init/app_exit_service.dart';
import '../../../../app/init/app_navigator.dart';
import '../../application/debug_session_controller.dart';
import '../../presentation/debug_caution_surface.dart';
import '../../../selector/application/dev_auth.dart';
import 'local_prefs_bottom_sheet.dart';
import 'sqlite_explorer_bottom_sheet.dart';

class DevQuickActions {
  DevQuickActions._();

  static GlobalKey<NavigatorState> get navigatorKey => AppNavigator.key;
  static ValueListenable<bool> get enabled => DevAuth.devModeEnabled;

  static const _kSideKey = 'dev_quick_actions_side_v2';
  static const _kYKey = 'dev_quick_actions_y_v2';
  static const _legacyEnabledKey = 'dev_quick_actions_enabled_v1';
  static const _legacyYKey = 'dev_quick_actions_bubble_y_v1';

  static SharedPreferences? _prefs;
  static OverlayEntry? _entry;
  static bool _initialized = false;
  static bool _opening = false;
  static bool _closing = false;
  static Future<void>? _activeSurface;

  static Future<void> init() async {
    if (_initialized) return;
    _prefs ??= await SharedPreferences.getInstance();
    if (!_prefs!.containsKey(_kYKey)) {
      final legacyY = _prefs!.getDouble(_legacyYKey);
      if (legacyY != null) await _prefs!.setDouble(_kYKey, legacyY);
    }
    await _prefs!.remove(_legacyEnabledKey);
    await DebugSessionController.initialize();
    DevAuth.devModeEnabled.addListener(_handleSessionChange);
    _initialized = true;
    if (DevAuth.devModeEnabled.value) {
      _showOverlay();
    }
  }

  static void _handleSessionChange() {
    if (DevAuth.devModeEnabled.value) {
      _showOverlay();
    } else {
      _hideOverlay();
    }
  }

  static Future<void> mountIfNeeded() async {
    if (!_initialized || _prefs == null) {
      await init();
    }
    if (DevAuth.devModeEnabled.value) {
      _showOverlay();
    }
  }

  static Future<void> enableDeveloperMode({String source = 'terminal'}) async {
    if (!_initialized || _prefs == null) {
      await init();
    }
    await DebugSessionController.enable(source: source);
    await mountIfNeeded();
  }

  static Future<void> disableDeveloperMode({String source = 'developer_tools'}) async {
    await DebugSessionController.disable(source: source);
  }

  static void unmount() => _hideOverlay();

  static BuildContext? _bestContext() {
    final state = navigatorKey.currentState;
    return state?.overlay?.context ?? state?.context;
  }

  static Future<void> closeAnySheet() async {
    if (_closing) return;
    final tracked = _activeSurface;
    if (tracked == null) return;
    _closing = true;
    try {
      final ctx = _bestContext();
      if (ctx == null) return;
      Navigator.of(ctx, rootNavigator: true).maybePop();
      try {
        await tracked;
      } catch (_) {}
    } finally {
      _closing = false;
    }
  }

  static Future<void> openSheetExclusively(
    Future<dynamic> Function(BuildContext context) open,
  ) async {
    if (_opening) return;
    _opening = true;
    try {
      await closeAnySheet();
      final ctx = _bestContext();
      if (ctx == null) return;
      final dynamic result = open(ctx);
      if (result is Future) {
        final tracked = result.then<void>((_) {});
        _activeSurface = tracked;
        try {
          await tracked;
        } finally {
          _activeSurface = null;
        }
      }
    } finally {
      _opening = false;
    }
  }

  static Future<dynamic> showLocalPrefsSheet(BuildContext context) {
    DebugSessionController.record(
      'developer_tool_open',
      source: 'developer_quick_actions',
      meta: const <String, Object?>{'tool': 'shared_preferences'},
    );
    return showModalBottomSheet<dynamic>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const LocalPrefsBottomSheet(),
    );
  }

  static Future<dynamic> showSQLiteExplorerSheet(BuildContext context) {
    DebugSessionController.record(
      'developer_tool_open',
      source: 'developer_quick_actions',
      meta: const <String, Object?>{'tool': 'sqlite'},
    );
    return SQLiteExplorerBottomSheet.showFullScreen<dynamic>(context);
  }

  static void _showOverlay() {
    if (_entry != null) return;
    final overlay = navigatorKey.currentState?.overlay;
    if (overlay == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _showOverlay());
      return;
    }
    _entry = OverlayEntry(
      builder: (_) => _DebugLauncher(
        initialSide: _restoreSide(),
        initialY: _restoreY(),
        onPositionSave: _savePosition,
      ),
    );
    overlay.insert(_entry!);
  }

  static void _hideOverlay() {
    _entry?.remove();
    _entry = null;
  }

  static _DebugEdgeSide _restoreSide() {
    final value = _prefs?.getString(_kSideKey);
    return value == 'right' ? _DebugEdgeSide.right : _DebugEdgeSide.left;
  }

  static double _restoreY() => _prefs?.getDouble(_kYKey) ?? 240.0;

  static Future<void> _savePosition(_DebugEdgeSide side, double y) async {
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.setString(
      _kSideKey,
      side == _DebugEdgeSide.right ? 'right' : 'left',
    );
    await _prefs!.setDouble(_kYKey, y);
  }
}

enum _DebugEdgeSide { left, right }

class _DebugLauncher extends StatefulWidget {
  const _DebugLauncher({
    required this.initialSide,
    required this.initialY,
    required this.onPositionSave,
  });

  final _DebugEdgeSide initialSide;
  final double initialY;
  final Future<void> Function(_DebugEdgeSide side, double y) onPositionSave;

  @override
  State<_DebugLauncher> createState() => _DebugLauncherState();
}

class _DebugLauncherState extends State<_DebugLauncher>
    with TickerProviderStateMixin {
  static const double _launcherWidth = 96;
  static const double _launcherHeight = 42;
  static const double _edge = 8;

  late _DebugEdgeSide _side;
  late double _y;
  late AnimationController _paletteController;
  late Animation<double> _paletteAnimation;
  double _dragX = 0;
  bool _ending = false;
  bool _reduceMotion = false;

  bool get _expanded => _paletteController.value > 0.001;

  @override
  void initState() {
    super.initState();
    _side = widget.initialSide;
    _y = widget.initialY;
    _paletteController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 240),
    );
    _paletteAnimation = CurvedAnimation(
      parent: _paletteController,
      curve: const _DebugSpringCurve(),
      reverseCurve: Curves.easeInCubic,
    )..addListener(() {
        if (mounted) setState(() {});
      });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.of(context).disableAnimations;
    final screen = MediaQuery.of(context).size;
    final bottomInset = MediaQuery.of(context).padding.bottom;
    _y = _clampY(_y, screen.height, bottomInset);
  }

  @override
  void dispose() {
    _paletteController.dispose();
    super.dispose();
  }

  Future<void> _setExpanded(bool value) async {
    HapticFeedback.lightImpact();
    if (_reduceMotion) {
      _paletteController.value = value ? 1 : 0;
      return;
    }
    if (value) {
      await _paletteController.forward();
    } else {
      await _paletteController.reverse();
    }
  }

  Future<void> _openPrefs() async {
    await _setExpanded(false);
    await DevQuickActions.openSheetExclusively(
      (context) => DevQuickActions.showLocalPrefsSheet(context),
    );
  }

  Future<void> _openSQLite() async {
    await _setExpanded(false);
    await DevQuickActions.openSheetExclusively(
      (context) => DevQuickActions.showSQLiteExplorerSheet(context),
    );
  }

  Future<void> _showStatus() async {
    await _setExpanded(false);
    final ctx = DevQuickActions._bestContext();
    if (ctx == null) return;
    await DebugSessionController.showStatus(
      ctx,
      source: 'developer_quick_actions',
      description: <String>[
        'DEBUG session: ACTIVE',
        'Launcher side: ${_side.name}',
        'Launcher y: ${_y.toStringAsFixed(1)}',
        'SharedPreferences: available',
        'SQLite Explorer: available',
      ].join('\n'),
    );
  }

  Future<void> _exitDebug() async {
    if (_ending) return;
    HapticFeedback.mediumImpact();
    await _setExpanded(false);
    if (mounted) setState(() => _ending = true);
    if (!_reduceMotion) {
      await Future<void>.delayed(const Duration(milliseconds: 160));
    }
    await DevQuickActions.disableDeveloperMode(
      source: 'developer_quick_actions',
    );
  }

  Future<void> _exitApp() async {
    await _setExpanded(false);
    await DevQuickActions.closeAnySheet();
    final ctx = DevQuickActions._bestContext() ?? context;
    DebugSessionController.record(
      'developer_app_exit',
      source: 'developer_quick_actions',
    );
    await AppExitService.exitApp(ctx);
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final size = media.size;
    final paletteWidth =
        math.max(160.0, math.min(312.0, size.width - 28)).toDouble();
    final availablePaletteHeight = math.max(
      180.0,
      size.height - media.padding.top - media.padding.bottom - 24,
    ).toDouble();
    final paletteMaxHeight = math.min(440.0, availablePaletteHeight).toDouble();
    final launcherX = _side == _DebugEdgeSide.left
        ? _edge
        : size.width - _launcherWidth - _edge;
    final paletteLeft = _side == _DebugEdgeSide.left
        ? 14.0
        : size.width - paletteWidth - 14.0;
    final maxPaletteTop = math.max(
      media.padding.top + 12,
      size.height - media.padding.bottom - paletteMaxHeight - 12,
    ).toDouble();
    final paletteTop = (_y - 32).clamp(
      media.padding.top + 12,
      maxPaletteTop,
    ).toDouble();
    final duration =
        _reduceMotion ? Duration.zero : const Duration(milliseconds: 180);

    return Stack(
      children: [
        if (_expanded)
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _setExpanded(false),
              child: Opacity(
                opacity: 0.045 * _paletteAnimation.value,
                child: const ColoredBox(color: Colors.black),
              ),
            ),
          ),
        Positioned(
          left: paletteLeft,
          top: paletteTop,
          child: IgnorePointer(
            ignoring: !_expanded,
            child: Transform.scale(
              scale: 0.97 + 0.03 * _paletteAnimation.value,
              alignment: _side == _DebugEdgeSide.left
                  ? Alignment.centerLeft
                  : Alignment.centerRight,
              child: Opacity(
                opacity: _paletteAnimation.value,
                child: _DebugPalette(
                  width: paletteWidth,
                  maxHeight: paletteMaxHeight,
                  progress: _paletteAnimation.value,
                  onPrefs: _openPrefs,
                  onSQLite: _openSQLite,
                  onStatus: _showStatus,
                  onExitDebug: _exitDebug,
                  onExitApp: _exitApp,
                ),
              ),
            ),
          ),
        ),
        Positioned(
          left: launcherX,
          top: _y,
          child: AnimatedSlide(
            duration: duration,
            curve: Curves.easeOutCubic,
            offset: _ending
                ? Offset(
                    _side == _DebugEdgeSide.left ? -0.2 : 0.2,
                    0,
                  )
                : Offset.zero,
            child: AnimatedOpacity(
              duration: duration,
              opacity: _ending ? 0 : 1,
              child: TweenAnimationBuilder<double>(
                duration: _reduceMotion
                    ? Duration.zero
                    : const Duration(milliseconds: 220),
                curve: Curves.easeOutBack,
                tween: Tween<double>(begin: 0, end: 1),
                builder: (context, value, child) {
                  final visualProgress = value.clamp(0.0, 1.0).toDouble();
                  return Opacity(
                    opacity: visualProgress,
                    child: Transform.translate(
                      offset: Offset(
                        (_side == _DebugEdgeSide.left ? -10 : 10) *
                            (1 - visualProgress),
                        0,
                      ),
                      child: Transform.scale(
                        scale: 0.96 + 0.04 * value,
                        child: child,
                      ),
                    ),
                  );
                },
                child: GestureDetector(
                  onPanUpdate: (details) {
                    _dragX += details.delta.dx;
                    setState(() {
                      _y = _clampY(
                        _y + details.delta.dy,
                        size.height,
                        media.padding.bottom,
                      );
                    });
                  },
                  onPanEnd: (_) async {
                    final side = _dragX.abs() > 24
                        ? (_dragX > 0
                            ? _DebugEdgeSide.right
                            : _DebugEdgeSide.left)
                        : _side;
                    _dragX = 0;
                    setState(() => _side = side);
                    await widget.onPositionSave(_side, _y);
                  },
                  child: _DebugEdgePill(
                    expanded: _expanded,
                    side: _side,
                    reduceMotion: _reduceMotion,
                    onTap: () => _setExpanded(!_expanded),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  double _clampY(double raw, double height, double bottomInset) {
    final minY = MediaQuery.of(context).padding.top + 42;
    final maxY = math.max(
      minY,
      height - bottomInset - _launcherHeight - 18,
    );
    return raw.clamp(minY, maxY).toDouble();
  }
}

class _DebugEdgePill extends StatelessWidget {
  const _DebugEdgePill({
    required this.expanded,
    required this.side,
    required this.reduceMotion,
    required this.onTap,
  });

  final bool expanded;
  final _DebugEdgeSide side;
  final bool reduceMotion;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final borderRadius = BorderRadius.horizontal(
      left: Radius.circular(side == _DebugEdgeSide.right ? 16 : 6),
      right: Radius.circular(side == _DebugEdgeSide.left ? 16 : 6),
    );
    return Semantics(
      button: true,
      label: 'DEBUG 도구 열기',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: borderRadius,
          child: SizedBox(
            width: 96,
            height: 42,
            child: DebugCautionSurface(
              borderRadius: borderRadius,
              child: Padding(
                padding: const EdgeInsets.all(3),
                child: DebugCautionLabel(
                  borderRadius: BorderRadius.horizontal(
                    left: Radius.circular(
                      side == _DebugEdgeSide.right ? 13 : 4,
                    ),
                    right: Radius.circular(
                      side == _DebugEdgeSide.left ? 13 : 4,
                    ),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const SizedBox(
                        width: 7,
                        height: 7,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: debugCautionYellow,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                      const SizedBox(width: 7),
                      const Text(
                        'DEBUG',
                        style: TextStyle(
                          color: debugCautionYellow,
                          fontFamily: 'monospace',
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.6,
                        ),
                      ),
                      const SizedBox(width: 4),
                      AnimatedRotation(
                        duration: reduceMotion
                            ? Duration.zero
                            : const Duration(milliseconds: 180),
                        turns: expanded ? 0.5 : 0,
                        child: const Icon(
                          Icons.keyboard_arrow_up_rounded,
                          color: debugCautionYellow,
                          size: 17,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DebugPalette extends StatelessWidget {
  const _DebugPalette({
    required this.width,
    required this.maxHeight,
    required this.progress,
    required this.onPrefs,
    required this.onSQLite,
    required this.onStatus,
    required this.onExitDebug,
    required this.onExitApp,
  });

  static const Color _debugAccent = Color(0xFF6D5DFB);

  final double width;
  final double maxHeight;
  final double progress;
  final Future<void> Function() onPrefs;
  final Future<void> Function() onSQLite;
  final Future<void> Function() onStatus;
  final Future<void> Function() onExitDebug;
  final Future<void> Function() onExitApp;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          width: width,
          constraints: BoxConstraints(maxHeight: maxHeight),
          decoration: BoxDecoration(
            color: cs.surface.withOpacity(0.90),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: _debugAccent.withOpacity(0.34)),
            boxShadow: const [
              BoxShadow(
                color: Colors.black26,
                blurRadius: 20,
                offset: Offset(0, 8),
              ),
            ],
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
              Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: _debugAccent.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(11),
                    ),
                    alignment: Alignment.center,
                    child: const Icon(
                      Icons.terminal_rounded,
                      color: _debugAccent,
                      size: 19,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'DEBUG TOOLS',
                          style: text.titleSmall?.copyWith(
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.4,
                          ),
                        ),
                        Text(
                          '개발자 세션 활성화',
                          style: text.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(
                    width: 7,
                    height: 7,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: _debugAccent,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _PaletteSectionLabel(label: '검사'),
              _AnimatedPaletteAction(
                index: 0,
                progress: progress,
                icon: Icons.tune_rounded,
                title: 'SharedPreferences',
                subtitle: '로컬 설정 값 검사 및 수정',
                onTap: onPrefs,
              ),
              _AnimatedPaletteAction(
                index: 1,
                progress: progress,
                icon: Icons.storage_rounded,
                title: 'SQLite Explorer',
                subtitle: '데이터베이스 · 테이블 · 행 검사',
                onTap: onSQLite,
              ),
              _AnimatedPaletteAction(
                index: 2,
                progress: progress,
                icon: Icons.monitor_heart_outlined,
                title: 'Status',
                subtitle: 'debugPrint 로그 확인 및 코드 복사',
                onTap: onStatus,
              ),
              const SizedBox(height: 8),
              _PaletteSectionLabel(label: '세션'),
              _AnimatedPaletteAction(
                index: 3,
                progress: progress,
                icon: Icons.logout_rounded,
                title: 'DEBUG 종료',
                subtitle: '앱은 유지하고 개발자 세션만 종료',
                onTap: onExitDebug,
              ),
              const SizedBox(height: 8),
              _PaletteSectionLabel(label: '앱'),
              _AnimatedPaletteAction(
                index: 4,
                progress: progress,
                icon: Icons.power_settings_new_rounded,
                title: '앱 종료',
                subtitle: 'ParkinWorkin을 종료',
                destructive: true,
                onTap: onExitApp,
              ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PaletteSectionLabel extends StatelessWidget {
  const _PaletteSectionLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 2, 4, 5),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: cs.onSurfaceVariant,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.5,
            ),
      ),
    );
  }
}

class _AnimatedPaletteAction extends StatelessWidget {
  const _AnimatedPaletteAction({
    required this.index,
    required this.progress,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.destructive = false,
  });

  final int index;
  final double progress;
  final IconData icon;
  final String title;
  final String subtitle;
  final Future<void> Function() onTap;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final begin = (0.08 + index * 0.07).clamp(0.0, 0.72).toDouble();
    final end = (begin + 0.42).clamp(0.42, 1.0).toDouble();
    final local = ((progress - begin) / (end - begin))
        .clamp(0.0, 1.0)
        .toDouble();
    final eased = Curves.easeOutCubic.transform(local);
    return Opacity(
      opacity: eased,
      child: Transform.translate(
        offset: Offset(0, 5 * (1 - eased)),
        child: _PaletteActionTile(
          icon: icon,
          title: title,
          subtitle: subtitle,
          destructive: destructive,
          onTap: onTap,
        ),
      ),
    );
  }
}

class _PaletteActionTile extends StatelessWidget {
  const _PaletteActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    required this.destructive,
  });

  static const Color _debugAccent = Color(0xFF6D5DFB);

  final IconData icon;
  final String title;
  final String subtitle;
  final Future<void> Function() onTap;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final accent = destructive ? cs.error : _debugAccent;
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () {
            HapticFeedback.selectionClick();
            onTap();
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: cs.outlineVariant.withOpacity(0.65)),
              color: accent.withOpacity(0.045),
            ),
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: accent.withOpacity(0.11),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  alignment: Alignment.center,
                  child: Icon(icon, color: accent, size: 18),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                              color: destructive ? cs.error : cs.onSurface,
                            ),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 18,
                  color: destructive ? cs.error : cs.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DebugSpringCurve extends Curve {
  const _DebugSpringCurve();

  @override
  double transform(double t) {
    final e = math.exp(-6 * t);
    final c = math.cos(10 * t);
    return (1 - e * c).clamp(0.0, 1.0).toDouble();
  }
}
