import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../design_system/common_ui/common_quick_action_surface.dart';
import '../../../../shared/operational_cache/domain/repositories/operational_local_repository.dart';
import '../../../rule/domain/models/rule_model.dart';
import '../../application/single_area_work_rules_loader.dart';
import '../../application/single_inside_diagnostics.dart';

class SingleInsideBottomActionSurface extends StatefulWidget {
  const SingleInsideBottomActionSurface({
    super.key,
    required this.division,
    required this.area,
    required this.refreshRevision,
    required this.onMenuPressed,
  });

  final String division;
  final String area;
  final int refreshRevision;
  final Future<void> Function() onMenuPressed;

  @override
  State<SingleInsideBottomActionSurface> createState() =>
      _SingleInsideBottomActionSurfaceState();
}

class _SingleInsideBottomActionSurfaceState
    extends State<SingleInsideBottomActionSurface> {
  bool _expanded = false;
  bool _loadFailed = false;
  RuleModel? _rule;

  String get _identity => '${widget.division.trim()}/${widget.area.trim()}';

  @override
  void didUpdateWidget(covariant SingleInsideBottomActionSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    final previous = '${oldWidget.division.trim()}/${oldWidget.area.trim()}';
    final identityChanged = previous != _identity;
    final revisionChanged = oldWidget.refreshRevision != widget.refreshRevision;
    if (!identityChanged && !revisionChanged) return;
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

  Future<SingleAreaWorkRulesResult> _load() {
    return SingleAreaWorkRulesLoader.load(
      localRepository: context.read<OperationalLocalRepository>(),
      division: widget.division,
      area: widget.area,
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
        'expanded_refresh_complete identity=$requestedIdentity found=${result.rule != null} contentLength=${result.rule?.content.length ?? 0}',
      );
    } catch (error, stackTrace) {
      SingleInsideDiagnostics.log(
        'rules',
        'expanded_refresh_failure identity=$requestedIdentity error=$error stack=$stackTrace',
      );
    }
  }

  Future<void> _toggleRules(Rect _) async {
    if (_expanded) {
      setState(() => _expanded = false);
      SingleInsideDiagnostics.log(
        'rules',
        'toggle expanded=false division=${widget.division.trim()} area=${widget.area.trim()}',
      );
      return;
    }
    final requestedIdentity = _identity;
    try {
      final result = await _load();
      if (!mounted) return;
      if (requestedIdentity != _identity) {
        SingleInsideDiagnostics.log(
          'rules',
          'load_ignored requested=$requestedIdentity current=$_identity reason=identity_changed',
        );
        return;
      }
      setState(() {
        _rule = result.rule;
        _loadFailed = false;
        _expanded = true;
      });
      SingleInsideDiagnostics.log(
        'rules',
        'toggle expanded=true division=${result.division} area=${result.area} found=${result.rule != null} contentLength=${result.rule?.content.length ?? 0}',
      );
    } catch (error, stackTrace) {
      SingleInsideDiagnostics.log(
        'rules',
        'load_failure division=${widget.division.trim()} area=${widget.area.trim()} error=$error stack=$stackTrace',
      );
      if (!mounted || requestedIdentity != _identity) return;
      setState(() {
        _rule = null;
        _loadFailed = true;
        _expanded = true;
      });
      await SingleInsideDiagnostics.showStatus(
        context,
        title: '업무 규칙 상태',
        description: '현재 지역 업무 규칙을 불러오지 못했습니다.',
        failure: true,
      );
    }
  }

  Future<void> _openMenu(Rect _) async {
    SingleInsideDiagnostics.log(
      'menu',
      'launcher_pressed placement=bottom_quick_action_row division=${widget.division.trim()} area=${widget.area.trim()}',
    );
    await widget.onMenuPressed();
  }

  Widget _buildRuleContent(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    if (_loadFailed) {
      return Text(
        '업무 규칙을 불러오지 못했습니다.',
        key: const ValueKey<String>('failed'),
        style: theme.textTheme.bodyMedium?.copyWith(
          color: cs.error,
          fontWeight: FontWeight.w700,
        ),
      );
    }
    final rule = _rule;
    if (rule == null) {
      return Text(
        '등록된 업무 규칙이 없습니다.',
        key: const ValueKey<String>('empty'),
        style: theme.textTheme.bodyMedium?.copyWith(
          color: cs.onSurfaceVariant,
          fontWeight: FontWeight.w600,
        ),
      );
    }
    final content = rule.content.trim();
    if (content.isEmpty) {
      return Text(
        '등록된 업무 안내문이 없습니다.',
        key: ValueKey<String>('content_empty_${rule.id}'),
        style: theme.textTheme.bodyMedium?.copyWith(
          color: cs.onSurfaceVariant,
          fontWeight: FontWeight.w600,
        ),
      );
    }
    final maxHeight = math.max(120.0, MediaQuery.sizeOf(context).height * .28);
    return ConstrainedBox(
      key: ValueKey<String>('rule_${rule.id}_${rule.updatedAt?.millisecondsSinceEpoch ?? 0}'),
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: SingleChildScrollView(
        physics: const ClampingScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '업무 안내문',
              style: theme.textTheme.labelLarge?.copyWith(
                color: cs.onSurface,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 7),
            Text(
              content,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: cs.onSurface,
                height: 1.55,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRulesPanel(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    return AnimatedSize(
      duration: reduceMotion ? Duration.zero : const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
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
          child: Row(
            children: [
              Expanded(
                flex: 2,
                child: CommonQuickActionControl(
                  semanticsLabel: _expanded ? '업무 규칙 닫기' : '업무 규칙 열기',
                  icon: Icons.rule_rounded,
                  foreground: cs.primary,
                  showProgressWhileRunning: !_expanded,
                  onPressed: _toggleRules,
                ),
              ),
              Expanded(
                child: CommonQuickActionControl(
                  semanticsLabel: '메뉴',
                  icon: Icons.menu_rounded,
                  foreground: cs.onSurfaceVariant,
                  showProgressWhileRunning: false,
                  onPressed: _openMenu,
                ),
              ),
            ],
          ),
        ),
        _buildRulesPanel(context),
      ],
    );
  }
}
