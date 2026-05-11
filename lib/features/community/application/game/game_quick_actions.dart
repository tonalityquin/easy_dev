import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../app/init/app_navigator.dart';
import '../../widgets/game/tetris.dart';

class GameQuickActions {
  GameQuickActions._();

  static GlobalKey<NavigatorState> get navigatorKey => AppNavigator.key;

  static final enabled = ValueNotifier<bool>(false);

  static const _kEnabledKey = 'game_quick_actions_enabled_v1';
  static const _kBubbleXKey = 'game_quick_actions_bubble_x_v1';
  static const _kBubbleYKey = 'game_quick_actions_bubble_y_v1';
  static const _kHeadEnabledKey = 'head_hub_actions_enabled_v1';
  static const _kHeadBubbleXKey = 'head_hub_actions_bubble_x_v1';
  static const _kHeadBubbleYKey = 'head_hub_actions_bubble_y_v1';

  static SharedPreferences? _prefs;
  static OverlayEntry? _entry;
  static bool _initialized = false;
  static bool _opening = false;
  static bool _closing = false;
  static bool _sheetOpen = false;
  static Future<void>? _activeSheet;

  static BuildContext? _bestContext() {
    final state = navigatorKey.currentState;
    final overlayCtx = state?.overlay?.context;
    return overlayCtx ?? state?.context;
  }

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
        closeTetrisSheet();
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

  static void toggleEnabled() => enabled.value = !enabled.value;

  static Future<void> openTetrisSheet([BuildContext? context]) async {
    if (_opening) return;
    if (_sheetOpen) return;
    _opening = true;
    final ctx = context ?? _bestContext();
    if (ctx == null) {
      _opening = false;
      return;
    }
    try {
      _sheetOpen = true;
      final future = showModalBottomSheet<void>(
        context: ctx,
        isScrollControlled: true,
        useSafeArea: true,
        backgroundColor: Colors.transparent,
        builder: (_) => const _GameTetrisSheet(),
      );
      _activeSheet = future;
      await future;
    } finally {
      TetrisGameSession.pauseSession();
      _activeSheet = null;
      _sheetOpen = false;
      _opening = false;
    }
  }

  static Future<void> closeTetrisSheet() async {
    if (_closing) return;
    _closing = true;
    try {
      TetrisGameSession.pauseSession();
      if (!_sheetOpen) return;
      final ctx = _bestContext();
      if (ctx == null) return;
      Navigator.of(ctx).maybePop();
      try {
        await _activeSheet;
      } catch (_) {}
    } finally {
      _closing = false;
    }
  }

  static Future<void> toggleTetrisSheet([BuildContext? context]) async {
    if (_sheetOpen) {
      await closeTetrisSheet();
    } else {
      await openTetrisSheet(context);
    }
  }

  static Future<void> terminateSession({bool disableBubble = false}) async {
    TetrisGameSession.terminate();
    await closeTetrisSheet();
    TetrisGameSession.terminate();
    if (disableBubble) setEnabled(false);
  }

  static Offset _restorePos() {
    final dx = _prefs?.getDouble(_kBubbleXKey) ?? 100000.0;
    final dy = _prefs?.getDouble(_kBubbleYKey) ?? 272.0;
    return Offset(dx, dy);
  }

  static Future<void> _savePos(Offset pos) async {
    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.setDouble(_kBubbleXKey, pos.dx);
    await _prefs!.setDouble(_kBubbleYKey, pos.dy);
  }

  static void _showOverlay() {
    if (_entry != null) return;
    final overlay = navigatorKey.currentState?.overlay;
    if (overlay == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _showOverlay());
      return;
    }
    _entry = OverlayEntry(
      builder: (context) => Material(
        type: MaterialType.transparency,
        child: _GameBubble(initialPos: _restorePos(), onPosSave: _savePos),
      ),
    );
    overlay.insert(_entry!);
  }

  static void _hideOverlay() {
    _entry?.remove();
    _entry = null;
  }
}

class _GameTetrisSheet extends StatelessWidget {
  const _GameTetrisSheet();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return DraggableScrollableSheet(
      initialChildSize: 1.0,
      minChildSize: 0.55,
      maxChildSize: 1.0,
      expand: false,
      builder: (_, controller) {
        return Container(
          decoration: BoxDecoration(
            color: cs.background,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.12), blurRadius: 16, offset: const Offset(0, -4))],
          ),
          child: SafeArea(
            top: true,
            bottom: false,
            child: Column(
              children: [
                const SizedBox(height: 8),
                Container(
                  width: 44,
                  height: 4,
                  decoration: BoxDecoration(color: cs.onSurface.withOpacity(0.16), borderRadius: BorderRadius.circular(999)),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 8, 8),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 18,
                        backgroundColor: cs.secondaryContainer,
                        child: Icon(Icons.extension_rounded, color: cs.onSecondaryContainer, size: 20),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('테트리스', style: text.titleMedium?.copyWith(fontWeight: FontWeight.w800, color: cs.onSurface)),
                            Text('닫으면 일시정지되고 다시 열면 이어서 재개할 수 있습니다.', style: text.bodySmall?.copyWith(color: cs.onSurfaceVariant), maxLines: 1, overflow: TextOverflow.ellipsis),
                          ],
                        ),
                      ),
                      ValueListenableBuilder<bool>(
                        valueListenable: GameQuickActions.enabled,
                        builder: (context, on, _) {
                          return Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(on ? 'Bubble ON' : 'Bubble OFF', style: text.labelMedium?.copyWith(color: on ? cs.primary : cs.onSurfaceVariant, fontWeight: FontWeight.w800)),
                              Switch.adaptive(
                                value: on,
                                onChanged: (v) async {
                                  GameQuickActions.setEnabled(v);
                                  if (v) await GameQuickActions.mountIfNeeded();
                                  HapticFeedback.selectionClick();
                                },
                              ),
                            ],
                          );
                        },
                      ),
                      IconButton(
                        tooltip: '닫기',
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                ),
                Divider(height: 1, color: cs.outlineVariant),
                Expanded(
                  child: Tetris.embedded(onClose: () => Navigator.of(context).pop()),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _GameBubble extends StatefulWidget {
  final Offset initialPos;
  final Future<void> Function(Offset) onPosSave;

  const _GameBubble({required this.initialPos, required this.onPosSave});

  @override
  State<_GameBubble> createState() => _GameBubbleState();
}

class _GameBubbleState extends State<_GameBubble> {
  static const double _touchWidth = 34;
  static const double _height = 64;
  static const double _visualWidth = 18;
  static const double _headTouchWidth = 28;
  static const double _headHeight = 56;
  static const double _bubbleGap = 12;

  late Offset _pos;
  bool _clampedOnce = false;

  @override
  void initState() {
    super.initState();
    _pos = widget.initialPos;
  }

  Offset _clamp(Offset raw, Size screen, double bottomInset) {
    final right = (raw.dx + _touchWidth / 2) >= screen.width / 2;
    final x = right ? screen.width - _touchWidth : 0.0;
    final maxY = (screen.height - _height - bottomInset).clamp(0.0, double.infinity).toDouble();
    final y = raw.dy.clamp(0.0, maxY).toDouble();
    return _avoidHeadOverlap(Offset(x, y), screen, bottomInset);
  }

  Rect? _headBubbleRect(Size screen, double bottomInset) {
    final prefs = GameQuickActions._prefs;
    if (prefs?.getBool(GameQuickActions._kHeadEnabledKey) != true) return null;
    final rawDx = prefs?.getDouble(GameQuickActions._kHeadBubbleXKey) ?? 12.0;
    final rawDy = prefs?.getDouble(GameQuickActions._kHeadBubbleYKey) ?? 200.0;
    final right = (rawDx + _headTouchWidth / 2) >= screen.width / 2;
    final x = right ? screen.width - _headTouchWidth : 0.0;
    final maxY = (screen.height - _headHeight - bottomInset).clamp(0.0, double.infinity).toDouble();
    final y = rawDy.clamp(0.0, maxY).toDouble();
    return Rect.fromLTWH(x, y, _headTouchWidth, _headHeight);
  }

  Offset _avoidHeadOverlap(Offset pos, Size screen, double bottomInset) {
    final head = _headBubbleRect(screen, bottomInset);
    if (head == null) return pos;
    final mine = Rect.fromLTWH(pos.dx, pos.dy, _touchWidth, _height);
    if (!mine.overlaps(head)) return pos;

    final maxY = (screen.height - _height - bottomInset).clamp(0.0, double.infinity).toDouble();
    final below = (head.bottom + _bubbleGap).clamp(0.0, maxY).toDouble();
    final belowRect = Rect.fromLTWH(pos.dx, below, _touchWidth, _height);
    if (!belowRect.overlaps(head)) return Offset(pos.dx, below);

    final above = (head.top - _bubbleGap - _height).clamp(0.0, maxY).toDouble();
    final aboveRect = Rect.fromLTWH(pos.dx, above, _touchWidth, _height);
    if (!aboveRect.overlaps(head)) return Offset(pos.dx, above);

    return Offset(pos.dx, maxY);
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final screen = mq.size;
    final bottomInset = mq.padding.bottom + mq.viewInsets.bottom;
    if (!_clampedOnce && screen != Size.zero) {
      _clampedOnce = true;
      _pos = _clamp(_pos, screen, bottomInset);
    }

    final right = (_pos.dx + _touchWidth / 2) >= screen.width / 2;
    final x = right ? screen.width - _touchWidth : 0.0;

    return Stack(
      children: [
        Positioned(
          left: x,
          top: _pos.dy,
          width: _touchWidth,
          height: _height,
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: () async {
              HapticFeedback.lightImpact();
              await GameQuickActions.toggleTetrisSheet(context);
            },
            onLongPress: () async {
              HapticFeedback.mediumImpact();
              await GameQuickActions.terminateSession();
            },
            onPanUpdate: (d) => setState(() => _pos = _clamp(_pos + d.delta, screen, bottomInset)),
            onPanEnd: (_) async {
              final snapped = _clamp(_pos, screen, bottomInset);
              setState(() => _pos = snapped);
              await widget.onPosSave(snapped);
            },
            child: Align(
              alignment: right ? Alignment.centerRight : Alignment.centerLeft,
              child: _GameEdgeHandle(width: _visualWidth, height: _height, dockRight: right),
            ),
          ),
        ),
      ],
    );
  }
}

class _GameEdgeHandle extends StatelessWidget {
  final double width;
  final double height;
  final bool dockRight;

  const _GameEdgeHandle({required this.width, required this.height, required this.dockRight});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final borderRadius = BorderRadius.horizontal(
      left: Radius.circular(dockRight ? 999 : 0),
      right: Radius.circular(dockRight ? 0 : 999),
    );

    return Semantics(
      button: true,
      label: '테트리스 열기',
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          borderRadius: borderRadius,
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [cs.secondaryContainer, Color.alphaBlend(cs.secondary.withOpacity(0.18), cs.surface)],
          ),
          border: Border.all(color: cs.outlineVariant.withOpacity(0.85)),
          boxShadow: [BoxShadow(blurRadius: 16, offset: const Offset(0, 6), color: cs.shadow.withOpacity(0.22))],
        ),
        child: RotatedBox(
          quarterTurns: dockRight ? 1 : 3,
          child: Icon(Icons.extension_rounded, size: 16, color: cs.onSecondaryContainer),
        ),
      ),
    );
  }
}
