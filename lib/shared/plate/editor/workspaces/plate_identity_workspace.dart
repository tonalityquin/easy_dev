import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../design_system/common_ui/common_ui_components.dart';
import '../../../../design_system/common_ui/common_ui_theme.dart';
import '../domain/plate_identity_focus_target.dart';
import '../keypad/plate_kor_keypad.dart';
import '../keypad/plate_num_keypad.dart';

class PlateIdentityWorkspace extends StatefulWidget {
  const PlateIdentityWorkspace({
    super.key,
    required this.frontController,
    required this.middleController,
    required this.backController,
    required this.pending,
    required this.onAutoApply,
    required this.onExit,
    this.description = '차량번호의 앞자리, 한글, 뒷자리를 입력합니다.',
    this.onDebug,
    this.initialThreeDigit,
    this.initialFocusTarget,
    this.middleSuggestions = const <String>[],
    this.onFocusTargetChanged,
    this.plateAnchorKey,
  });

  final TextEditingController frontController;
  final TextEditingController middleController;
  final TextEditingController backController;
  final bool pending;
  final Future<void> Function() onAutoApply;
  final VoidCallback onExit;
  final String description;
  final ValueChanged<String>? onDebug;
  final bool? initialThreeDigit;
  final PlateIdentityFocusTarget? initialFocusTarget;
  final List<String> middleSuggestions;
  final ValueChanged<PlateIdentityFocusTarget>? onFocusTargetChanged;
  final Key? plateAnchorKey;

  @override
  State<PlateIdentityWorkspace> createState() => _PlateIdentityWorkspaceState();
}

class _PlateIdentityWorkspaceState extends State<PlateIdentityWorkspace> {
  late PlateIdentityFocusTarget _segment;
  late bool _threeDigit;
  late bool _pending;
  late List<String> _middleSuggestions;
  int _inputSessionRevision = 0;
  bool _autoApplyScheduled = false;
  bool _autoApplying = false;

  bool get _valid {
    final front = widget.frontController.text.trim();
    final middle = widget.middleController.text.trim();
    final back = widget.backController.text.trim();
    final requiredFrontLength = _threeDigit ? 3 : 2;
    return front.length == requiredFrontLength &&
        RegExp(r'^\d+$').hasMatch(front) &&
        RegExp(r'^[가-힣]$').hasMatch(middle) &&
        RegExp(r'^\d{4}$').hasMatch(back);
  }

  @override
  void initState() {
    super.initState();
    final initialFront = widget.frontController.text.trim();
    _threeDigit = widget.initialThreeDigit ??
        (initialFront.isEmpty || initialFront.length == 3);
    _pending = widget.pending;
    _middleSuggestions = _normalizeSuggestions(widget.middleSuggestions);
    _segment = widget.initialFocusTarget ??
        resolvePlateIdentityFocusTarget(
          front: widget.frontController.text,
          middle: widget.middleController.text,
          back: widget.backController.text,
          requiredFrontLength: _threeDigit ? 3 : 2,
        );
    widget.frontController.addListener(_markChanged);
    widget.middleController.addListener(_markChanged);
    widget.backController.addListener(_markChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      widget.onFocusTargetChanged?.call(_segment);
      _debug('identity_editor=initial_focus target=${_segment.name}');
    });
  }

  @override
  void dispose() {
    widget.frontController.removeListener(_markChanged);
    widget.middleController.removeListener(_markChanged);
    widget.backController.removeListener(_markChanged);
    super.dispose();
  }

  List<String> _normalizeSuggestions(List<String> values) {
    final seen = <String>{};
    final result = <String>[];
    for (final value in values) {
      final normalized = value.trim();
      if (normalized.isEmpty || !seen.add(normalized)) continue;
      result.add(normalized);
    }
    return result;
  }

  void _debug(String message) {
    final onDebug = widget.onDebug;
    if (onDebug != null) {
      onDebug(message);
      return;
    }
    debugPrint('[PlateIdentityWorkspace] $message');
  }

  void _markChanged() {
    if (!mounted) return;
    final clearSuggestions = _middleSuggestions.isNotEmpty &&
        widget.middleController.text.trim().isNotEmpty;
    setState(() {
      _pending = true;
      if (clearSuggestions) _middleSuggestions = const <String>[];
    });
    _scheduleAutoApply('controller_changed');
  }

  void _scheduleAutoApply(String reason) {
    if (_autoApplyScheduled || _autoApplying) return;
    _autoApplyScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      _autoApplyScheduled = false;
      if (!mounted || _autoApplying || !_pending) return;
      final valid = _valid;
      _debug(
        'identity_editor=completion_check complete=$valid reason=$reason frontLength=${widget.frontController.text.trim().length} middleLength=${widget.middleController.text.trim().length} backLength=${widget.backController.text.trim().length}',
      );
      if (!valid) return;
      setState(() => _autoApplying = true);
      HapticFeedback.mediumImpact();
      _debug(
        'identity_editor=auto_apply_start plate=${widget.frontController.text.trim()}-${widget.middleController.text.trim()}-${widget.backController.text.trim()}',
      );
      try {
        await widget.onAutoApply();
        _debug('identity_editor=auto_apply_complete');
      } catch (error, stackTrace) {
        _debug('identity_editor=auto_apply_failed error=$error\n$stackTrace');
        if (mounted) setState(() => _autoApplying = false);
      }
    });
  }

  void _select(PlateIdentityFocusTarget segment) {
    setState(() {
      _segment = segment;
      _inputSessionRevision++;
    });
    widget.onFocusTargetChanged?.call(segment);
    _debug('identity_editor=segment selected=${segment.name}');
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

  void _handleSegmentTap(PlateIdentityFocusTarget segment) {
    final controller = _controllerFor(segment);
    final previous = controller.text.trim();
    setState(() {
      _segment = segment;
      _pending = true;
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
      _middleSuggestions = const <String>[];
      _inputSessionRevision++;
    });
    widget.onFocusTargetChanged?.call(PlateIdentityFocusTarget.front);
    _debug('identity_editor=reset');
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
    return Expanded(
      flex: flex,
      child: Semantics(
        button: true,
        selected: selected,
        label: '$label ${value.isEmpty ? '미입력' : value}',
        child: InkWell(
          borderRadius: BorderRadius.circular(CommonUiShapes.control),
          onTap: _autoApplying ? null : () => _handleSegmentTap(segment),
          child: AnimatedContainer(
            duration: reduceMotion
                ? Duration.zero
                : const Duration(milliseconds: 150),
            curve: Curves.easeOutCubic,
            constraints: const BoxConstraints(minHeight: 76),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: selected ? tokens.accentContainer : tokens.surface,
              borderRadius: BorderRadius.circular(CommonUiShapes.control),
              border: Border.all(
                color: selected ? tokens.accent : tokens.borderSubtle,
                width: selected ? 1.5 : 1,
              ),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  label,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color:
                            selected ? tokens.accent : tokens.textSecondary,
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(height: 5),
                Text(
                  value.isEmpty ? '—' : value,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: tokens.textPrimary,
                        fontWeight: FontWeight.w900,
                        letterSpacing: .6,
                      ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _advanceAfterInput(PlateIdentityFocusTarget current) {
    final next = _resolveFocus(fallback: current);
    _select(next);
    _debug('identity_editor=advance current=${current.name} next=${next.name}');
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
              _pending = true;
              _inputSessionRevision++;
            });
            widget.onFocusTargetChanged?.call(PlateIdentityFocusTarget.front);
            _debug(
              'identity_editor=front_mode digits=${threeDigits ? 3 : 2}',
            );
          },
          enableDigitModeSwitch: true,
          height: 238,
        );
      case PlateIdentityFocusTarget.middle:
        return PlateKorKeypad(
          key: ValueKey<String>('middle:$_inputSessionRevision'),
          controller: widget.middleController,
          replaceExistingOnFirstInput: true,
          debugName: 'middle',
          onDebug: _debug,
          onComplete: () => _advanceAfterInput(PlateIdentityFocusTarget.middle),
          height: 238,
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
          height: 238,
        );
    }
  }

  void _selectMiddleSuggestion(String value) {
    widget.middleController.text = value.trim();
    widget.middleController.selection = TextSelection.collapsed(
      offset: widget.middleController.text.length,
    );
    final next = _resolveFocus(fallback: PlateIdentityFocusTarget.middle);
    setState(() {
      _middleSuggestions = const <String>[];
      _pending = true;
      _segment = next;
      _inputSessionRevision++;
    });
    widget.onFocusTargetChanged?.call(next);
    HapticFeedback.selectionClick();
    _debug(
      'identity_editor=middle_suggestion_selected value=${value.trim()} next=${next.name}',
    );
    _scheduleAutoApply('middle_suggestion');
  }

  Widget _buildMiddleSuggestions(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final visible = _segment == PlateIdentityFocusTarget.middle &&
        _middleSuggestions.isNotEmpty;
    return AnimatedSwitcher(
      duration:
          reduceMotion ? Duration.zero : const Duration(milliseconds: 150),
      reverseDuration:
          reduceMotion ? Duration.zero : const Duration(milliseconds: 120),
      child: visible
          ? Container(
              key: ValueKey<String>(_middleSuggestions.join('|')),
              width: double.infinity,
              margin: const EdgeInsets.only(top: 8),
              padding: const EdgeInsets.fromLTRB(10, 9, 10, 10),
              decoration: BoxDecoration(
                color: tokens.surfaceOverlay,
                borderRadius: BorderRadius.circular(CommonUiShapes.control),
                border: Border.all(color: tokens.borderSubtle),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'OCR 한글 후보',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          color: tokens.textSecondary,
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  const SizedBox(height: 7),
                  Wrap(
                    spacing: 7,
                    runSpacing: 7,
                    children: _middleSuggestions
                        .map(
                          (value) => ActionChip(
                            label: Text(value),
                            onPressed: _autoApplying
                                ? null
                                : () => _selectMiddleSuggestion(value),
                          ),
                        )
                        .toList(growable: false),
                  ),
                ],
              ),
            )
          : const SizedBox.shrink(
              key: ValueKey<String>('no_middle_suggestions'),
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    return Container(
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: tokens.borderSubtle),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 12, 8),
            child: Row(
              children: [
                CommonIconButton(
                  icon: Icons.arrow_back_rounded,
                  tooltip: '차량 정보로',
                  size: 36,
                  iconSize: 18,
                  onPressed: _autoApplying ? null : widget.onExit,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '번호판 입력',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              color: tokens.textPrimary,
                              fontWeight: FontWeight.w900,
                            ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        widget.description,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: tokens.textSecondary,
                              height: 1.3,
                            ),
                      ),
                    ],
                  ),
                ),
                AnimatedSwitcher(
                  duration: reduceMotion
                      ? Duration.zero
                      : const Duration(milliseconds: 140),
                  child: _autoApplying
                      ? SizedBox(
                          key: const ValueKey<String>('identity_applying'),
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.2,
                            color: tokens.accent,
                          ),
                        )
                      : const SizedBox.shrink(
                          key: ValueKey<String>('identity_idle'),
                        ),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: tokens.borderSubtle),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    physics: const ClampingScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        KeyedSubtree(
                          key: widget.plateAnchorKey,
                          child: AnimatedBuilder(
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
                                    label: '문자',
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
                        ),
                        const SizedBox(height: 8),
                        AnimatedSwitcher(
                          duration: reduceMotion
                              ? Duration.zero
                              : const Duration(milliseconds: 140),
                          reverseDuration: reduceMotion
                              ? Duration.zero
                              : const Duration(milliseconds: 110),
                          child: Align(
                            key: ValueKey<PlateIdentityFocusTarget>(_segment),
                            alignment: Alignment.centerLeft,
                            child: Text(
                              _segment == PlateIdentityFocusTarget.front
                                  ? '앞자리 숫자를 입력합니다.'
                                  : _segment == PlateIdentityFocusTarget.middle
                                      ? '번호판 한글을 선택합니다.'
                                      : '뒷자리 숫자 4자리를 입력합니다.',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
                                    color: tokens.textSecondary,
                                    fontWeight: FontWeight.w700,
                                  ),
                            ),
                          ),
                        ),
                        _buildMiddleSuggestions(context),
                        const SizedBox(height: 8),
                        AnimatedBuilder(
                          animation: Listenable.merge(
                            <Listenable>[
                              widget.frontController,
                              widget.middleController,
                              widget.backController,
                            ],
                          ),
                          builder: (context, _) {
                            final valid = _valid;
                            final text = _autoApplying
                                ? '번호판을 반영하고 있습니다.'
                                : _pending
                                    ? valid
                                        ? '입력이 완성되어 자동으로 반영됩니다.'
                                        : '차량번호를 완성하세요.'
                                    : '수정할 영역을 선택하세요.';
                            return AnimatedSwitcher(
                              duration: reduceMotion
                                  ? Duration.zero
                                  : const Duration(milliseconds: 140),
                              child: Text(
                                text,
                                key: ValueKey<String>(
                                  '$_pending:$valid:$_autoApplying',
                                ),
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(
                                      color: _pending && !valid
                                          ? tokens.warning
                                          : _autoApplying || valid
                                              ? tokens.accent
                                              : tokens.textSecondary,
                                      fontWeight: FontWeight.w800,
                                    ),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),
                Divider(height: 1, color: tokens.borderSubtle),
                ClipRect(
                  child: AnimatedSwitcher(
                    duration: reduceMotion
                        ? Duration.zero
                        : const Duration(milliseconds: 165),
                    reverseDuration: reduceMotion
                        ? Duration.zero
                        : const Duration(milliseconds: 140),
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeInCubic,
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
                    child: IgnorePointer(
                      ignoring: _autoApplying,
                      key: ValueKey<String>(
                        '${_segment.name}:$_inputSessionRevision',
                      ),
                      child: _buildKeypad(),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
