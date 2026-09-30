import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../design_system/common_ui/common_quick_action_surface.dart';
import '../../../../shared/operational_cache/domain/repositories/operational_local_repository.dart';
import '../../../rule/applications/work_rule_report_loader.dart';
import '../../../rule/domain/models/rule_model.dart';
import '../../../rule/widgets/work_rule_report_surface.dart';
import '../../application/single_inside_diagnostics.dart';

class SingleInsideBottomActionSurface extends StatefulWidget {
  const SingleInsideBottomActionSurface({
    super.key,
    required this.division,
    required this.area,
    required this.refreshRevision,
    required this.initialAutoOpenRequested,
    required this.onInitialAutoOpenCompleted,
    required this.onInitialAutomationInterrupted,
  });

  final String division;
  final String area;
  final int refreshRevision;
  final bool initialAutoOpenRequested;
  final Future<void> Function() onInitialAutoOpenCompleted;
  final ValueChanged<String> onInitialAutomationInterrupted;

  @override
  State<SingleInsideBottomActionSurface> createState() =>
      _SingleInsideBottomActionSurfaceState();
}

class _SingleInsideBottomActionSurfaceState
    extends State<SingleInsideBottomActionSurface> {
  static const Duration _initialAutoOpenDuration = Duration(milliseconds: 340);
  static const Duration _manualPanelDuration = Duration(milliseconds: 240);

  bool _expanded = false;
  bool _loadFailed = false;
  bool _rulesBusy = false;
  bool _initialAutoOpenHandled = false;
  bool _rulesOpeningAnimationActive = false;
  bool _awaitingInitialAutoOpenAnimation = false;
  bool _initialAutoOpenCompletionSent = false;
  RuleModel? _rule;

  String get _identity => '${widget.division.trim()}/${widget.area.trim()}';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _maybeStartInitialAutoOpen();
    });
  }

  @override
  void didUpdateWidget(covariant SingleInsideBottomActionSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    final previous = '${oldWidget.division.trim()}/${oldWidget.area.trim()}';
    final identityChanged = previous != _identity;
    final revisionChanged = oldWidget.refreshRevision != widget.refreshRevision;
    final autoOpenChanged =
        !oldWidget.initialAutoOpenRequested && widget.initialAutoOpenRequested;
    if (identityChanged || revisionChanged) {
      if (identityChanged) {
        _expanded = false;
        _rule = null;
      }
      _loadFailed = false;
      SingleInsideDiagnostics.log(
        'rules',
        'source_changed identityChanged=$identityChanged revisionChanged=$revisionChanged previous=$previous current=$_identity revision=${widget.refreshRevision} expanded=$_expanded',
      );
      if (_expanded && revisionChanged) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _reloadExpanded();
        });
      }
    }
    if (autoOpenChanged) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _maybeStartInitialAutoOpen();
      });
    }
  }

  Future<WorkRuleReportResult> _load() {
    return WorkRuleReportLoader.load(
      localRepository: context.read<OperationalLocalRepository>(),
      division: widget.division,
      area: widget.area,
      onDebug: (message) => SingleInsideDiagnostics.log('rules', message),
    );
  }

  Future<void> _reloadExpanded() async {
    final requestedIdentity = _identity;
    try {
      final result = await _load();
      if (!mounted || requestedIdentity != _identity) return;
      setState(() {
        _rule = result.rule;
        _loadFailed = false;
      });
      SingleInsideDiagnostics.log(
        'rules',
        'expanded_refresh_complete identity=$requestedIdentity found=${result.rule != null} todoCount=${result.rule?.todoItems.length ?? 0} contentLength=${result.rule?.content.length ?? 0}',
      );
    } catch (error, stackTrace) {
      SingleInsideDiagnostics.log(
        'rules',
        'expanded_refresh_failure identity=$requestedIdentity error=$error stack=$stackTrace',
      );
    }
  }

  Future<void> _maybeStartInitialAutoOpen() async {
    if (!widget.initialAutoOpenRequested ||
        _initialAutoOpenHandled ||
        !mounted) {
      return;
    }
    _initialAutoOpenHandled = true;
    SingleInsideDiagnostics.log(
      'rules',
      'initial_auto_open_started identity=$_identity expanded=$_expanded animationDurationMs=${_initialAutoOpenDuration.inMilliseconds} manualAnimationDurationMs=${_manualPanelDuration.inMilliseconds}',
    );
    if (_expanded) {
      if (_rulesOpeningAnimationActive) {
        setState(() => _awaitingInitialAutoOpenAnimation = true);
        SingleInsideDiagnostics.log(
          'rules',
          'initial_auto_open_waiting_for_existing_animation identity=$_identity',
        );
      } else {
        _completeInitialAutoOpen('already_expanded');
      }
      return;
    }
    await _openRules(
      source: 'initial_auto',
      showFailureStatus: false,
      notifyInitialCompletion: true,
    );
  }

  Future<void> _openRules({
    required String source,
    required bool showFailureStatus,
    required bool notifyInitialCompletion,
  }) async {
    if (_rulesBusy || !mounted) return;
    if (_expanded) {
      if (notifyInitialCompletion) {
        if (_rulesOpeningAnimationActive) {
          setState(() => _awaitingInitialAutoOpenAnimation = true);
        } else {
          _completeInitialAutoOpen('already_expanded');
        }
      }
      return;
    }
    final requestedIdentity = _identity;
    setState(() => _rulesBusy = true);
    try {
      final result = await _load();
      if (!mounted) return;
      if (requestedIdentity != _identity) {
        SingleInsideDiagnostics.log(
          'rules',
          'load_ignored source=$source requested=$requestedIdentity current=$_identity reason=identity_changed',
        );
        return;
      }
      setState(() {
        _rule = result.rule;
        _loadFailed = false;
        _expanded = true;
        _rulesOpeningAnimationActive = true;
        _awaitingInitialAutoOpenAnimation = notifyInitialCompletion;
      });
      final reduceMotion =
          MediaQuery.maybeOf(context)?.disableAnimations ?? false;
      var animationDurationMs = 0;
      if (!reduceMotion) {
        animationDurationMs = notifyInitialCompletion
            ? _initialAutoOpenDuration.inMilliseconds
            : _manualPanelDuration.inMilliseconds;
      }
      SingleInsideDiagnostics.log(
        'rules',
        'open source=$source expanded=true division=${result.division} area=${result.area} found=${result.rule != null} todoCount=${result.rule?.todoItems.length ?? 0} contentLength=${result.rule?.content.length ?? 0} notifyInitialCompletion=$notifyInitialCompletion animationDurationMs=$animationDurationMs',
      );
      _completeInitialAutoOpenIfReduceMotion();
    } catch (error, stackTrace) {
      SingleInsideDiagnostics.log(
        'rules',
        'load_failure source=$source division=${widget.division.trim()} area=${widget.area.trim()} error=$error stack=$stackTrace',
      );
      if (!mounted || requestedIdentity != _identity) return;
      setState(() {
        _rule = null;
        _loadFailed = true;
        _expanded = true;
        _rulesOpeningAnimationActive = true;
        _awaitingInitialAutoOpenAnimation = notifyInitialCompletion;
      });
      final reduceMotion =
          MediaQuery.maybeOf(context)?.disableAnimations ?? false;
      var animationDurationMs = 0;
      if (!reduceMotion) {
        animationDurationMs = notifyInitialCompletion
            ? _initialAutoOpenDuration.inMilliseconds
            : _manualPanelDuration.inMilliseconds;
      }
      SingleInsideDiagnostics.log(
        'rules',
        'open source=$source expanded=true failure=true notifyInitialCompletion=$notifyInitialCompletion animationDurationMs=$animationDurationMs',
      );
      _completeInitialAutoOpenIfReduceMotion();
      if (showFailureStatus) {
        await SingleInsideDiagnostics.showStatus(
          context,
          title: '업무 규칙 상태',
          description: '현재 지역 업무 규칙을 불러오지 못했습니다.',
          failure: true,
        );
      }
    } finally {
      if (mounted) {
        setState(() => _rulesBusy = false);
      }
    }
  }

  void _completeInitialAutoOpenIfReduceMotion() {
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (!reduceMotion || !_awaitingInitialAutoOpenAnimation) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_expanded) return;
      _completeInitialAutoOpen('reduce_motion');
    });
  }

  void _handleRulesSizeAnimationEnd() {
    if (_expanded) {
      _rulesOpeningAnimationActive = false;
    }
    if (!_awaitingInitialAutoOpenAnimation || !_expanded) return;
    _completeInitialAutoOpen('animated_size_on_end');
  }

  void _completeInitialAutoOpen(String completionSource) {
    if (_initialAutoOpenCompletionSent || !mounted) return;
    _rulesOpeningAnimationActive = false;
    _awaitingInitialAutoOpenAnimation = false;
    _initialAutoOpenCompletionSent = true;
    SingleInsideDiagnostics.log(
      'rules',
      'initial_auto_open_completed identity=$_identity completionSource=$completionSource expanded=$_expanded loadFailed=$_loadFailed',
    );
    unawaited(widget.onInitialAutoOpenCompleted());
  }

  Future<void> _toggleRules(Rect _) async {
    if (_rulesBusy || _awaitingInitialAutoOpenAnimation) return;
    widget.onInitialAutomationInterrupted('rules_manual_tap');
    if (_expanded) {
      setState(() {
        _expanded = false;
        _rulesOpeningAnimationActive = false;
      });
      SingleInsideDiagnostics.log(
        'rules',
        'toggle expanded=false division=${widget.division.trim()} area=${widget.area.trim()}',
      );
      return;
    }
    await _openRules(
      source: 'manual',
      showFailureStatus: true,
      notifyInitialCompletion: false,
    );
  }

  Widget _buildRuleContent(BuildContext context) {
    if (_loadFailed) {
      return const WorkRuleReportMessageSurface(
        key: ValueKey<String>('failed'),
        icon: Icons.error_outline_rounded,
        title: '업무 규칙을 불러오지 못했습니다.',
      );
    }
    final rule = _rule;
    if (rule == null) {
      return const WorkRuleReportMessageSurface(
        key: ValueKey<String>('empty'),
        icon: Icons.description_outlined,
        title: '등록된 업무 규칙이 없습니다.',
      );
    }
    final maxHeight = math.max(150.0, MediaQuery.sizeOf(context).height * .34);
    return ConstrainedBox(
      key: ValueKey<String>(
        'rule_${rule.id}_${rule.updatedAt?.millisecondsSinceEpoch ?? 0}',
      ),
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: SingleChildScrollView(
        physics: const ClampingScrollPhysics(),
        child: WorkRuleReportSurface(
          area: widget.area,
          rule: rule,
          showDocumentHeader: false,
          dense: true,
        ),
      ),
    );
  }

  Widget _buildRulesPanel(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    var panelDuration = Duration.zero;
    if (!reduceMotion) {
      panelDuration = _awaitingInitialAutoOpenAnimation
          ? _initialAutoOpenDuration
          : _manualPanelDuration;
    }
    return AnimatedSize(
      duration: panelDuration,
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      onEnd: _handleRulesSizeAnimationEnd,
      child: !_expanded
          ? const SizedBox.shrink()
          : Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: cs.surface,
                border: Border(
                  top: BorderSide(color: cs.outlineVariant.withOpacity(.7)),
                ),
              ),
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '업무 규칙',
                          style: theme.textTheme.titleSmall?.copyWith(
                            color: cs.onSurface,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      Flexible(
                        child: Text(
                          widget.area.trim(),
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: cs.onSurfaceVariant,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  AnimatedSwitcher(
                    duration: reduceMotion ? Duration.zero : const Duration(milliseconds: 190),
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeInCubic,
                    transitionBuilder: (child, animation) {
                      if (reduceMotion) return child;
                      return FadeTransition(
                        opacity: animation,
                        child: SlideTransition(
                          position: Tween<Offset>(
                            begin: const Offset(0, .025),
                            end: Offset.zero,
                          ).animate(animation),
                          child: child,
                        ),
                      );
                    },
                    child: _buildRuleContent(context),
                  ),
                ],
              ),
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        CommonQuickActionSurface(
          backgroundColor: cs.surface,
          borderColor: cs.outlineVariant.withOpacity(.7),
          child: CommonQuickActionControl(
            semanticsLabel: _expanded ? '업무 규칙 닫기' : '업무 규칙 열기',
            icon: Icons.rule_rounded,
            foreground: cs.primary,
            showProgressWhileRunning: !_expanded,
            onPressed: _rulesBusy || _awaitingInitialAutoOpenAnimation
                ? null
                : _toggleRules,
          ),
        ),
        _buildRulesPanel(context),
      ],
    );
  }
}
