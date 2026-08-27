import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../design_system/common_ui/common_ui_theme.dart';
import '../domain/plate_identity_focus_target.dart';
import '../keypad/plate_kor_keypad.dart';
import '../keypad/plate_num_keypad.dart';

class PlateIdentityInputPanel extends StatefulWidget {
  const PlateIdentityInputPanel({
    super.key,
    required this.frontController,
    required this.middleController,
    required this.backController,
    this.initialThreeDigit,
    this.initialFocusTarget,
    this.onFocusTargetChanged,
    this.onFrontDigitModeChanged,
    this.onDebug,
    this.showValidationErrors = false,
    this.keypadHeight = 238,
    this.segmentMinHeight = 68,
    this.segmentHorizontalPadding = 10,
    this.segmentVerticalPadding = 8,
  });

  final TextEditingController frontController;
  final TextEditingController middleController;
  final TextEditingController backController;
  final bool? initialThreeDigit;
  final PlateIdentityFocusTarget? initialFocusTarget;
  final ValueChanged<PlateIdentityFocusTarget>? onFocusTargetChanged;
  final ValueChanged<bool>? onFrontDigitModeChanged;
  final ValueChanged<String>? onDebug;
  final bool showValidationErrors;
  final double keypadHeight;
  final double segmentMinHeight;
  final double segmentHorizontalPadding;
  final double segmentVerticalPadding;

  @override
  State<PlateIdentityInputPanel> createState() =>
      _PlateIdentityInputPanelState();
}

class _PlateIdentityInputPanelState extends State<PlateIdentityInputPanel> {
  late PlateIdentityFocusTarget _segment;
  late bool _threeDigit;
  int _inputSessionRevision = 0;

  @override
  void initState() {
    super.initState();
    final front = widget.frontController.text.trim();
    _threeDigit = widget.initialThreeDigit ?? (front.isEmpty || front.length == 3);
    _segment = widget.initialFocusTarget ??
        resolvePlateIdentityFocusTarget(
          front: widget.frontController.text,
          middle: widget.middleController.text,
          back: widget.backController.text,
          requiredFrontLength: _threeDigit ? 3 : 2,
        );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      widget.onFocusTargetChanged?.call(_segment);
      _debug('identity_editor=initial_focus target=${_segment.name}');
    });
  }

  void _debug(String message) {
    final callback = widget.onDebug;
    if (callback != null) {
      callback(message);
      return;
    }
    debugPrint('[PlateIdentityInputPanel] $message');
  }

  TextEditingController _controllerFor(PlateIdentityFocusTarget segment) {
    switch (segment) {
      case PlateIdentityFocusTarget.front:
        return widget.frontController;
      case PlateIdentityFocusTarget.middle:
        return widget.middleController;
      case PlateIdentityFocusTarget.back:
        return widget.backController;
    }
  }

  PlateIdentityFocusTarget _resolveFocus({
    PlateIdentityFocusTarget fallback = PlateIdentityFocusTarget.front,
  }) {
    return resolvePlateIdentityFocusTarget(
      front: widget.frontController.text,
      middle: widget.middleController.text,
      back: widget.backController.text,
      requiredFrontLength: _threeDigit ? 3 : 2,
      fallback: fallback,
    );
  }

  void _select(PlateIdentityFocusTarget segment) {
    if (!mounted) return;
    setState(() {
      _segment = segment;
      _inputSessionRevision++;
    });
    widget.onFocusTargetChanged?.call(segment);
    _debug('identity_editor=segment selected=${segment.name}');
  }

  void _handleSegmentTap(PlateIdentityFocusTarget segment) {
    final controller = _controllerFor(segment);
    final previous = controller.text.trim();
    setState(() {
      _segment = segment;
      _inputSessionRevision++;
    });
    if (controller.text.isNotEmpty) controller.clear();
    widget.onFocusTargetChanged?.call(segment);
    HapticFeedback.selectionClick();
    _debug(
      'identity_editor=segment_tap_clear target=${segment.name} previous=$previous',
    );
  }

  void _resetAll() {
    widget.frontController.clear();
    widget.middleController.clear();
    widget.backController.clear();
    setState(() {
      _segment = PlateIdentityFocusTarget.front;
      _inputSessionRevision++;
    });
    widget.onFocusTargetChanged?.call(PlateIdentityFocusTarget.front);
    HapticFeedback.selectionClick();
    _debug('identity_editor=reset');
  }

  void _advanceAfterInput(PlateIdentityFocusTarget current) {
    final next = _resolveFocus(fallback: current);
    _select(next);
    _debug('identity_editor=advance current=${current.name} next=${next.name}');
  }

  bool _segmentInvalid(PlateIdentityFocusTarget segment) {
    if (!widget.showValidationErrors) return false;
    switch (segment) {
      case PlateIdentityFocusTarget.front:
        final front = widget.frontController.text.trim();
        return front.length != (_threeDigit ? 3 : 2) ||
            !RegExp(r'^\d+$').hasMatch(front);
      case PlateIdentityFocusTarget.middle:
        return !RegExp(r'^[가-힣]$')
            .hasMatch(widget.middleController.text.trim());
      case PlateIdentityFocusTarget.back:
        return !RegExp(r'^\d{4}$').hasMatch(widget.backController.text.trim());
    }
  }

  Widget _segmentTile(
    BuildContext context, {
    required PlateIdentityFocusTarget segment,
    required String label,
    required String value,
    required int flex,
  }) {
    final tokens = CommonUiTheme.of(context);
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final selected = _segment == segment;
    final invalid = _segmentInvalid(segment);
    final borderColor = invalid
        ? tokens.danger
        : selected
            ? tokens.accent
            : tokens.borderSubtle;
    return Expanded(
      flex: flex,
      child: Semantics(
        button: true,
        selected: selected,
        label: '$label ${value.isEmpty ? '미입력' : value}',
        child: InkWell(
          borderRadius: BorderRadius.circular(CommonUiShapes.control),
          onTap: () => _handleSegmentTap(segment),
          child: AnimatedContainer(
            duration: reduceMotion ? Duration.zero : CommonUiMotion.selection,
            curve: CommonUiMotion.standard,
            constraints: BoxConstraints(minHeight: widget.segmentMinHeight),
            padding: EdgeInsets.symmetric(
              horizontal: widget.segmentHorizontalPadding,
              vertical: widget.segmentVerticalPadding,
            ),
            decoration: BoxDecoration(
              color: selected ? tokens.accentContainer : tokens.surface,
              borderRadius: BorderRadius.circular(CommonUiShapes.control),
              border: Border.all(
                color: borderColor,
                width: selected || invalid ? 1.5 : 1,
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: invalid
                            ? tokens.danger
                            : selected
                                ? tokens.accent
                                : tokens.textSecondary,
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(height: 4),
                AnimatedSwitcher(
                  duration:
                      reduceMotion ? Duration.zero : CommonUiMotion.selection,
                  child: Text(
                    value.isEmpty ? '—' : value,
                    key: ValueKey<String>(value),
                    maxLines: 1,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: tokens.textPrimary,
                          fontWeight: FontWeight.w900,
                          letterSpacing: .5,
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

  Widget _buildKeypad() {
    switch (_segment) {
      case PlateIdentityFocusTarget.front:
        return PlateNumKeypad(
          key: ValueKey<String>(
            'front:${_threeDigit ? 3 : 2}:$_inputSessionRevision',
          ),
          controller: widget.frontController,
          maxLength: _threeDigit ? 3 : 2,
          replaceExistingOnFirstInput: true,
          debugName: 'front',
          onDebug: _debug,
          onComplete: () => _advanceAfterInput(PlateIdentityFocusTarget.front),
          onChangeFrontDigitMode: (threeDigits) {
            widget.frontController.clear();
            setState(() {
              _threeDigit = threeDigits;
              _segment = PlateIdentityFocusTarget.front;
              _inputSessionRevision++;
            });
            widget.onFrontDigitModeChanged?.call(threeDigits);
            widget.onFocusTargetChanged?.call(PlateIdentityFocusTarget.front);
            HapticFeedback.selectionClick();
            _debug(
              'identity_editor=front_mode digits=${threeDigits ? 3 : 2}',
            );
          },
          enableDigitModeSwitch: true,
          height: widget.keypadHeight,
        );
      case PlateIdentityFocusTarget.middle:
        return PlateKorKeypad(
          key: ValueKey<String>('middle:$_inputSessionRevision'),
          controller: widget.middleController,
          replaceExistingOnFirstInput: true,
          debugName: 'middle',
          onDebug: _debug,
          onComplete: () => _advanceAfterInput(PlateIdentityFocusTarget.middle),
          height: widget.keypadHeight,
        );
      case PlateIdentityFocusTarget.back:
        return PlateNumKeypad(
          key: ValueKey<String>('back:$_inputSessionRevision'),
          controller: widget.backController,
          maxLength: 4,
          replaceExistingOnFirstInput: true,
          debugName: 'back',
          onDebug: _debug,
          enableDigitModeSwitch: false,
          onComplete: () {
            HapticFeedback.selectionClick();
            _advanceAfterInput(PlateIdentityFocusTarget.back);
          },
          onReset: _resetAll,
          height: widget.keypadHeight,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AnimatedBuilder(
          animation: Listenable.merge(
            <Listenable>[
              widget.frontController,
              widget.middleController,
              widget.backController,
            ],
          ),
          builder: (context, _) {
            return Row(
              children: [
                _segmentTile(
                  context,
                  segment: PlateIdentityFocusTarget.front,
                  label: '앞자리',
                  value: widget.frontController.text.trim(),
                  flex: 3,
                ),
                const SizedBox(width: 8),
                _segmentTile(
                  context,
                  segment: PlateIdentityFocusTarget.middle,
                  label: '한글',
                  value: widget.middleController.text.trim(),
                  flex: 2,
                ),
                const SizedBox(width: 8),
                _segmentTile(
                  context,
                  segment: PlateIdentityFocusTarget.back,
                  label: '뒷자리',
                  value: widget.backController.text.trim(),
                  flex: 4,
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 10),
        ClipRect(
          child: AnimatedSwitcher(
            duration: reduceMotion ? Duration.zero : CommonUiMotion.component,
            reverseDuration:
                reduceMotion ? Duration.zero : CommonUiMotion.selection,
            switchInCurve: CommonUiMotion.enter,
            switchOutCurve: CommonUiMotion.exit,
            transitionBuilder: (child, animation) {
              final slide = Tween<Offset>(
                begin: const Offset(.025, .035),
                end: Offset.zero,
              ).animate(animation);
              return FadeTransition(
                opacity: animation,
                child: SlideTransition(position: slide, child: child),
              );
            },
            child: KeyedSubtree(
              key: ValueKey<String>(
                '${_segment.name}:${_threeDigit ? 3 : 2}:$_inputSessionRevision',
              ),
              child: _buildKeypad(),
            ),
          ),
        ),
      ],
    );
  }
}
