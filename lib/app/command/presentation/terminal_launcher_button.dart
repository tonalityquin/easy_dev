import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../application/app_command_diagnostics.dart';
import '../../terminal/presentation/parkinworkin_terminal_navigator.dart';

class TerminalLauncherButton extends StatefulWidget {
  const TerminalLauncherButton({
    super.key,
    this.source = 'app_bar',
  });

  final String source;

  @override
  State<TerminalLauncherButton> createState() =>
      _TerminalLauncherButtonState();
}

class _TerminalLauncherButtonState extends State<TerminalLauncherButton> {
  bool _hovered = false;
  bool _pressed = false;
  bool _focused = false;
  bool _opening = false;

  Future<void> _open() async {
    if (_opening) return;
    HapticFeedback.selectionClick();
    setState(() => _opening = true);
    try {
      await showParkinWorkinTerminal(context, source: widget.source);
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  Future<void> _showStatus() async {
    await AppCommandDiagnostics.showStatus(
      context,
      title: 'Command Status',
      description: 'Terminal session 및 Command 실행 로그입니다.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final background = _pressed
        ? const Color(0xFF5B1A47)
        : _hovered || _focused
            ? const Color(0xFF421333)
            : const Color(0xFF300A24);
    final border = _focused
        ? const Color(0xFF8AE234)
        : _hovered
            ? const Color(0xFF8B5B7E)
            : const Color(0xFF5E3A55);

    return Semantics(
      button: true,
      enabled: !_opening,
      label: 'ParkinWorkin Terminal 열기',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onLongPress: _showStatus,
        onTapDown: (_) {
          if (!_opening) setState(() => _pressed = true);
        },
        onTapCancel: () => setState(() => _pressed = false),
        onTapUp: (_) => setState(() => _pressed = false),
        onTap: _opening ? null : _open,
        child: Focus(
          onFocusChange: (value) => setState(() => _focused = value),
          onKeyEvent: (_, event) {
            if (event is KeyDownEvent &&
                (event.logicalKey == LogicalKeyboardKey.enter ||
                    event.logicalKey == LogicalKeyboardKey.space)) {
              if (!_opening) {
                _open();
              }
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          child: MouseRegion(
            onEnter: (_) => setState(() => _hovered = true),
            onExit: (_) => setState(() => _hovered = false),
            child: AnimatedScale(
              scale: _pressed ? .92 : 1,
              duration:
                  reduceMotion ? Duration.zero : const Duration(milliseconds: 110),
              curve: Curves.easeOutCubic,
              child: AnimatedContainer(
                duration:
                    reduceMotion ? Duration.zero : const Duration(milliseconds: 160),
                curve: Curves.easeOutCubic,
                width: 44,
                height: 34,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: background,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: border),
                  boxShadow: _hovered || _focused
                      ? const [
                          BoxShadow(
                            color: Color(0x55000000),
                            blurRadius: 10,
                            offset: Offset(0, 4),
                          ),
                        ]
                      : const [],
                ),
                child: AnimatedSwitcher(
                  duration: reduceMotion
                      ? Duration.zero
                      : const Duration(milliseconds: 140),
                  child: _opening
                      ? const SizedBox(
                          key: ValueKey<String>('opening'),
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 1.7,
                            color: Color(0xFF8AE234),
                          ),
                        )
                      : const Text(
                          '>_',
                          key: ValueKey<String>('terminal'),
                          style: TextStyle(
                            color: Color(0xFF8AE234),
                            fontFamily: 'monospace',
                            fontSize: 14,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -.5,
                          ),
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
