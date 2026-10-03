import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../app/utils/developer_operation_status_dialog.dart';
import '../../../design_system/common_ui/common_ui_operational_report.dart';
import '../../../design_system/common_ui/common_ui_theme.dart';
import '../../../shared/operational_cache/domain/repositories/operational_local_repository.dart';
import '../applications/work_rule_report_loader.dart';
import '../domain/models/rule_model.dart';
import '../domain/utils/work_manual_text.dart';
import 'work_manual/work_manual_book_reader.dart';

enum WorkRuleReportSide { left, right, inline }

enum WorkRuleReportContentMode { notice, responseManual }

extension WorkRuleReportContentModeUi on WorkRuleReportContentMode {
  String get debugName {
    switch (this) {
      case WorkRuleReportContentMode.notice:
        return 'notice';
      case WorkRuleReportContentMode.responseManual:
        return 'response_manual';
    }
  }

  String get workspaceTitle {
    switch (this) {
      case WorkRuleReportContentMode.notice:
        return '업무 규칙';
      case WorkRuleReportContentMode.responseManual:
        return '업무 메뉴얼';
    }
  }

  String get contentTitle {
    switch (this) {
      case WorkRuleReportContentMode.notice:
        return '업무 안내문';
      case WorkRuleReportContentMode.responseManual:
        return '업무 메뉴얼';
    }
  }

  String get itemLabel {
    switch (this) {
      case WorkRuleReportContentMode.notice:
        return '안내 항목';
      case WorkRuleReportContentMode.responseManual:
        return '페이지';
    }
  }

  IconData get icon {
    switch (this) {
      case WorkRuleReportContentMode.notice:
        return Icons.rule_rounded;
      case WorkRuleReportContentMode.responseManual:
        return Icons.menu_book_rounded;
    }
  }

  String contentOf(RuleModel? rule) {
    if (rule == null) return '';
    switch (this) {
      case WorkRuleReportContentMode.notice:
        return rule.content.trim();
      case WorkRuleReportContentMode.responseManual:
        return normalizeWorkManualText(rule.responseManual);
    }
  }

  String get renderMode {
    switch (this) {
      case WorkRuleReportContentMode.notice:
        return 'numbered_items';
      case WorkRuleReportContentMode.responseManual:
        return 'structured_horizontal_book';
    }
  }

  bool get autoNumbering => this == WorkRuleReportContentMode.notice;

  bool get preserveBlankLines =>
      this == WorkRuleReportContentMode.responseManual;

  String get visualStyle {
    switch (this) {
      case WorkRuleReportContentMode.notice:
        return 'pre_clock_in_report';
      case WorkRuleReportContentMode.responseManual:
        return 'structured_manual_book_reader';
    }
  }

  String get scrollPolicy {
    switch (this) {
      case WorkRuleReportContentMode.notice:
        return 'adaptive_full_height';
      case WorkRuleReportContentMode.responseManual:
        return 'horizontal_page_view_vertical_page_scroll';
    }
  }

  String get pageAxis {
    switch (this) {
      case WorkRuleReportContentMode.notice:
        return '-';
      case WorkRuleReportContentMode.responseManual:
        return 'horizontal';
    }
  }

  String get loadingMessage => '${contentTitle}을 불러오는 중입니다.';

  String get emptyMessage => '등록된 ${contentTitle}이 없습니다.';

  String get failedMessage => '${contentTitle}을 불러오지 못했습니다.';

  String get readyMessage => '$contentTitle 준비가 완료되었습니다.';

  String get emptyReadyMessage => '$contentTitle 조회가 완료되었습니다. 등록된 내용이 없습니다.';

  String get statusTitle => '$workspaceTitle 상태';

  String get initialMessage => '현재 지역의 $contentTitle Snapshot을 확인하고 있습니다.';

  String get developerModeMessage =>
      '개발자 모드 ON: $contentTitle debugPrint 코드를 복사할 수 있습니다.';
}

List<String> splitWorkRuleNoticeItems(String value) {
  return value
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n')
      .split('\n')
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .toList(growable: false);
}

bool _useCompactWorkRuleLayout(BoxConstraints constraints) {
  final width = constraints.hasBoundedWidth
      ? constraints.maxWidth
      : double.infinity;
  final height = constraints.hasBoundedHeight
      ? constraints.maxHeight
      : double.infinity;
  return width < 320 || height < 520;
}

class WorkRuleReportWorkspace extends StatefulWidget {
  const WorkRuleReportWorkspace({
    super.key,
    required this.division,
    required this.area,
    required this.capabilityEnabled,
    required this.source,
    required this.side,
    required this.onBack,
    this.contentMode = WorkRuleReportContentMode.notice,
    this.refreshRevision = 0,
    this.developerMode = false,
    this.onDebug,
  });

  final String division;
  final String area;
  final bool capabilityEnabled;
  final String source;
  final WorkRuleReportSide side;
  final VoidCallback onBack;
  final WorkRuleReportContentMode contentMode;
  final int refreshRevision;
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
  double? _viewportWidth;
  double? _viewportHeight;
  bool? _compactLayout;
  String? _lastViewportSignature;
  WorkManualBookDiagnostics? _manualBookDiagnostics;

  String get _identity => '${widget.division.trim()}/${widget.area.trim()}';

  String get _content => widget.contentMode.contentOf(_rule);

  bool get _contentAvailable {
    if (widget.contentMode == WorkRuleReportContentMode.responseManual) {
      return _rule?.responseManualPages.isNotEmpty ?? false;
    }
    return _content.trim().isNotEmpty;
  }

  bool get _ruleFound => _rule != null;

  int get _itemCount =>
      widget.contentMode == WorkRuleReportContentMode.notice
          ? splitWorkRuleNoticeItems(_content).length
          : _rule?.responseManualPages.length ?? 0;

  int get _manualLineCount {
    if (widget.contentMode != WorkRuleReportContentMode.responseManual ||
        _content.isEmpty) {
      return 0;
    }
    return normalizeWorkManualText(_content).split('\n').length;
  }

  String _formatViewportValue(double? value) {
    if (value == null || !value.isFinite) return '-';
    return value.toStringAsFixed(1);
  }

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
        oldWidget.capabilityEnabled != widget.capabilityEnabled ||
        oldWidget.contentMode != widget.contentMode ||
        oldWidget.refreshRevision != widget.refreshRevision) {
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

  void _recordViewport(BoxConstraints constraints) {
    if (!constraints.hasBoundedWidth || !constraints.hasBoundedHeight) return;
    final width = constraints.maxWidth;
    final height = constraints.maxHeight;
    final compact = _useCompactWorkRuleLayout(constraints);
    _viewportWidth = width;
    _viewportHeight = height;
    _compactLayout = compact;
    final signature =
        '${width.toStringAsFixed(1)}x${height.toStringAsFixed(1)}:$compact';
    if (_lastViewportSignature == signature) return;
    _lastViewportSignature = signature;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _lastViewportSignature != signature) return;
      _debug(
        'work_rule_report=layout layoutMode=side_dock_fill viewportWidth=${width.toStringAsFixed(1)} viewportHeight=${height.toStringAsFixed(1)} compactLayout=$compact scrollPolicy=${widget.contentMode.scrollPolicy}',
      );
    });
  }

  Future<void> _load() async {
    final generation = ++_generation;
    if (mounted) {
      setState(() {
        _loading = true;
        _failed = false;
        _manualBookDiagnostics = null;
      });
    }

    final trace = await DeveloperOperationTrace.start(
      context: context,
      title: widget.contentMode.workspaceTitle,
      initialMessage: widget.contentMode.initialMessage,
      useCommonUi: true,
      developerModeMessage: widget.contentMode.developerModeMessage,
      standardModeMessage: '개발자 모드 OFF',
      showDialogImmediately: false,
    );
    if (!mounted || generation != _generation) return;
    _trace = trace;
    _debug(
      'work_rule_report=open_requested capability=${widget.capabilityEnabled} contentMode=${widget.contentMode.debugName} refreshRevision=${widget.refreshRevision} visualStyle=${widget.contentMode.visualStyle} layoutMode=side_dock_fill scrollPolicy=${widget.contentMode.scrollPolicy} remoteRead=0 remoteWrite=0',
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
      final selectedContent =
          widget.contentMode == WorkRuleReportContentMode.notice
              ? result.content
              : normalizeWorkManualText(result.responseManual);
      final selectedAvailable = selectedContent.trim().isNotEmpty;
      final itemCount =
          widget.contentMode == WorkRuleReportContentMode.notice
              ? splitWorkRuleNoticeItems(selectedContent).length
              : result.responseManualPages.length;
      final manualLineCount =
          widget.contentMode == WorkRuleReportContentMode.responseManual &&
              selectedContent.isNotEmpty
          ? selectedContent.split('\n').length
          : 0;
      _debug(
        'work_rule_report=ready ruleFound=${result.ruleFound} contentAvailable=${result.contentAvailable} contentLength=${result.content.length} responseManualAvailable=${result.responseManualAvailable} responseManualLength=${result.responseManual.length} responseManualPageCount=${result.responseManualPages.length} legacyFallback=${result.rule?.responseManualUsesLegacyFallback ?? false} selectedContentAvailable=$selectedAvailable selectedContentLength=${selectedContent.length} itemCount=$itemCount manualLineCount=$manualLineCount renderMode=${widget.contentMode.renderMode} autoNumbering=${widget.contentMode.autoNumbering} preserveBlankLines=${widget.contentMode.preserveBlankLines} updatedAt=${result.updatedAt?.toIso8601String() ?? '-'} source=${result.source} contentMode=${widget.contentMode.debugName} refreshRevision=${widget.refreshRevision} visualStyle=${widget.contentMode.visualStyle} layoutMode=side_dock_fill scrollPolicy=${widget.contentMode.scrollPolicy}',
      );
      await trace.succeed(
        selectedAvailable
            ? widget.contentMode.readyMessage
            : widget.contentMode.emptyReadyMessage,
      );
    } catch (error, stackTrace) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _rule = null;
        _loading = false;
        _failed = true;
      });
      _debug('work_rule_report=failed error=$error');
      await trace.fail(
        widget.contentMode.failedMessage,
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> _showDeveloperStatus() async {
    final trace = _trace;
    if (trace == null || !trace.developerMode || !mounted) return;
    await HapticFeedback.selectionClick();
    final book = _manualBookDiagnostics;
    trace.log(
      'work_rule_report=status_snapshot loading=$_loading failed=$_failed capability=${widget.capabilityEnabled} ruleFound=$_ruleFound selectedContentAvailable=$_contentAvailable selectedContentLength=${_content.length} itemCount=$_itemCount manualLineCount=$_manualLineCount contentLength=${_rule?.content.trim().length ?? 0} responseManualLength=${_rule?.responseManual.length ?? 0} responseManualPageCount=${_rule?.responseManualPages.length ?? 0} legacyFallback=${_rule?.responseManualUsesLegacyFallback ?? false} renderMode=${widget.contentMode.renderMode} autoNumbering=${widget.contentMode.autoNumbering} preserveBlankLines=${widget.contentMode.preserveBlankLines} updatedAt=${_rule?.updatedAt?.toIso8601String() ?? '-'} contentMode=${widget.contentMode.debugName} refreshRevision=${widget.refreshRevision} visualStyle=${widget.contentMode.visualStyle} layoutMode=side_dock_fill viewportWidth=${_formatViewportValue(_viewportWidth)} viewportHeight=${_formatViewportValue(_viewportHeight)} compactLayout=${_compactLayout?.toString() ?? '-'} scrollPolicy=${widget.contentMode.scrollPolicy} pageCount=${book?.pageCount ?? 0} activePage=${book?.activePage ?? 0} pageTextLength=${book?.pageTextLength ?? 0} pageViewportWidth=${book?.pageViewportWidth.toStringAsFixed(1) ?? '-'} pageViewportHeight=${book?.pageViewportHeight.toStringAsFixed(1) ?? '-'} activePageId=${book?.activePageId ?? '-'} pageInternalScroll=${book?.internalScroll ?? false} storageMode=structured_pages autoPagination=false textScale=${book?.textScale.toStringAsFixed(2) ?? '-'} pageAxis=${widget.contentMode.pageAxis}',
    );
    if (!mounted) return;
    await trace.showSnapshotStatusDialog(
      context,
      title: widget.contentMode.statusTitle,
      description: [
        'source=${widget.source}',
        'side=${widget.side.name}',
        'division=${widget.division.trim()}',
        'area=${widget.area.trim()}',
        'capabilityEnabled=${widget.capabilityEnabled}',
        'loading=$_loading',
        'failed=$_failed',
        'ruleFound=$_ruleFound',
        'selectedContentAvailable=$_contentAvailable',
        'selectedContentLength=${_content.length}',
        'itemCount=$_itemCount',
        'manualLineCount=$_manualLineCount',
        'contentLength=${_rule?.content.trim().length ?? 0}',
        'responseManualLength=${_rule?.responseManual.length ?? 0}',
        'responseManualPageCount=${_rule?.responseManualPages.length ?? 0}',
        'legacyFallback=${_rule?.responseManualUsesLegacyFallback ?? false}',
        'renderMode=${widget.contentMode.renderMode}',
        'autoNumbering=${widget.contentMode.autoNumbering}',
        'preserveBlankLines=${widget.contentMode.preserveBlankLines}',
        'updatedAt=${_rule?.updatedAt?.toIso8601String() ?? '-'}',
        'contentMode=${widget.contentMode.debugName}',
        'refreshRevision=${widget.refreshRevision}',
        'visualStyle=${widget.contentMode.visualStyle}',
        'layoutMode=side_dock_fill',
        'viewportWidth=${_formatViewportValue(_viewportWidth)}',
        'viewportHeight=${_formatViewportValue(_viewportHeight)}',
        'compactLayout=${_compactLayout?.toString() ?? '-'}',
        'scrollPolicy=${widget.contentMode.scrollPolicy}',
        'pageCount=${book?.pageCount ?? 0}',
        'activePage=${book?.activePage ?? 0}',
        'pageTextLength=${book?.pageTextLength ?? 0}',
        'pageViewportWidth=${book?.pageViewportWidth.toStringAsFixed(1) ?? '-'}',
        'pageViewportHeight=${book?.pageViewportHeight.toStringAsFixed(1) ?? '-'}',
        'activePageId=${book?.activePageId ?? '-'}',
        'pageInternalScroll=${book?.internalScroll ?? false}',
        'storageMode=structured_pages',
        'autoPagination=false',
        'textScale=${book?.textScale.toStringAsFixed(2) ?? '-'}',
        'pageAxis=${widget.contentMode.pageAxis}',
        'dataSource=operational_sqlite',
        'remoteRead=0',
        'remoteWrite=0',
      ].join('\n'),
      failure: _failed,
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_loading) {
      return WorkRuleReportMessageSurface(
        key: ValueKey<String>('work_rule_${widget.contentMode.debugName}_loading'),
        area: widget.area,
        statusLabel: '불러오는 중',
        message: widget.contentMode.loadingMessage,
        contentMode: widget.contentMode,
        showProgress: true,
        fillAvailableHeight: true,
      );
    }
    if (!widget.capabilityEnabled) {
      return WorkRuleReportMessageSurface(
        key: ValueKey<String>('work_rule_${widget.contentMode.debugName}_unavailable'),
        area: widget.area,
        statusLabel: '사용 불가',
        message: '현재 지역에서는 업무 규칙 기능을 사용하지 않습니다.',
        contentMode: widget.contentMode,
        fillAvailableHeight: true,
      );
    }
    if (_failed) {
      return WorkRuleReportMessageSurface(
        key: ValueKey<String>('work_rule_${widget.contentMode.debugName}_failed'),
        area: widget.area,
        statusLabel: '불러오기 실패',
        message: widget.contentMode.failedMessage,
        contentMode: widget.contentMode,
        actionLabel: '다시 불러오기',
        onAction: () => unawaited(_load()),
        fillAvailableHeight: true,
      );
    }
    final rule = _rule;
    if (rule == null || !_contentAvailable) {
      return WorkRuleReportMessageSurface(
        key: ValueKey<String>('work_rule_${widget.contentMode.debugName}_empty'),
        area: widget.area,
        statusLabel: '미등록',
        message: widget.contentMode.emptyMessage,
        itemCount: 0,
        contentMode: widget.contentMode,
        fillAvailableHeight: true,
      );
    }
    if (widget.contentMode == WorkRuleReportContentMode.responseManual) {
      return WorkManualBookReader(
        key: ValueKey<String>(
          'work_manual_book_${rule.id}_${rule.updatedAt?.millisecondsSinceEpoch ?? 0}_${rule.responseManualPages.length}_${_content.length}',
        ),
        pages: rule.responseManualPages,
        updatedAt: rule.updatedAt,
        onDebug: _debug,
        onDiagnosticsChanged: (value) {
          _manualBookDiagnostics = value;
        },
      );
    }
    return WorkRuleReportSurface(
      key: ValueKey<String>(
        'work_rule_notice_ready_${rule.id}_${rule.updatedAt?.millisecondsSinceEpoch ?? 0}_${_content.length}',
      ),
      area: widget.area,
      rule: rule,
      fillAvailableHeight: true,
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
                widget.contentMode.icon,
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
                    widget.contentMode.workspaceTitle,
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
                label: widget.contentMode.statusTitle,
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
          child: LayoutBuilder(
            builder: (context, constraints) {
              _recordViewport(constraints);
              return AnimatedSwitcher(
                duration: reduceMotion
                    ? Duration.zero
                    : const Duration(milliseconds: 150),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                transitionBuilder: (child, animation) {
                  if (reduceMotion) return child;
                  final curved = CurvedAnimation(
                    parent: animation,
                    curve: Curves.easeOutCubic,
                    reverseCurve: Curves.easeInCubic,
                  );
                  return FadeTransition(
                    opacity: curved,
                    child: SlideTransition(
                      position: Tween<Offset>(
                        begin: const Offset(0, 0.018),
                        end: Offset.zero,
                      ).animate(curved),
                      child: ScaleTransition(
                        scale: Tween<double>(begin: 0.992, end: 1).animate(curved),
                        child: child,
                      ),
                    ),
                  );
                },
                child: _buildBody(context),
              );
            },
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
    this.dense = false,
    this.fillAvailableHeight = false,
  });

  final String area;
  final RuleModel rule;
  final bool dense;
  final bool fillAvailableHeight;

  String _formatUpdatedAt(DateTime? value) {
    if (value == null) return '-';
    final local = value.toLocal();
    String two(int number) => number.toString().padLeft(2, '0');
    return '${local.year}.${two(local.month)}.${two(local.day)} ${two(local.hour)}:${two(local.minute)}';
  }

  Widget _buildNoticeBody(
    BuildContext context, {
    required bool compact,
    required String content,
  }) {
    final tokens = CommonUiTheme.of(context);
    final items = splitWorkRuleNoticeItems(content);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var index = 0; index < items.length; index++) ...[
          CommonOperationalReportNumberedRow(
            index: index,
            text: items[index],
            dense: compact,
            semanticLabel:
                '업무 안내 ${index + 1}, ${items[index]}',
          ),
          if (index < items.length - 1)
            Divider(height: 1, color: tokens.borderSubtle),
        ],
      ],
    );
  }

  Widget _buildLead(
    BuildContext context, {
    required bool compact,
    required String resolvedArea,
    required String content,
  }) {
    final tokens = CommonUiTheme.of(context);
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '업무 안내문',
          style: (compact ? text.titleSmall : text.titleLarge)?.copyWith(
            color: tokens.textPrimary,
            fontWeight: compact ? FontWeight.w800 : FontWeight.w700,
            height: 1.35,
          ),
        ),
        SizedBox(height: compact ? 14 : 18),
        CommonOperationalReportMetadataRow(
          dense: compact,
          label: '근무 위치',
          value: Text(
            resolvedArea.isEmpty ? '현재 지역' : resolvedArea,
            textAlign: TextAlign.right,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: text.bodyMedium?.copyWith(
              color: tokens.textPrimary,
              fontWeight: FontWeight.w600,
              height: 1.4,
            ),
          ),
        ),
        const SizedBox(height: 8),
        CommonOperationalReportMetadataRow(
          dense: compact,
          label: '안내 항목',
          value: Text(
            '${splitWorkRuleNoticeItems(content).length}건',
            textAlign: TextAlign.right,
            style: text.bodyMedium?.copyWith(
              color: tokens.textPrimary,
              fontWeight: FontWeight.w600,
              height: 1.4,
            ),
          ),
        ),
        const SizedBox(height: 8),
        CommonOperationalReportMetadataRow(
          dense: compact,
          label: '상태',
          value: Text(
            '열람 가능',
            textAlign: TextAlign.right,
            style: text.bodyMedium?.copyWith(
              color: tokens.success,
              fontWeight: FontWeight.w700,
              height: 1.4,
            ),
          ),
        ),
        SizedBox(height: compact ? 14 : 18),
        Divider(height: 1, color: tokens.borderStrong),
        const SizedBox(height: 4),
        _buildNoticeBody(
          context,
          compact: compact,
          content: content,
        ),
      ],
    );
  }

  Widget _buildFooter(
    BuildContext context, {
    required bool compact,
  }) {
    final tokens = CommonUiTheme.of(context);
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 4),
        Divider(height: 1, color: tokens.borderStrong),
        SizedBox(height: compact ? 12 : 14),
        CommonOperationalReportMetadataRow(
          dense: compact,
          label: '마지막 수정',
          value: Text(
            _formatUpdatedAt(rule.updatedAt),
            textAlign: TextAlign.right,
            style: text.bodyMedium?.copyWith(
              color: tokens.textSecondary,
              fontWeight: FontWeight.w600,
              height: 1.4,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCompactContent(
    BuildContext context, {
    required bool compact,
    required String resolvedArea,
    required String content,
  }) {
    final horizontalPadding = compact ? 12.0 : 20.0;
    final topPadding = compact ? 12.0 : 18.0;
    final bottomPadding = compact ? 12.0 : 14.0;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        horizontalPadding,
        topPadding,
        horizontalPadding,
        bottomPadding,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildLead(
            context,
            compact: compact,
            resolvedArea: resolvedArea,
            content: content,
          ),
          _buildFooter(context, compact: compact),
        ],
      ),
    );
  }

  Widget _buildFullHeightContent(
    BuildContext context,
    BoxConstraints constraints, {
    required String resolvedArea,
    required String content,
  }) {
    final compact = dense || _useCompactWorkRuleLayout(constraints);
    final horizontalPadding = compact ? 12.0 : 20.0;
    final topPadding = compact ? 12.0 : 18.0;
    final bottomPadding = compact ? 12.0 : 14.0;
    return CustomScrollView(
      physics: const ClampingScrollPhysics(),
      slivers: [
        SliverPadding(
          padding: EdgeInsets.fromLTRB(
            horizontalPadding,
            topPadding,
            horizontalPadding,
            0,
          ),
          sliver: SliverToBoxAdapter(
            child: _buildLead(
              context,
              compact: compact,
              resolvedArea: resolvedArea,
              content: content,
            ),
          ),
        ),
        SliverFillRemaining(
          hasScrollBody: false,
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              horizontalPadding,
              0,
              horizontalPadding,
              bottomPadding,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildFooter(context, compact: compact),
              ],
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final resolvedArea = area.trim().isEmpty ? rule.area.trim() : area.trim();
    final content = rule.content.trim();
    if (!fillAvailableHeight) {
      return _buildCompactContent(
        context,
        compact: dense,
        resolvedArea: resolvedArea,
        content: content,
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        return _buildFullHeightContent(
          context,
          constraints,
          resolvedArea: resolvedArea,
          content: content,
        );
      },
    );
  }
}

class WorkRuleReportMessageSurface extends StatelessWidget {
  const WorkRuleReportMessageSurface({
    super.key,
    required this.area,
    required this.statusLabel,
    required this.message,
    this.contentMode = WorkRuleReportContentMode.notice,
    this.itemCount,
    this.showProgress = false,
    this.actionLabel,
    this.onAction,
    this.dense = false,
    this.fillAvailableHeight = false,
  });

  final String area;
  final String statusLabel;
  final String message;
  final WorkRuleReportContentMode contentMode;
  final int? itemCount;
  final bool showProgress;
  final String? actionLabel;
  final VoidCallback? onAction;
  final bool dense;
  final bool fillAvailableHeight;

  Color _statusColor(CommonUiTokens tokens) {
    if (statusLabel == '불러오기 실패') return tokens.danger;
    if (statusLabel == '사용 불가') return tokens.warning;
    if (statusLabel == '열람 가능') return tokens.success;
    return tokens.textSecondary;
  }

  String get _metricValue {
    if (itemCount == null) return '-';
    switch (contentMode) {
      case WorkRuleReportContentMode.notice:
        return '$itemCount건';
      case WorkRuleReportContentMode.responseManual:
        return '$itemCount페이지';
    }
  }

  Widget _buildLead(
    BuildContext context, {
    required bool compact,
    required String resolvedArea,
  }) {
    final tokens = CommonUiTheme.of(context);
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          contentMode.contentTitle,
          style: (compact ? text.titleSmall : text.titleLarge)?.copyWith(
            color: tokens.textPrimary,
            fontWeight: compact ? FontWeight.w800 : FontWeight.w700,
            height: 1.35,
          ),
        ),
        SizedBox(height: compact ? 14 : 18),
        CommonOperationalReportMetadataRow(
          dense: compact,
          label: '근무 위치',
          value: Text(
            resolvedArea,
            textAlign: TextAlign.right,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: text.bodyMedium?.copyWith(
              color: tokens.textPrimary,
              fontWeight: FontWeight.w600,
              height: 1.4,
            ),
          ),
        ),
        const SizedBox(height: 8),
        CommonOperationalReportMetadataRow(
          dense: compact,
          label: contentMode.itemLabel,
          value: Text(
            _metricValue,
            textAlign: TextAlign.right,
            style: text.bodyMedium?.copyWith(
              color: tokens.textPrimary,
              fontWeight: FontWeight.w600,
              height: 1.4,
            ),
          ),
        ),
        const SizedBox(height: 8),
        CommonOperationalReportMetadataRow(
          dense: compact,
          label: '상태',
          value: Text(
            statusLabel,
            textAlign: TextAlign.right,
            style: text.bodyMedium?.copyWith(
              color: _statusColor(tokens),
              fontWeight: FontWeight.w700,
              height: 1.4,
            ),
          ),
        ),
        SizedBox(height: compact ? 14 : 18),
        Divider(height: 1, color: tokens.borderStrong),
        Padding(
          padding: EdgeInsets.symmetric(
            horizontal: 4,
            vertical: compact ? 16 : 20,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                message,
                textAlign: TextAlign.left,
                style: text.bodyMedium?.copyWith(
                  color: tokens.textPrimary,
                  fontWeight: FontWeight.w600,
                  height: 1.45,
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
                Align(
                  alignment: Alignment.centerRight,
                  child: OutlinedButton.icon(
                    onPressed: onAction,
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                    label: Text(actionLabel!),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCompactContent(
    BuildContext context, {
    required bool compact,
    required String resolvedArea,
  }) {
    final tokens = CommonUiTheme.of(context);
    final horizontalPadding = compact ? 12.0 : 20.0;
    final topPadding = compact ? 12.0 : 18.0;
    final bottomPadding = compact ? 12.0 : 14.0;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        horizontalPadding,
        topPadding,
        horizontalPadding,
        bottomPadding,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildLead(
            context,
            compact: compact,
            resolvedArea: resolvedArea,
          ),
          Divider(height: 1, color: tokens.borderStrong),
        ],
      ),
    );
  }

  Widget _buildFullHeightContent(
    BuildContext context,
    BoxConstraints constraints, {
    required String resolvedArea,
  }) {
    final tokens = CommonUiTheme.of(context);
    final compact = dense || _useCompactWorkRuleLayout(constraints);
    final horizontalPadding = compact ? 12.0 : 20.0;
    final topPadding = compact ? 12.0 : 18.0;
    final bottomPadding = compact ? 12.0 : 14.0;
    return CustomScrollView(
      physics: const ClampingScrollPhysics(),
      slivers: [
        SliverPadding(
          padding: EdgeInsets.fromLTRB(
            horizontalPadding,
            topPadding,
            horizontalPadding,
            0,
          ),
          sliver: SliverToBoxAdapter(
            child: _buildLead(
              context,
              compact: compact,
              resolvedArea: resolvedArea,
            ),
          ),
        ),
        SliverFillRemaining(
          hasScrollBody: false,
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              horizontalPadding,
              0,
              horizontalPadding,
              bottomPadding,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Divider(height: 1, color: tokens.borderStrong),
              ],
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final resolvedArea = area.trim().isEmpty ? '현재 지역' : area.trim();
    if (!fillAvailableHeight) {
      return _buildCompactContent(
        context,
        compact: dense,
        resolvedArea: resolvedArea,
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        return _buildFullHeightContent(
          context,
          constraints,
          resolvedArea: resolvedArea,
        );
      },
    );
  }
}
