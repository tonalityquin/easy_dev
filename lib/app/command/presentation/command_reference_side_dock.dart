import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../design_system/common_ui/common_ui_side_dock.dart';
import '../../../design_system/common_ui/common_ui_side_dock_frame.dart';
import '../../../design_system/common_ui/common_ui_theme.dart';
import '../application/app_command_definition.dart';
import '../application/app_command_diagnostics.dart';
import '../application/app_command_registry.dart';

Future<void> showCommandReferenceSideDock({
  required BuildContext context,
}) async {
  AppCommandDiagnostics.record(
    phase: 'help_open',
    input: 'help',
    normalized: 'help',
    command: 'help',
    result: 'opening',
  );
  await showCommonLeftSideDock<void>(
    context: context,
    barrierLabel: 'Command Reference',
    useRootNavigator: true,
    maxWidth: 420,
    widthFactor: .94,
    builder: (dockContext) => const _CommandReferenceDock(),
  );
  AppCommandDiagnostics.record(
    phase: 'help_close',
    input: 'help',
    normalized: 'help',
    command: 'help',
    result: 'closed',
  );
}

class _CommandReferenceDock extends StatelessWidget {
  const _CommandReferenceDock();

  @override
  Widget build(BuildContext context) {
    return CommonSideDockFrame(
      title: 'Command Reference',
      subtitle: '${AppCommandRegistry.visibleCommands.length} commands · 탭하면 명령어를 복사합니다.',
      icon: Icons.terminal_rounded,
      onClose: () => Navigator.of(context).pop(),
      onLongPress: () => AppCommandDiagnostics.showStatus(
        context,
        title: 'Command Status',
        description: '현재 Command Registry와 최근 실행 로그입니다.',
      ),
      child: ListView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(2, 2, 8, 10),
        children: [
          for (var categoryIndex = 0;
              categoryIndex < AppCommandRegistry.categories.length;
              categoryIndex++) ...[
            if (categoryIndex > 0) const SizedBox(height: 14),
            CommonSideDockSection(
              title: AppCommandRegistry.categories[categoryIndex],
              subtitle: categoryIndex == 0
                  ? '고정 명령어를 정확히 입력한 뒤 Enter로 실행합니다.'
                  : '개발자 기능을 활성화하는 명령입니다.',
              order: categoryIndex + 1,
              child: Column(
                children: [
                  for (var commandIndex = 0;
                      commandIndex <
                          AppCommandRegistry.byCategory(
                            AppCommandRegistry.categories[categoryIndex],
                          ).length;
                      commandIndex++) ...[
                    _CommandReferenceRow(
                      definition: AppCommandRegistry.byCategory(
                        AppCommandRegistry.categories[categoryIndex],
                      )[commandIndex],
                      order: commandIndex + 2,
                    ),
                    if (commandIndex <
                        AppCommandRegistry.byCategory(
                                  AppCommandRegistry.categories[categoryIndex],
                                ).length -
                            1)
                      const SizedBox(height: 8),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _CommandReferenceRow extends StatefulWidget {
  const _CommandReferenceRow({
    required this.definition,
    required this.order,
  });

  final AppCommandDefinition definition;
  final int order;

  @override
  State<_CommandReferenceRow> createState() => _CommandReferenceRowState();
}

class _CommandReferenceRowState extends State<_CommandReferenceRow> {
  bool _pressed = false;
  bool _hovered = false;
  bool _focused = false;
  bool _copied = false;

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.definition.command));
    HapticFeedback.selectionClick();
    AppCommandDiagnostics.record(
      phase: 'help_copy',
      input: widget.definition.command,
      normalized: widget.definition.command,
      command: widget.definition.command,
      result: 'copied',
    );
    if (!mounted) return;
    setState(() => _copied = true);
    await Future<void>.delayed(const Duration(milliseconds: 720));
    if (!mounted) return;
    setState(() => _copied = false);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final background = _pressed
        ? tokens.accentContainer
        : _hovered || _focused
            ? tokens.surfaceSelected
            : tokens.surfaceRaised;

    return CommonSideDockReveal(
      order: widget.order,
      offsetY: 5,
      child: FocusableActionDetector(
        onShowHoverHighlight: (value) {
          if (mounted) setState(() => _hovered = value);
        },
        onShowFocusHighlight: (value) {
          if (mounted) setState(() => _focused = value);
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (_) => setState(() => _pressed = true),
          onTapCancel: () => setState(() => _pressed = false),
          onTapUp: (_) => setState(() => _pressed = false),
          onTap: _copy,
          child: AnimatedScale(
            scale: _pressed ? .985 : 1,
            duration: reduceMotion ? Duration.zero : CommonUiMotion.press,
            curve: CommonUiMotion.enter,
            child: AnimatedContainer(
              duration:
                  reduceMotion ? Duration.zero : CommonUiMotion.selection,
              curve: CommonUiMotion.enter,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
              decoration: BoxDecoration(
                color: background,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: _focused ? tokens.focusRing : tokens.borderSubtle,
                ),
                boxShadow: [
                  if (_hovered && !_pressed)
                    BoxShadow(
                      color: tokens.shadow,
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                ],
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '>',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: tokens.accent,
                          fontWeight: FontWeight.w900,
                          fontFamily: 'monospace',
                        ),
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.definition.command,
                          style:
                              Theme.of(context).textTheme.titleSmall?.copyWith(
                                    color: tokens.textPrimary,
                                    fontWeight: FontWeight.w800,
                                    fontFamily: 'monospace',
                                  ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          widget.definition.description,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: tokens.textSecondary,
                                height: 1.25,
                              ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  AnimatedSwitcher(
                    duration:
                        reduceMotion ? Duration.zero : CommonUiMotion.instant,
                    child: Icon(
                      _copied ? Icons.check_rounded : Icons.copy_rounded,
                      key: ValueKey<bool>(_copied),
                      size: 17,
                      color: _copied ? tokens.success : tokens.iconSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
