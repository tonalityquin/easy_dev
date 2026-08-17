import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../app/utils/status_dialog.dart';
import '../../../../design_system/common_ui/common_ui_components.dart';
import '../../../../design_system/common_ui/common_ui_side_dock.dart';
import '../../../../design_system/common_ui/common_ui_theme.dart';
import '../../../selector/application/dev_auth.dart';

class HeadquarterModeDockResult {
  const HeadquarterModeDockResult.switchMode(this.modeKey)
      : openSecondary = false;

  const HeadquarterModeDockResult.openSecondary()
      : modeKey = '',
        openSecondary = true;

  final String modeKey;
  final bool openSecondary;
}

Future<HeadquarterModeDockResult?> showHeadquarterModeSideDock({
  required BuildContext context,
  required String currentModeKey,
  required String currentScreen,
}) {
  return showCommonRightSideDock<HeadquarterModeDockResult>(
    context: context,
    barrierLabel: '헤드쿼터 모드 전환',
    builder: (_) => HeadquarterModeSideDock(
      currentModeKey: currentModeKey,
      currentScreen: currentScreen,
    ),
  );
}

class HeadquarterModeSideDock extends StatefulWidget {
  const HeadquarterModeSideDock({
    super.key,
    required this.currentModeKey,
    required this.currentScreen,
  });

  final String currentModeKey;
  final String currentScreen;

  @override
  State<HeadquarterModeSideDock> createState() =>
      _HeadquarterModeSideDockState();
}

class _HeadquarterModeSideDockState extends State<HeadquarterModeSideDock> {
  static const List<_HeadquarterRailItem> _items = <_HeadquarterRailItem>[
    _HeadquarterRailItem(
      modeKey: 'double',
      label: '더블',
      title: '더블 헤드쿼터',
      icon: Icons.view_week_rounded,
    ),
    _HeadquarterRailItem(
      modeKey: 'triple',
      label: '트리플',
      title: '트리플 헤드쿼터',
      icon: Icons.apartment_rounded,
    ),
    _HeadquarterRailItem(
      modeKey: 'minor',
      label: '마이너',
      title: '마이너 헤드쿼터',
      icon: Icons.tune_rounded,
    ),
    _HeadquarterRailItem(
      modeKey: 'sprint',
      label: '스프린트',
      title: '스프린트 모드',
      icon: Icons.bolt_rounded,
    ),
  ];

  final _HeadquarterDockDebugLog _debugLog = _HeadquarterDockDebugLog();
  late String _selectedModeKey;
  bool _developerLoggedIn = false;
  bool _devModeEnabled = false;

  @override
  void initState() {
    super.initState();
    _selectedModeKey = widget.currentModeKey;
    _debugLog.log(
      'mounted screen=${widget.currentScreen} current=${widget.currentModeKey}',
    );
    DevAuth.devModeEnabled.addListener(_handleDevModeChanged);
    _resolveDeveloperState();
  }

  @override
  void dispose() {
    DevAuth.devModeEnabled.removeListener(_handleDevModeChanged);
    _debugLog.log('disposed selected=$_selectedModeKey');
    super.dispose();
  }

  Future<void> _resolveDeveloperState() async {
    final loggedIn = await DevAuth.isDeveloperLoggedIn();
    final modeEnabled = await DevAuth.isDevModeEnabled();
    if (!mounted) return;
    setState(() {
      _developerLoggedIn = loggedIn;
      _devModeEnabled = modeEnabled;
    });
    _debugLog.log(
      'developer_state loggedIn=$loggedIn modeEnabled=$modeEnabled',
    );
  }

  void _handleDevModeChanged() {
    if (!mounted) return;
    final value = DevAuth.devModeEnabled.value;
    if (_devModeEnabled == value) return;
    setState(() => _devModeEnabled = value);
    _debugLog.log('developer_mode_changed enabled=$value');
  }

  _HeadquarterRailItem get _selectedItem {
    return _items.firstWhere(
      (item) => item.modeKey == _selectedModeKey,
      orElse: () => _items.first,
    );
  }

  void _select(String modeKey) {
    if (_selectedModeKey == modeKey) return;
    HapticFeedback.selectionClick();
    setState(() => _selectedModeKey = modeKey);
    _debugLog.log('rail_selected mode=$modeKey');
  }

  void _confirm() {
    if (_selectedModeKey == widget.currentModeKey) return;
    _debugLog.log(
      'switch_confirm from=${widget.currentModeKey} to=$_selectedModeKey',
    );
    Navigator.of(context).pop(
      HeadquarterModeDockResult.switchMode(_selectedModeKey),
    );
  }

  void _openSecondary() {
    if (!_developerLoggedIn) return;
    _debugLog.log('secondary_confirm');
    HapticFeedback.selectionClick();
    Navigator.of(context).pop(const HeadquarterModeDockResult.openSecondary());
  }

  Future<void> _showDeveloperStatus() async {
    if (!_devModeEnabled) return;
    _debugLog.log('status_dialog_open');
    await _debugLog.showStatus(context);
  }

  void _close() {
    _debugLog.log('close_button');
    HapticFeedback.lightImpact();
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final selected = _selectedItem;
    final isCurrent = selected.modeKey == widget.currentModeKey;

    return Column(
      children: [
        Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: tokens.accentContainer,
                borderRadius: BorderRadius.circular(CommonUiShapes.control),
                border: Border.all(color: tokens.borderSubtle),
              ),
              alignment: Alignment.center,
              child: Icon(
                Icons.swap_horiz_rounded,
                color: tokens.onAccentContainer,
                size: 21,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '헤드쿼터 모드 전환',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: tokens.textPrimary,
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    widget.currentModeKey,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: tokens.textSecondary,
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ],
              ),
            ),
            if (_devModeEnabled)
              CommonIconButton(
                icon: Icons.bug_report_rounded,
                tooltip: '상태',
                onPressed: _showDeveloperStatus,
                haptic: CommonHaptic.selection,
              ),
            const SizedBox(width: 4),
            CommonIconButton(
              icon: Icons.close_rounded,
              tooltip: '닫기',
              onPressed: _close,
              haptic: CommonHaptic.light,
            ),
          ],
        ),
        const SizedBox(height: 10),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: 62,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: tokens.surfaceOverlay,
                    borderRadius: BorderRadius.circular(CommonUiShapes.card),
                    border: Border.all(color: tokens.borderSubtle),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 5,
                    ),
                    child: Column(
                      children: [
                        Expanded(
                          child: SingleChildScrollView(
                            child: Column(
                              children: [
                                for (final item in _items) ...[
                                  _HeadquarterRailButton(
                                    item: item,
                                    selected: item.modeKey == _selectedModeKey,
                                    current: item.modeKey == widget.currentModeKey,
                                    onTap: () => _select(item.modeKey),
                                  ),
                                  if (item != _items.last)
                                    const SizedBox(height: 4),
                                ],
                              ],
                            ),
                          ),
                        ),
                        if (_developerLoggedIn) ...[
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: Divider(
                              height: 1,
                              color: tokens.borderSubtle,
                            ),
                          ),
                          _HeadquarterRailButton(
                            item: const _HeadquarterRailItem(
                              modeKey: 'secondary',
                              label: '운영',
                              title: '운영 관리',
                              icon: Icons.admin_panel_settings_rounded,
                            ),
                            selected: false,
                            current: false,
                            onTap: _openSecondary,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: tokens.canvas,
                    borderRadius: BorderRadius.circular(CommonUiShapes.card),
                    border: Border.all(color: tokens.borderSubtle),
                  ),
                  child: Column(
                    children: [
                      Expanded(
                        child: AnimatedSwitcher(
                          duration: reduceMotion
                              ? Duration.zero
                              : CommonUiMotion.component,
                          switchInCurve: CommonUiMotion.enter,
                          switchOutCurve: CommonUiMotion.exit,
                          transitionBuilder: (child, animation) {
                            if (reduceMotion) return child;
                            final curved = CurvedAnimation(
                              parent: animation,
                              curve: CommonUiMotion.enter,
                              reverseCurve: CommonUiMotion.exit,
                            );
                            return FadeTransition(
                              opacity: curved,
                              child: SlideTransition(
                                position: Tween<Offset>(
                                  begin: const Offset(.035, 0),
                                  end: Offset.zero,
                                ).animate(curved),
                                child: child,
                              ),
                            );
                          },
                          child: _HeadquarterModeContent(
                            key: ValueKey<String>(selected.modeKey),
                            item: selected,
                            current: isCurrent,
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(10),
                        child: CommonButton(
                          label: isCurrent ? '현재 모드' : '이 모드로 전환',
                          icon: isCurrent
                              ? Icons.check_circle_rounded
                              : Icons.swap_horiz_rounded,
                          onPressed: isCurrent ? null : _confirm,
                          expand: true,
                          haptic: CommonHaptic.selection,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _HeadquarterModeContent extends StatelessWidget {
  const _HeadquarterModeContent({
    super.key,
    required this.item,
    required this.current,
  });

  final _HeadquarterRailItem item;
  final bool current;

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 58,
              height: 58,
              decoration: BoxDecoration(
                color: tokens.accentContainer,
                borderRadius: BorderRadius.circular(CommonUiShapes.card),
                border: Border.all(color: tokens.borderSubtle),
              ),
              alignment: Alignment.center,
              child: Icon(
                item.icon,
                size: 28,
                color: tokens.onAccentContainer,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              item.title,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: tokens.textPrimary,
                    fontWeight: FontWeight.w800,
                  ),
            ),
            if (current) ...[
              const SizedBox(height: 8),
              _HeadquarterStatusBadge(
                label: '현재',
                color: tokens.accent,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _HeadquarterRailButton extends StatefulWidget {
  const _HeadquarterRailButton({
    required this.item,
    required this.selected,
    required this.current,
    required this.onTap,
  });

  final _HeadquarterRailItem item;
  final bool selected;
  final bool current;
  final VoidCallback onTap;

  @override
  State<_HeadquarterRailButton> createState() => _HeadquarterRailButtonState();
}

class _HeadquarterRailButtonState extends State<_HeadquarterRailButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final foreground = widget.selected
        ? tokens.onAccentContainer
        : widget.current
            ? tokens.accent
            : tokens.textSecondary;
    final background = widget.selected
        ? tokens.accentContainer
        : widget.current
            ? tokens.surfaceSelected
            : tokens.surfaceRaised;
    final borderColor = widget.selected
        ? tokens.accent
        : widget.current
            ? tokens.borderStrong
            : tokens.borderSubtle;

    return AnimatedScale(
      scale: _pressed ? .97 : 1,
      duration: reduceMotion ? Duration.zero : const Duration(milliseconds: 110),
      child: AnimatedContainer(
        duration: reduceMotion ? Duration.zero : CommonUiMotion.selection,
        height: 54,
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(CommonUiShapes.control),
          border: Border.all(
            color: borderColor,
            width: widget.selected ? 1.3 : 1,
          ),
        ),
        child: Material(
          color: tokens.transparent,
          borderRadius: BorderRadius.circular(CommonUiShapes.control),
          child: InkWell(
            onTap: widget.onTap,
            onTapDown: (_) => setState(() => _pressed = true),
            onTapCancel: () => setState(() => _pressed = false),
            onTapUp: (_) => setState(() => _pressed = false),
            borderRadius: BorderRadius.circular(CommonUiShapes.control),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(widget.item.icon, size: 18, color: foreground),
                const SizedBox(height: 3),
                Text(
                  widget.item.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: foreground,
                        fontSize: 9.5,
                        fontWeight: FontWeight.w800,
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

class _HeadquarterStatusBadge extends StatelessWidget {
  const _HeadquarterStatusBadge({
    required this.label,
    required this.color,
  });

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(.12),
        borderRadius: BorderRadius.circular(CommonUiShapes.pill),
        border: Border.all(color: color.withOpacity(.32)),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
            ),
      ),
    );
  }
}

class _HeadquarterRailItem {
  const _HeadquarterRailItem({
    required this.modeKey,
    required this.label,
    required this.title,
    required this.icon,
  });

  final String modeKey;
  final String label;
  final String title;
  final IconData icon;
}

class _HeadquarterDockDebugLog {
  final List<String> _lines = <String>[];

  void log(String message) {
    final line =
        '[HeadquarterModeSideDock][${DateTime.now().toIso8601String()}] $message';
    _lines.add(line);
    if (_lines.length > 120) {
      _lines.removeRange(0, _lines.length - 120);
    }
    debugPrint(line);
  }

  String get debugPrintCode => _lines
      .map((line) => 'debugPrint(${jsonEncode(line)});')
      .join('\n');

  Future<void> showStatus(BuildContext context) async {
    await StatusDialog.showSuccess(
      context,
      title: '헤드쿼터 모드 상태',
      description: _lines.join('\n'),
      copyText: debugPrintCode,
      copyButtonLabel: 'debugPrint 코드 복사',
      visibleDuration: const Duration(seconds: 60),
      useCommonUi: true,
    );
  }
}
