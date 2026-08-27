import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../design_system/common_ui/common_ui_theme.dart';
import '../application/app_command_diagnostics.dart';
import '../application/app_command_executor.dart';

enum _CommandBarState {
  idle,
  running,
  success,
  failure,
}

class CommonCommandBar extends StatefulWidget {
  const CommonCommandBar({
    super.key,
    this.maxWidth = 280,
  });

  final double maxWidth;

  @override
  State<CommonCommandBar> createState() => _CommonCommandBarState();
}

class _CommonCommandBarState extends State<CommonCommandBar>
    with SingleTickerProviderStateMixin {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  late final AnimationController _shakeController;
  late final Animation<double> _shakeAnimation;
  _CommandBarState _state = _CommandBarState.idle;
  bool _hovered = false;
  bool _pressed = false;
  bool _focused = false;

  bool get _busy => _state == _CommandBarState.running;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_handleFocusChange);
    _shakeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 180),
    );
    _shakeAnimation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween<double>(begin: 0, end: -3), weight: 1),
      TweenSequenceItem(tween: Tween<double>(begin: -3, end: 3), weight: 2),
      TweenSequenceItem(tween: Tween<double>(begin: 3, end: -2), weight: 2),
      TweenSequenceItem(tween: Tween<double>(begin: -2, end: 2), weight: 2),
      TweenSequenceItem(tween: Tween<double>(begin: 2, end: 0), weight: 1),
    ]).animate(CurvedAnimation(
      parent: _shakeController,
      curve: Curves.easeInOut,
    ));
  }

  void _handleFocusChange() {
    if (!mounted) return;
    setState(() => _focused = _focusNode.hasFocus);
  }

  @override
  void dispose() {
    _focusNode.removeListener(_handleFocusChange);
    _controller.dispose();
    _focusNode.dispose();
    _shakeController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    final raw = _controller.text;
    if (raw.trim().isEmpty) {
      HapticFeedback.mediumImpact();
      setState(() => _state = _CommandBarState.failure);
      await _shakeController.forward(from: 0);
      if (!mounted) return;
      _focusNode.requestFocus();
      return;
    }

    HapticFeedback.selectionClick();
    _focusNode.unfocus();
    setState(() => _state = _CommandBarState.running);

    final result = await AppCommandExecutor.execute(context, raw);
    if (!mounted) return;

    if (result.succeeded) {
      HapticFeedback.lightImpact();
      setState(() => _state = _CommandBarState.success);
      await Future<void>.delayed(const Duration(milliseconds: 360));
      if (!mounted) return;
      _controller.clear();
      setState(() => _state = _CommandBarState.idle);
      return;
    }

    HapticFeedback.mediumImpact();
    setState(() => _state = _CommandBarState.failure);
    await _shakeController.forward(from: 0);
    if (!mounted) return;
    _focusNode.requestFocus();
  }

  Future<void> _showStatus() async {
    await AppCommandDiagnostics.showStatus(
      context,
      title: 'Command Status',
      description: '최근 Command Registry 실행 로그입니다.',
    );
  }

  Widget _buildActionIcon(CommonUiTokens tokens, bool reduceMotion) {
    final Widget child;
    switch (_state) {
      case _CommandBarState.running:
        child = SizedBox(
          key: const ValueKey<String>('running'),
          width: 17,
          height: 17,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: tokens.accent,
          ),
        );
        break;
      case _CommandBarState.success:
        child = Icon(
          Icons.check_rounded,
          key: const ValueKey<String>('success'),
          size: 19,
          color: tokens.success,
        );
        break;
      case _CommandBarState.failure:
        child = Icon(
          Icons.error_outline_rounded,
          key: const ValueKey<String>('failure'),
          size: 18,
          color: tokens.danger,
        );
        break;
      case _CommandBarState.idle:
        child = Icon(
          Icons.keyboard_return_rounded,
          key: const ValueKey<String>('idle'),
          size: 18,
          color: _controller.text.trim().isEmpty
              ? tokens.iconDisabled
              : tokens.accent,
        );
        break;
    }

    return AnimatedSwitcher(
      duration: reduceMotion ? Duration.zero : CommonUiMotion.instant,
      switchInCurve: CommonUiMotion.enter,
      switchOutCurve: CommonUiMotion.exit,
      transitionBuilder: (child, animation) {
        return FadeTransition(
          opacity: animation,
          child: ScaleTransition(
            scale: Tween<double>(begin: .92, end: 1).animate(animation),
            child: child,
          ),
        );
      },
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final active = _focused || _hovered;
    final error = _state == _CommandBarState.failure;
    final borderColor = error
        ? tokens.danger
        : _focused
            ? tokens.focusRing
            : active
                ? tokens.borderStrong
                : tokens.borderSubtle;
    final background = _pressed
        ? tokens.accentContainer
        : active
            ? tokens.surfaceRaised
            : tokens.surface;

    final screenWidth = MediaQuery.sizeOf(context).width;
    final responsiveMaxWidth =
        (screenWidth - 252).clamp(132.0, widget.maxWidth).toDouble();

    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: responsiveMaxWidth),
      child: Semantics(
        textField: true,
        label: '고정 명령어 입력',
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onLongPress: _showStatus,
          child: MouseRegion(
            onEnter: (_) => setState(() => _hovered = true),
            onExit: (_) => setState(() => _hovered = false),
            child: AnimatedBuilder(
              animation: _shakeAnimation,
              builder: (context, child) {
                return Transform.translate(
                  offset: Offset(reduceMotion ? 0 : _shakeAnimation.value, 0),
                  child: child,
                );
              },
              child: AnimatedScale(
                scale: _pressed ? .985 : 1,
                duration: reduceMotion ? Duration.zero : CommonUiMotion.press,
                curve: CommonUiMotion.enter,
                child: AnimatedContainer(
                  duration: reduceMotion
                      ? Duration.zero
                      : CommonUiMotion.selection,
                  curve: CommonUiMotion.enter,
                  height: 38,
                  padding: const EdgeInsets.fromLTRB(10, 2, 4, 2),
                  decoration: BoxDecoration(
                    color: background,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: borderColor),
                    boxShadow: [
                      if (_focused)
                        BoxShadow(
                          color: tokens.focusRing,
                          blurRadius: 0,
                          spreadRadius: 1.5,
                        )
                      else if (_hovered)
                        BoxShadow(
                          color: tokens.shadow,
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Text(
                        '>',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              color: tokens.accent,
                              fontWeight: FontWeight.w900,
                              fontFamily: 'monospace',
                            ),
                      ),
                      const SizedBox(width: 7),
                      Expanded(
                        child: TextField(
                          controller: _controller,
                          focusNode: _focusNode,
                          enabled: !_busy,
                          textInputAction: TextInputAction.done,
                          autocorrect: false,
                          enableSuggestions: false,
                          textCapitalization: TextCapitalization.none,
                          cursorColor: tokens.accent,
                          style:
                              Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    color: tokens.textPrimary,
                                    fontWeight: FontWeight.w700,
                                    fontFamily: 'monospace',
                                    letterSpacing: .1,
                                  ),
                          decoration: const InputDecoration(
                            isDense: true,
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            contentPadding: EdgeInsets.zero,
                          ),
                          onChanged: (_) {
                            if (_state == _CommandBarState.failure) {
                              setState(() => _state = _CommandBarState.idle);
                            } else {
                              setState(() {});
                            }
                          },
                          onSubmitted: (_) => _submit(),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Semantics(
                        button: true,
                        enabled: !_busy && _controller.text.trim().isNotEmpty,
                        label: '명령 실행',
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTapDown: (_) {
                            if (!_busy) setState(() => _pressed = true);
                          },
                          onTapCancel: () => setState(() => _pressed = false),
                          onTapUp: (_) => setState(() => _pressed = false),
                          onTap: _busy ? null : _submit,
                          child: SizedBox(
                            width: 30,
                            height: 30,
                            child: Center(
                              child: _buildActionIcon(tokens, reduceMotion),
                            ),
                          ),
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
