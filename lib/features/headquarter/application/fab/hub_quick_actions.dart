import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../app/init/app_navigator.dart';
import '../../page/sheets/company_calendar_page.dart';
import '../../page/sheets/head_memo.dart';
import '../../page/sheets/head_tutorials.dart';
import '../../page/sheets/roadmap_bottom_sheet.dart';
import '../../widgets/hr/attendance_calendar.dart' as hr_att;
import '../../widgets/hr/break_calendar.dart' as hr_break;
import '../../widgets/mgmt/field.dart' as mgmt;
import '../../widgets/mgmt/statistics.dart' as mgmt_stats;
class HeadHubActions {
  HeadHubActions._();

  static GlobalKey<NavigatorState> get navigatorKey => AppNavigator.key;

  static final enabled = ValueNotifier<bool>(false);

  static const _kEnabledKey = 'head_hub_actions_enabled_v1';
  static const _kBubbleXKey = 'head_hub_actions_bubble_x_v1';
  static const contactFormUrl = 'https://forms.gle/hDTkX1p6U9jMMuySA';
  static const _kBubbleYKey = 'head_hub_actions_bubble_y_v1';
  static const _kGameEnabledKey = 'game_quick_actions_enabled_v1';
  static const _kGameBubbleXKey = 'game_quick_actions_bubble_x_v1';
  static const _kGameBubbleYKey = 'game_quick_actions_bubble_y_v1';

  static SharedPreferences? _prefs;
  static OverlayEntry? _entry;
  static bool _initialized = false;

  static bool _closing = false;
  static bool _opening = false;

  static Future<void>? _activeSheet;

  static BuildContext? _bestContext() {
    final state = navigatorKey.currentState;
    final overlayCtx = state?.overlay?.context;
    return overlayCtx ?? state?.context;
  }

  static BuildContext? currentContext() => _bestContext();

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
        final T? result = await fut;
        return result;
      } finally {
        _activeSheet = null;
        await Future<void>.delayed(const Duration(milliseconds: 16));
      }
    } finally {
      _opening = false;
    }
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

  static Future<bool> openContactForm([BuildContext? context]) async {
    final uri = Uri.tryParse(contactFormUrl.trim());
    if (uri == null) return false;

    var opened = false;

    try {
      opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      opened = false;
    }

    if (!opened) {
      try {
        opened = await launchUrl(uri, mode: LaunchMode.platformDefault);
      } catch (_) {
        opened = false;
      }
    }

    if (!opened) {
      final ctx = context ?? _bestContext();
      final messenger = ctx == null ? null : ScaffoldMessenger.maybeOf(ctx);
      messenger?.showSnackBar(
        const SnackBar(
          content: Text('문의하기 화면을 열 수 없습니다.'),
          behavior: SnackBarBehavior.floating,
          duration: Duration(milliseconds: 1200),
        ),
      );
    }

    return opened;
  }

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
        child: _HubBubble(
          initialPos: _restorePos(),
          onPosSave: _savePos,
        ),
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

class _HubBubbleState extends State<_HubBubble>
    with SingleTickerProviderStateMixin {
  static const double _handleTouchWidth = 44;
  static const double _handleVisualWidth = 18;
  static const double _handleHeight = 56;
  static const double _dockRadius = 18;
  static const double _gameTouchWidth = 34;
  static const double _gameHeight = 64;
  static const double _bubbleGap = 12;

  late Offset _pos;
  bool _clampedOnce = false;

  late final AnimationController _ctrl;
  late final Animation<double> _t;

  bool get _expanded => _ctrl.value > 0.001;

  final TextEditingController _searchCtrl = TextEditingController();
  final FocusNode _searchFocus = FocusNode();

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
    _searchCtrl.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _searchFocus.dispose();
    _ctrl.dispose();
    super.dispose();
  }

  void _toggleMenu() {
    if (_expanded) {
      _searchFocus.unfocus();
      _ctrl.reverse();
    } else {
      _searchCtrl.clear();
      _ctrl.forward();
    }
    HapticFeedback.lightImpact();
  }

  Future<void> _handleActionTap(_DockAction action) async {
    HapticFeedback.selectionClick();
    await action.onTap();
  }

  List<_DockAction> _buildActions(ColorScheme cs) {
    Future<void> closeMenu() async {
      if (_expanded) {
        _searchFocus.unfocus();
        await _ctrl.reverse();
      }
    }

    return <_DockAction>[
      _DockAction(
        id: 'memo',
        icon: Icons.sticky_note_2_rounded,
        label: '메모',
        hint: '플로팅 버블 · 어디서나 기록',
        color: cs.secondaryContainer,
        onTap: () async {
          await closeMenu();
          await HeadHubActions.openSheetExclusively<dynamic>((ctx) {
            return HeadMemo.openPanel();
          });
        },
      ),
      _DockAction(
        id: 'company_calendar',
        icon: Icons.calendar_month_rounded,
        label: '본사 달력',
        hint: '본사 직원 간 일정 공유',
        color: const Color(0xFF43A047),
        onTap: () async {
          await closeMenu();
          await HeadHubActions.openSheetExclusively<dynamic>((ctx) {
            return CompanyCalendarPage.showAsBottomSheet(ctx);
          });
        },
      ),
      _DockAction(
        id: 'attendance',
        icon: Icons.how_to_reg_rounded,
        label: '출·퇴근',
        hint: '각 직원 별 출퇴근 관리',
        color: const Color(0xFF1565C0),
        onTap: () async {
          await closeMenu();
          await HeadHubActions.openSheetExclusively<dynamic>((ctx) {
            return hr_att.AttendanceCalendar.showAsBottomSheet(ctx);
          });
        },
      ),
      _DockAction(
        id: 'break',
        icon: Icons.free_breakfast_rounded,
        label: '휴게 관리',
        hint: '각 직원 별 휴게시간 관리',
        color: const Color(0xFF3949AB),
        onTap: () async {
          await closeMenu();
          await HeadHubActions.openSheetExclusively<dynamic>((ctx) {
            return hr_break.BreakCalendar.showAsBottomSheet(ctx);
          });
        },
      ),
      _DockAction(
        id: 'field',
        icon: Icons.map_rounded,
        label: '근무지 현황',
        hint: 'Division별 지역 · 인원',
        color: const Color(0xFF00897B),
        onTap: () async {
          await closeMenu();
          await HeadHubActions.openSheetExclusively<dynamic>((ctx) {
            return mgmt.Field.showAsBottomSheet(ctx);
          });
        },
      ),
      _DockAction(
        id: 'statistics',
        icon: Icons.stacked_line_chart_rounded,
        label: '통계 비교',
        hint: '입·출차/정산 추이',
        color: const Color(0xFF6A1B9A),
        onTap: () async {
          await closeMenu();
          await HeadHubActions.openSheetExclusively<dynamic>((ctx) {
            return mgmt_stats.Statistics.showAsBottomSheet(ctx);
          });
        },
      ),
      _DockAction(
        id: 'roadmap',
        icon: Icons.edit_note_rounded,
        label: '향후 로드맵',
        hint: 'After Release',
        color: const Color(0xFF7E57C2),
        onTap: () async {
          await closeMenu();
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
        id: 'tutorials',
        icon: Icons.menu_book_rounded,
        label: '튜토리얼',
        hint: 'PDF 가이드 모음',
        color: const Color(0xFF00695C),
        onTap: () async {
          await closeMenu();
          final TutorialItem? selected =
              await HeadHubActions.openSheetExclusively<TutorialItem>((ctx) {
            return HeadTutorials.showPickerBottomSheet(ctx);
          });

          final ctx2 = HeadHubActions.currentContext();
          if (selected != null && ctx2 != null) {
            await TutorialPdfViewer.open(ctx2, selected);
          }
        },
      ),
      _DockAction(
        id: 'contact',
        icon: Icons.contact_support_rounded,
        label: '문의하기',
        hint: '이슈 · 오류 · 궁금증',
        color: const Color(0xFFD84315),
        onTap: () async {
          await closeMenu();
          await HeadHubActions.closeAnySheet();
          await HeadHubActions.openContactForm();
        },
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.maybeOf(context);
    final screen = media?.size ?? Size.zero;
    final bottomInset = media?.padding.bottom ?? 0;
    final keyboardInset = media?.viewInsets.bottom ?? 0;
    final cs = Theme.of(context).colorScheme;

    if (!_clampedOnce && screen != Size.zero) {
      _clampedOnce = true;
      _pos = _clampToScreen(_pos, screen, bottomInset + keyboardInset);
    }

    final dockRight = screen == Size.zero
        ? true
        : (_pos.dx + _handleTouchWidth / 2) >= screen.width / 2;

    final actions = _buildActions(cs);

    final maxDockWidth = (screen.width * 0.92).clamp(240.0, double.infinity);
    final dockWidth = math.min(360.0, maxDockWidth);

    final dockBorderRadius = dockRight
        ? const BorderRadius.only(
            topLeft: Radius.circular(_dockRadius),
            bottomLeft: Radius.circular(_dockRadius),
          )
        : const BorderRadius.only(
            topRight: Radius.circular(_dockRadius),
            bottomRight: Radius.circular(_dockRadius),
          );

    final slideDistance = dockWidth + _handleTouchWidth + 24;
    final slideX = dockRight
        ? slideDistance * (1 - _t.value)
        : -slideDistance * (1 - _t.value);

    final handleX = screen == Size.zero
        ? _pos.dx
        : (dockRight ? (screen.width - _handleTouchWidth) : 0.0);

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
          top: 0,
          bottom: 0,
          left: dockRight ? null : 0,
          right: dockRight ? 0 : null,
          child: IgnorePointer(
            ignoring: !_expanded,
            child: Transform.translate(
              offset: Offset(slideX, 0),
              child: Opacity(
                opacity: _t.value,
                child: _GlassDock(
                  width: dockWidth,
                  height: screen.height,
                  borderRadius: dockBorderRadius,
                  child: SafeArea(
                    child: Padding(
                      padding: EdgeInsets.only(bottom: keyboardInset),
                      child: _CommandPaletteDock(
                        actions: actions,
                        controller: _searchCtrl,
                        focusNode: _searchFocus,
                        onSelect: _handleActionTap,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        Positioned(
          left: handleX,
          top: _pos.dy,
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: _toggleMenu,
            onPanUpdate: (d) {
              if (screen == Size.zero) return;
              setState(() {
                final next = Offset(_pos.dx + d.delta.dx, _pos.dy + d.delta.dy);
                _pos =
                    _clampToScreen(next, screen, bottomInset + keyboardInset);
              });
            },
            onPanEnd: (_) async {
              if (screen == Size.zero) return;
              setState(() {
                _pos = _clampToScreen(_pos, screen, bottomInset + keyboardInset);
              });
              await widget.onPosSave(_pos);
            },
            child: SizedBox(
              width: _handleTouchWidth,
              height: _handleHeight,
              child: Align(
                alignment:
                    dockRight ? Alignment.centerRight : Alignment.centerLeft,
                child: _EdgeHandle(
                  width: _handleVisualWidth,
                  height: _handleHeight,
                  dockRight: dockRight,
                  expanded: _expanded,
                  progress: _t.value,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Offset _clampToScreen(Offset raw, Size screen, double bottomInset) {
    final wantsRight = (raw.dx + _handleTouchWidth / 2) >= screen.width / 2;
    final snappedX = wantsRight ? (screen.width - _handleTouchWidth) : 0.0;

    final maxY = (screen.height - _handleHeight - bottomInset).clamp(0.0, double.infinity).toDouble();
    final dy = raw.dy.clamp(0.0, maxY).toDouble();
    return _avoidGameOverlap(Offset(snappedX, dy), screen, bottomInset);
  }

  Rect? _gameBubbleRect(Size screen, double bottomInset) {
    final prefs = HeadHubActions._prefs;
    if (prefs?.getBool(HeadHubActions._kGameEnabledKey) != true) return null;
    final rawDx = prefs?.getDouble(HeadHubActions._kGameBubbleXKey) ?? 100000.0;
    final rawDy = prefs?.getDouble(HeadHubActions._kGameBubbleYKey) ?? 272.0;
    final right = (rawDx + _gameTouchWidth / 2) >= screen.width / 2;
    final x = right ? screen.width - _gameTouchWidth : 0.0;
    final maxY = (screen.height - _gameHeight - bottomInset).clamp(0.0, double.infinity).toDouble();
    final y = rawDy.clamp(0.0, maxY).toDouble();
    return Rect.fromLTWH(x, y, _gameTouchWidth, _gameHeight);
  }

  Offset _avoidGameOverlap(Offset pos, Size screen, double bottomInset) {
    final game = _gameBubbleRect(screen, bottomInset);
    if (game == null) return pos;
    final mine = Rect.fromLTWH(pos.dx, pos.dy, _handleTouchWidth, _handleHeight);
    if (!mine.overlaps(game)) return pos;

    final maxY = (screen.height - _handleHeight - bottomInset).clamp(0.0, double.infinity).toDouble();
    final above = (game.top - _bubbleGap - _handleHeight).clamp(0.0, maxY).toDouble();
    final aboveRect = Rect.fromLTWH(pos.dx, above, _handleTouchWidth, _handleHeight);
    if (!aboveRect.overlaps(game)) return Offset(pos.dx, above);

    final below = (game.bottom + _bubbleGap).clamp(0.0, maxY).toDouble();
    final belowRect = Rect.fromLTWH(pos.dx, below, _handleTouchWidth, _handleHeight);
    if (!belowRect.overlaps(game)) return Offset(pos.dx, below);

    return Offset(pos.dx, 0.0);
  }
}

class _CommandPaletteDock extends StatelessWidget {
  final List<_DockAction> actions;
  final TextEditingController controller;
  final FocusNode focusNode;
  final Future<void> Function(_DockAction action) onSelect;

  const _CommandPaletteDock({
    required this.actions,
    required this.controller,
    required this.focusNode,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    final queryRaw = controller.text.trim();
    final query = _normalize(queryRaw);

    final filtered = query.isEmpty
        ? actions
        : actions
            .where((a) => _normalize(a.searchText).contains(query))
            .toList(growable: false);

    final titleText = query.isEmpty ? '빠른 실행' : '검색 결과';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          titleText,
          style: text.titleSmall?.copyWith(
            fontWeight: FontWeight.w800,
            letterSpacing: 0.2,
            color: cs.onSurface,
          ),
        ),
        const SizedBox(height: 10),
        _SearchField(
          controller: controller,
          focusNode: focusNode,
          onSubmit: () async {
            if (filtered.isNotEmpty) {
              await onSelect(filtered.first);
            }
          },
        ),
        const SizedBox(height: 10),
        Expanded(
          child: _PaletteList(
            query: query,
            items: filtered,
            onSelect: onSelect,
          ),
        ),
      ],
    );
  }

  static String _normalize(String s) =>
      s.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();
}

class _SearchField extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final Future<void> Function() onSubmit;

  const _SearchField({
    required this.controller,
    required this.focusNode,
    required this.onSubmit,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final border = cs.outlineVariant.withOpacity(0.85);
    final fill = cs.surface.withOpacity(0.55);

    return Container(
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: border, width: 1),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Row(
        children: [
          Icon(Icons.search_rounded, color: cs.onSurfaceVariant),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => onSubmit(),
              decoration: InputDecoration(
                isDense: true,
                hintText: '기능 검색',
                border: InputBorder.none,
                hintStyle: TextStyle(
                  color: cs.onSurfaceVariant.withOpacity(0.8),
                ),
              ),
            ),
          ),
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: controller,
            builder: (context, v, _) {
              final hasText = v.text.trim().isNotEmpty;
              if (!hasText) return const SizedBox.shrink();
              return IconButton(
                onPressed: () => controller.clear(),
                icon: Icon(Icons.close_rounded, color: cs.onSurfaceVariant),
                tooltip: '지우기',
              );
            },
          ),
        ],
      ),
    );
  }
}

class _PaletteList extends StatelessWidget {
  final String query;
  final List<_DockAction> items;
  final Future<void> Function(_DockAction action) onSelect;

  const _PaletteList({
    required this.query,
    required this.items,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    if (query.isNotEmpty && items.isEmpty) {
      return Center(
        child: Text(
          '검색 결과가 없습니다.',
          style: text.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
        ),
      );
    }

    return ListView.separated(
      padding: EdgeInsets.zero,
      physics: const ClampingScrollPhysics(),
      itemCount: items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        return _PaletteTile(
          action: items[index],
          onSelect: onSelect,
        );
      },
    );
  }
}

class _PaletteTile extends StatelessWidget {
  final _DockAction action;
  final Future<void> Function(_DockAction action) onSelect;

  const _PaletteTile({required this.action, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    final border = cs.outlineVariant.withOpacity(0.65);
    final bg = cs.surface.withOpacity(0.50);

    return Semantics(
      button: true,
      label: action.label,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => onSelect(action),
          child: Ink(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: border, width: 1),
            ),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: action.color,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: cs.shadow.withOpacity(0.10),
                        blurRadius: 8,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  alignment: Alignment.center,
                  child: Icon(action.icon, color: Colors.white, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        action.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: text.titleSmall?.copyWith(
                          color: cs.onSurface,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.2,
                        ),
                      ),
                      if ((action.hint ?? '').trim().isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          action.hint!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: text.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant,
                            height: 1.15,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(Icons.chevron_right_rounded, color: cs.onSurfaceVariant),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DockAction {
  final String id;
  final IconData icon;
  final String label;
  final String? hint;
  final Color color;
  final Future<void> Function() onTap;

  _DockAction({
    required this.id,
    required this.icon,
    required this.label,
    required this.hint,
    required this.color,
    required this.onTap,
  });

  String get searchText => [label, hint].whereType<String>().join(' ');
}

class _EdgeHandle extends StatelessWidget {
  final double width;
  final double height;
  final bool dockRight;
  final bool expanded;
  final double progress;

  const _EdgeHandle({
    required this.width,
    required this.height,
    required this.dockRight,
    required this.expanded,
    required this.progress,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final t = Curves.easeOutCubic.transform(progress.clamp(0.0, 1.0));
    final bg0 = Color.alphaBlend(
        cs.primaryContainer.withOpacity(0.55 + 0.10 * t), cs.surface);
    final bg1 = Color.alphaBlend(
        cs.secondaryContainer.withOpacity(0.35 + 0.10 * t), cs.surface);
    final border = cs.outlineVariant.withOpacity(0.85);

    IconData icon;
    if (dockRight) {
      icon =
          expanded ? Icons.chevron_right_rounded : Icons.chevron_left_rounded;
    } else {
      icon =
          expanded ? Icons.chevron_left_rounded : Icons.chevron_right_rounded;
    }

    return Semantics(
      button: true,
      label: expanded ? '빠른 실행 닫기' : '빠른 실행 열기',
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(999),
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [bg0, bg1],
          ),
          border: Border.all(color: border, width: 1),
          boxShadow: [
            BoxShadow(
              blurRadius: 16,
              offset: const Offset(0, 6),
              color: cs.shadow.withOpacity(0.22),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 18, color: cs.onSurface.withOpacity(0.92)),
            const SizedBox(height: 8),
            _GripDots(color: cs.onSurfaceVariant.withOpacity(0.55)),
          ],
        ),
      ),
    );
  }
}

class _GripDots extends StatelessWidget {
  final Color color;

  const _GripDots({required this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _Dot(color: color),
        const SizedBox(height: 4),
        _Dot(color: color),
        const SizedBox(height: 4),
        _Dot(color: color),
      ],
    );
  }
}

class _Dot extends StatelessWidget {
  final Color color;

  const _Dot({required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 3.5,
      height: 3.5,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
      ),
    );
  }
}

class _GlassDock extends StatelessWidget {
  final double width;
  final double height;
  final BorderRadius borderRadius;
  final Widget child;

  const _GlassDock({
    required this.width,
    required this.height,
    required this.borderRadius,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return ClipRRect(
      borderRadius: borderRadius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          width: width,
          height: height,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: borderRadius,
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
