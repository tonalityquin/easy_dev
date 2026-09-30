import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../app/utils/developer_operation_status_dialog.dart';
import '../../../design_system/common_ui/common_ui_theme.dart';
import '../../../shared/operational_cache/domain/repositories/operational_local_repository.dart';
import '../../../shared/secondary/widgets/ops_console_widgets.dart';
import '../applications/work_rule_report_loader.dart';
import '../domain/models/rule_model.dart';

enum WorkRuleReportSide { left, right, inline }

class WorkRuleReportWorkspace extends StatefulWidget {
  const WorkRuleReportWorkspace({
    super.key,
    required this.division,
    required this.area,
    required this.capabilityEnabled,
    required this.source,
    required this.side,
    required this.onBack,
    this.developerMode = false,
    this.onDebug,
  });

  final String division;
  final String area;
  final bool capabilityEnabled;
  final String source;
  final WorkRuleReportSide side;
  final VoidCallback onBack;
  final bool developerMode;
  final ValueChanged<String>? onDebug;

  @override
  State<WorkRuleReportWorkspace> createState() =>
      _WorkRuleReportWorkspaceState();
}

class _WorkRuleReportWorkspaceState extends State<WorkRuleReportWorkspace> {
  RuleModel? _rule;
  DeveloperOperationTrace? _trace;
  bool _loading = true;
  bool _failed = false;
  int _generation = 0;

  String get _identity => '${widget.division.trim()}/${widget.area.trim()}';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_load());
    });
  }

  @override
  void didUpdateWidget(covariant WorkRuleReportWorkspace oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldIdentity = '${oldWidget.division.trim()}/${oldWidget.area.trim()}';
    if (oldIdentity != _identity ||
        oldWidget.capabilityEnabled != widget.capabilityEnabled) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        unawaited(_load());
      });
    }
  }

  @override
  void dispose() {
    _debug('work_rule_report=closed');
    super.dispose();
  }

  void _debug(String message) {
    final line =
        'source=${widget.source} side=${widget.side.name} identity=$_identity $message';
    debugPrint('[WorkRuleReport] $line');
    widget.onDebug?.call(line);
    _trace?.log(line);
  }

  Future<void> _load() async {
    final generation = ++_generation;
    if (mounted) {
      setState(() {
        _loading = true;
        _failed = false;
      });
    }

    final trace = await DeveloperOperationTrace.start(
      context: context,
      title: '업무 규칙 보고서',
      initialMessage: '현재 지역의 업무 규칙 Snapshot을 확인하고 있습니다.',
      useCommonUi: true,
      developerModeMessage: '개발자 모드 ON: 업무 규칙 debugPrint 코드를 복사할 수 있습니다.',
      standardModeMessage: '개발자 모드 OFF',
      showDialogImmediately: false,
    );
    if (!mounted || generation != _generation) return;
    _trace = trace;
    _debug(
      'work_rule_report=open_requested capability=${widget.capabilityEnabled} remoteRead=0 remoteWrite=0',
    );

    if (!widget.capabilityEnabled) {
      setState(() {
        _loading = false;
        _failed = false;
        _rule = null;
      });
      _debug('work_rule_report=unavailable reason=capability_disabled');
      await trace.succeed('현재 지역에서는 업무 규칙 기능을 사용하지 않습니다.');
      return;
    }

    try {
      final result = await WorkRuleReportLoader.load(
        localRepository: context.read<OperationalLocalRepository>(),
        division: widget.division,
        area: widget.area,
        onDebug: _debug,
      );
      if (!mounted || generation != _generation) return;
      setState(() {
        _rule = result.rule;
        _loading = false;
        _failed = false;
      });
      _debug(
        'work_rule_report=ready found=${result.rule != null} todoCount=${result.rule?.todoItems.length ?? 0} contentLength=${result.rule?.content.length ?? 0} source=${result.source}',
      );
      await trace.succeed('업무 규칙 보고서 준비가 완료되었습니다.');
    } catch (error, stackTrace) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _rule = null;
        _loading = false;
        _failed = true;
      });
      _debug('work_rule_report=failed error=$error');
      await trace.fail(
        '업무 규칙 보고서를 불러오지 못했습니다.',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> _showDeveloperStatus() async {
    final trace = _trace;
    if (trace == null || !trace.developerMode || !mounted) return;
    await HapticFeedback.selectionClick();
    trace.log(
      'work_rule_report=status_snapshot loading=$_loading failed=$_failed capability=${widget.capabilityEnabled} found=${_rule != null} todoCount=${_rule?.todoItems.length ?? 0} contentLength=${_rule?.content.length ?? 0} updatedAt=${_rule?.updatedAt?.toIso8601String() ?? '-'}',
    );
    if (!mounted) return;
    await trace.showSnapshotStatusDialog(
      context,
      title: '업무 규칙 보고서 상태',
      description: [
        'source=${widget.source}',
        'side=${widget.side.name}',
        'division=${widget.division.trim()}',
        'area=${widget.area.trim()}',
        'capabilityEnabled=${widget.capabilityEnabled}',
        'loading=$_loading',
        'failed=$_failed',
        'found=${_rule != null}',
        'todoCount=${_rule?.todoItems.length ?? 0}',
        'contentLength=${_rule?.content.length ?? 0}',
        'updatedAt=${_rule?.updatedAt?.toIso8601String() ?? '-'}',
        'dataSource=operational_sqlite',
        'remoteRead=0',
        'remoteWrite=0',
      ].join('\n'),
      failure: _failed,
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_loading) {
      return const WorkRuleReportMessageSurface(
        key: ValueKey<String>('work_rule_loading'),
        icon: Icons.rule_folder_outlined,
        title: '업무 규칙을 불러오는 중입니다.',
        showProgress: true,
      );
    }
    if (!widget.capabilityEnabled) {
      return const WorkRuleReportMessageSurface(
        key: ValueKey<String>('work_rule_unavailable'),
        icon: Icons.rule_folder_outlined,
        title: '현재 지역에서는 업무 규칙 기능을 사용하지 않습니다.',
      );
    }
    if (_failed) {
      return WorkRuleReportMessageSurface(
        key: const ValueKey<String>('work_rule_failed'),
        icon: Icons.error_outline_rounded,
        title: '업무 규칙을 불러오지 못했습니다.',
        actionLabel: '다시 불러오기',
        onAction: () => unawaited(_load()),
      );
    }
    final rule = _rule;
    if (rule == null) {
      return const WorkRuleReportMessageSurface(
        key: ValueKey<String>('work_rule_empty'),
        icon: Icons.description_outlined,
        title: '등록된 업무 규칙이 없습니다.',
      );
    }
    return SingleChildScrollView(
      key: ValueKey<String>(
        'work_rule_ready_${rule.id}_${rule.updatedAt?.millisecondsSinceEpoch ?? 0}',
      ),
      physics: const ClampingScrollPhysics(),
      child: WorkRuleReportSurface(
        area: widget.area,
        rule: rule,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final text = Theme.of(context).textTheme;
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final showDeveloperStatus =
        widget.developerMode || (_trace?.developerMode ?? false);

    return Column(
      key: const ValueKey<String>('work_rule_report_workspace'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Semantics(
              button: true,
              label: '업무 목록으로',
              child: IconButton(
                onPressed: () {
                  HapticFeedback.selectionClick();
                  _debug('work_rule_report=close_requested source=back_button');
                  widget.onBack();
                },
                icon: Icon(
                  Icons.arrow_back_rounded,
                  color: tokens.iconPrimary,
                ),
              ),
            ),
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: tokens.accentContainer,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: tokens.borderSubtle),
              ),
              alignment: Alignment.center,
              child: Icon(
                Icons.rule_rounded,
                color: tokens.onAccentContainer,
                size: 20,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '업무 규칙',
                    style: text.titleMedium?.copyWith(
                      color: tokens.textPrimary,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  Text(
                    widget.area.trim().isEmpty ? '현재 지역' : widget.area.trim(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.labelMedium?.copyWith(
                      color: tokens.textSecondary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            if (showDeveloperStatus)
              Semantics(
                button: true,
                label: '업무 규칙 상태',
                child: IconButton(
                  onPressed: _showDeveloperStatus,
                  icon: Icon(
                    Icons.bug_report_outlined,
                    color: tokens.iconSecondary,
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 10),
        Expanded(
          child: AnimatedSwitcher(
            duration: reduceMotion
                ? Duration.zero
                : const Duration(milliseconds: 180),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            transitionBuilder: (child, animation) {
              if (reduceMotion) return child;
              return FadeTransition(
                opacity: animation,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0, .02),
                    end: Offset.zero,
                  ).animate(animation),
                  child: child,
                ),
              );
            },
            child: _buildBody(context),
          ),
        ),
      ],
    );
  }
}

class WorkRuleReportSurface extends StatelessWidget {
  const WorkRuleReportSurface({
    super.key,
    required this.area,
    required this.rule,
    this.showDocumentHeader = true,
    this.dense = false,
  });

  final String area;
  final RuleModel rule;
  final bool showDocumentHeader;
  final bool dense;

  String _formatUpdatedAt(DateTime? value) {
    if (value == null) return '-';
    final local = value.toLocal();
    String two(int number) => number.toString().padLeft(2, '0');
    return '${local.year}.${two(local.month)}.${two(local.day)} ${two(local.hour)}:${two(local.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final text = Theme.of(context).textTheme;
    final todos = rule.todoItems;
    final content = rule.content.trim();
    final padding = dense ? 12.0 : 14.0;

    return OpsDockListSurface(
      child: Padding(
        padding: EdgeInsets.all(padding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (showDocumentHeader) ...[
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: tokens.infoContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    alignment: Alignment.center,
                    child: Icon(
                      Icons.description_outlined,
                      color: tokens.onInfoContainer,
                      size: 21,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '업무 규칙 보고서',
                          style: text.titleSmall?.copyWith(
                            color: tokens.textPrimary,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '${area.trim().isEmpty ? rule.area : area.trim()} · 업무 항목 ${todos.length}개',
                          style: text.labelMedium?.copyWith(
                            color: tokens.textSecondary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: tokens.surfaceSelected,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: tokens.borderSubtle),
                    ),
                    child: Text(
                      'REPORT',
                      style: text.labelSmall?.copyWith(
                        color: tokens.textSecondary,
                        fontWeight: FontWeight.w900,
                        letterSpacing: .5,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Divider(height: 1, color: tokens.borderSubtle),
              const SizedBox(height: 14),
            ],
            if (todos.isNotEmpty) ...[
              Row(
                children: [
                  Icon(
                    Icons.format_list_numbered_rounded,
                    size: 19,
                    color: tokens.accent,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '업무 절차',
                    style: text.titleSmall?.copyWith(
                      color: tokens.textPrimary,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
              SizedBox(height: dense ? 8 : 10),
              for (var index = 0; index < todos.length; index++) ...[
                _WorkRuleReportRow(
                  number: index + 1,
                  text: todos[index].text,
                  dense: dense,
                ),
                if (index != todos.length - 1)
                  Divider(
                    height: dense ? 12 : 16,
                    color: tokens.borderSubtle,
                  ),
              ],
            ],
            if (todos.isNotEmpty && content.isNotEmpty) ...[
              const SizedBox(height: 14),
              Divider(height: 1, color: tokens.borderSubtle),
              const SizedBox(height: 14),
            ],
            if (content.isNotEmpty) ...[
              Row(
                children: [
                  Icon(
                    Icons.article_outlined,
                    size: 19,
                    color: tokens.accent,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '업무 안내문',
                    style: text.titleSmall?.copyWith(
                      color: tokens.textPrimary,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 9),
              Text(
                content,
                style: text.bodyMedium?.copyWith(
                  color: tokens.textPrimary,
                  height: 1.58,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
            if (todos.isEmpty && content.isEmpty)
              Text(
                '등록된 업무 규칙 내용이 없습니다.',
                style: text.bodyMedium?.copyWith(
                  color: tokens.textSecondary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            const SizedBox(height: 14),
            Divider(height: 1, color: tokens.borderSubtle),
            const SizedBox(height: 10),
            Text(
              '마지막 수정 ${_formatUpdatedAt(rule.updatedAt)}',
              style: text.labelSmall?.copyWith(
                color: tokens.textSecondary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class WorkRuleReportMessageSurface extends StatelessWidget {
  const WorkRuleReportMessageSurface({
    super.key,
    required this.icon,
    required this.title,
    this.showProgress = false,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final bool showProgress;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final text = Theme.of(context).textTheme;
    return OpsDockListSurface(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 24, 18, 22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 30, color: tokens.iconSecondary),
            const SizedBox(height: 10),
            Text(
              title,
              textAlign: TextAlign.center,
              style: text.bodyMedium?.copyWith(
                color: tokens.textPrimary,
                fontWeight: FontWeight.w800,
                height: 1.4,
              ),
            ),
            if (showProgress) ...[
              const SizedBox(height: 14),
              LinearProgressIndicator(
                minHeight: 2,
                color: tokens.accent,
                backgroundColor: tokens.surfaceSelected,
              ),
            ],
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 14),
              OutlinedButton.icon(
                onPressed: onAction,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: Text(actionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _WorkRuleReportRow extends StatelessWidget {
  const _WorkRuleReportRow({
    required this.number,
    required this.text,
    required this.dense,
  });

  final int number;
  final String text;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final style = Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: tokens.textPrimary,
          height: 1.5,
          fontWeight: FontWeight.w600,
        );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: dense ? 28 : 30,
          height: dense ? 28 : 30,
          decoration: BoxDecoration(
            color: tokens.accentContainer,
            borderRadius: BorderRadius.circular(10),
          ),
          alignment: Alignment.center,
          child: Text(
            number.toString().padLeft(2, '0'),
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: tokens.onAccentContainer,
                  fontWeight: FontWeight.w900,
                ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Padding(
            padding: EdgeInsets.only(top: dense ? 3 : 4),
            child: Text(text, style: style),
          ),
        ),
      ],
    );
  }
}
