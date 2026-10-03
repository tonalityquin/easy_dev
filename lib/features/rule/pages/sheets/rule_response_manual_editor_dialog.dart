import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../app/utils/developer_operation_status_dialog.dart';
import '../../../../design_system/common_ui/common_ui_components.dart';
import '../../../../design_system/common_ui/common_ui_theme.dart';
import '../../../../shared/secondary/widgets/ops_console_dialogs.dart';
import '../../domain/models/rule_model.dart';
import '../../domain/utils/work_manual_text.dart';

class RuleResponseManualEditorDialog extends StatefulWidget {
  const RuleResponseManualEditorDialog({
    super.key,
    required this.initialPages,
    required this.trace,
  });

  final List<RuleManualPage> initialPages;
  final DeveloperOperationTrace trace;

  @override
  State<RuleResponseManualEditorDialog> createState() =>
      _RuleResponseManualEditorDialogState();
}

class _RuleResponseManualEditorDialogState
    extends State<RuleResponseManualEditorDialog> {
  static const int _maxLength = 4000;

  final List<_RuleManualPageDraft> _pages = <_RuleManualPageDraft>[];
  bool _submitted = false;
  bool _reduceMotion = false;
  int _activePage = 0;

  List<RuleManualPage> get _snapshotPages {
    final result = <RuleManualPage>[];
    for (final draft in _pages) {
      final content = normalizeWorkManualForStorage(draft.controller.text);
      if (isWorkManualBlank(content)) continue;
      result.add(
        RuleManualPage(
          id: draft.id,
          content: content,
          order: result.length,
        ),
      );
    }
    return List<RuleManualPage>.unmodifiable(result);
  }

  int get _totalLength => flattenRuleManualPages(_snapshotPages).length;

  int get _emptyPageCount =>
      _pages.where((page) => isWorkManualBlank(page.controller.text)).length;

  String get _error {
    if (_totalLength > _maxLength) {
      return '업무 메뉴얼은 전체 $_maxLength자 이하로 입력해 주세요.';
    }
    return '';
  }

  @override
  void initState() {
    super.initState();
    final initial = normalizeRuleManualPagesForStorage(widget.initialPages);
    if (initial.isEmpty) {
      _pages.add(_newDraft());
    } else {
      for (final page in initial) {
        _pages.add(
          _RuleManualPageDraft(
            id: page.id,
            controller: TextEditingController(text: page.content),
            focusNode: FocusNode(),
          ),
        );
      }
    }
    widget.trace.log(
      '업무 메뉴얼 편집 Dialog 시작 editorMode=structured_pages initialPageCount=${initial.length} totalLength=${flattenRuleManualPages(initial).length} autoPagination=false pageBoundarySource=author_defined',
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
  }

  @override
  void dispose() {
    for (final page in _pages) {
      page.dispose();
    }
    super.dispose();
  }

  _RuleManualPageDraft _newDraft() {
    return _RuleManualPageDraft(
      id: 'manual_${DateTime.now().microsecondsSinceEpoch}_${_pages.length}',
      controller: TextEditingController(),
      focusNode: FocusNode(),
    );
  }

  void _handleChanged(int index) {
    if (_activePage != index) {
      setState(() => _activePage = index);
    } else {
      setState(() {});
    }
  }

  void _focusPage(int index) {
    if (index < 0 || index >= _pages.length) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || index >= _pages.length) return;
      _pages[index].focusNode.requestFocus();
    });
  }

  void _insertAfter(int index) {
    final insertIndex = (index + 1).clamp(0, _pages.length).toInt();
    setState(() {
      _pages.insert(insertIndex, _newDraft());
      _activePage = insertIndex;
    });
    widget.trace.log(
      '업무 메뉴얼 페이지 추가 insertIndex=$insertIndex draftPageCount=${_pages.length}',
    );
    HapticFeedback.selectionClick();
    _focusPage(insertIndex);
  }

  Future<void> _remove(int index) async {
    if (index < 0 || index >= _pages.length) return;
    final draft = _pages[index];
    if (!isWorkManualBlank(draft.controller.text)) {
      final confirmed = await showOpsConfirmDialog(
        context: context,
        title: '업무 메뉴얼 페이지 삭제',
        message: '${index + 1}페이지를 삭제하시겠습니까?',
        confirmLabel: '삭제',
        icon: Icons.delete_forever_rounded,
        destructive: true,
      );
      if (!confirmed || !mounted) return;
    }
    if (_pages.length == 1) {
      draft.controller.clear();
      setState(() => _activePage = 0);
      widget.trace.log('업무 메뉴얼 마지막 페이지 내용 비움 draftPageCount=1');
      HapticFeedback.mediumImpact();
      _focusPage(0);
      return;
    }
    final removed = _pages.removeAt(index);
    removed.dispose();
    setState(() {
      _activePage = _activePage.clamp(0, _pages.length - 1).toInt();
    });
    widget.trace.log(
      '업무 메뉴얼 페이지 삭제 index=$index draftPageCount=${_pages.length}',
    );
    HapticFeedback.mediumImpact();
    _focusPage(_activePage);
  }

  void _move(int index, int delta) {
    final target = index + delta;
    if (index < 0 || index >= _pages.length || target < 0 || target >= _pages.length) {
      return;
    }
    setState(() {
      final page = _pages.removeAt(index);
      _pages.insert(target, page);
      _activePage = target;
    });
    widget.trace.log(
      '업무 메뉴얼 페이지 순서 변경 from=$index to=$target draftPageCount=${_pages.length}',
    );
    HapticFeedback.selectionClick();
    _focusPage(target);
  }

  List<RuleManualPage> _resultPages() {
    final result = <RuleManualPage>[];
    final usedIds = <String>{};
    for (var index = 0; index < _pages.length; index += 1) {
      final draft = _pages[index];
      final content = normalizeWorkManualForStorage(draft.controller.text);
      if (isWorkManualBlank(content)) continue;
      var id = draft.id.trim();
      if (id.isEmpty || isLegacyRuleManualPageId(id) || usedIds.contains(id)) {
        id = 'manual_${DateTime.now().microsecondsSinceEpoch}_${result.length}';
        while (usedIds.contains(id)) {
          id = 'manual_${DateTime.now().microsecondsSinceEpoch}_${result.length}_${usedIds.length}';
        }
      }
      usedIds.add(id);
      result.add(
        RuleManualPage(
          id: id,
          content: content,
          order: result.length,
        ),
      );
    }
    return List<RuleManualPage>.unmodifiable(result);
  }

  void _apply() {
    setState(() => _submitted = true);
    final error = _error;
    if (error.isNotEmpty) {
      widget.trace.log('업무 메뉴얼 편집 validation 실패 reason=$error');
      HapticFeedback.mediumImpact();
      return;
    }
    final pages = _resultPages();
    final flattened = flattenRuleManualPages(pages);
    widget.trace.log(
      '업무 메뉴얼 편집 적용 storageMode=structured_pages pageCount=${pages.length} totalLength=${flattened.length} emptyDraftPageCount=$_emptyPageCount autoPagination=false',
    );
    HapticFeedback.selectionClick();
    Navigator.of(context, rootNavigator: true).pop(pages);
  }

  void _cancel() {
    widget.trace.log(
      '업무 메뉴얼 편집 취소 draftPageCount=${_pages.length} savedPageCount=${_snapshotPages.length} totalLength=$_totalLength',
    );
    Navigator.of(context, rootNavigator: true).pop();
  }

  Future<void> _showDeveloperStatus() async {
    final pages = _snapshotPages;
    final ids = pages.map((page) => page.id).join(',');
    widget.trace.log(
      '업무 메뉴얼 편집 개발자 상태 요청 storageMode=structured_pages draftPageCount=${_pages.length} savedPageCount=${pages.length} activeEditorPage=${_activePage + 1} emptyDraftPageCount=$_emptyPageCount totalLength=$_totalLength submitted=$_submitted pageOrder=$ids autoPagination=false pageBoundarySource=author_defined preserveBlankLines=true',
    );
    await widget.trace.showSnapshotStatusDialog(
      context,
      title: '업무 메뉴얼 편집 상태',
      description: [
        'editorMode=structured_pages',
        'storageMode=structured_pages',
        'draftPageCount=${_pages.length}',
        'savedPageCount=${pages.length}',
        'activeEditorPage=${_activePage + 1}',
        'emptyDraftPageCount=$_emptyPageCount',
        'totalLength=$_totalLength',
        'pageOrder=$ids',
        'autoPagination=false',
        'pageBoundarySource=author_defined',
        'pageInternalScroll=true',
        'autoNumbering=false',
        'preserveBlankLines=true',
      ].join('\n'),
      failure: _submitted && _error.isNotEmpty,
    );
  }

  InputDecoration _flatDecoration() {
    return const InputDecoration(
      border: InputBorder.none,
      enabledBorder: InputBorder.none,
      focusedBorder: InputBorder.none,
      errorBorder: InputBorder.none,
      focusedErrorBorder: InputBorder.none,
      disabledBorder: InputBorder.none,
      isDense: true,
      contentPadding: EdgeInsets.fromLTRB(0, 12, 0, 12),
      counterText: '',
    );
  }

  Widget _headerAction({
    required String semanticsLabel,
    required IconData icon,
    required VoidCallback? onPressed,
  }) {
    final tokens = CommonUiTheme.of(context);
    return Semantics(
      button: true,
      label: semanticsLabel,
      child: IconButton(
        onPressed: onPressed,
        icon: Icon(icon, size: 20, color: tokens.iconSecondary),
      ),
    );
  }

  Widget _pageAction({
    required String semanticsLabel,
    required IconData icon,
    required VoidCallback? onPressed,
    bool destructive = false,
  }) {
    final tokens = CommonUiTheme.of(context);
    return Semantics(
      button: true,
      label: semanticsLabel,
      child: IconButton(
        visualDensity: VisualDensity.compact,
        onPressed: onPressed,
        icon: Icon(
          icon,
          size: 18,
          color: destructive ? tokens.danger : tokens.iconSecondary,
        ),
      ),
    );
  }

  Widget _buildPageCard(BuildContext context, int index) {
    final tokens = CommonUiTheme.of(context);
    final theme = Theme.of(context);
    final draft = _pages[index];
    final active = _activePage == index;
    final contentLength = normalizeWorkManualText(draft.controller.text).length;
    return CommonAnimatedReveal(
      key: ValueKey<String>('manual_editor_page_${draft.id}'),
      duration: _reduceMotion ? Duration.zero : CommonUiMotion.component,
      offset: const Offset(0, .02),
      child: AnimatedContainer(
        duration: _reduceMotion ? Duration.zero : CommonUiMotion.selection,
        curve: CommonUiMotion.standard,
        decoration: BoxDecoration(
          color: tokens.surfaceRaised,
          borderRadius: BorderRadius.circular(CommonUiShapes.card),
          border: Border.all(
            color: active ? tokens.accent : tokens.borderSubtle,
            width: active ? 1.4 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: tokens.shadow,
              blurRadius: active ? 20 : 12,
              offset: Offset(0, active ? 8 : 5),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  AnimatedContainer(
                    duration: _reduceMotion
                        ? Duration.zero
                        : CommonUiMotion.selection,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: active
                          ? tokens.accentContainer
                          : tokens.surfaceOverlay,
                      borderRadius: BorderRadius.circular(CommonUiShapes.pill),
                      border: Border.all(
                        color: active ? tokens.accent : tokens.borderSubtle,
                      ),
                    ),
                    child: Text(
                      '${(index + 1).toString().padLeft(2, '0')} 페이지',
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: active
                            ? tokens.onAccentContainer
                            : tokens.textSecondary,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    '$contentLength자',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: tokens.textSecondary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  _pageAction(
                    semanticsLabel: '${index + 1}페이지를 앞으로 이동',
                    icon: Icons.keyboard_arrow_up_rounded,
                    onPressed: index == 0 ? null : () => _move(index, -1),
                  ),
                  _pageAction(
                    semanticsLabel: '${index + 1}페이지를 뒤로 이동',
                    icon: Icons.keyboard_arrow_down_rounded,
                    onPressed: index >= _pages.length - 1
                        ? null
                        : () => _move(index, 1),
                  ),
                  _pageAction(
                    semanticsLabel: '${index + 1}페이지 뒤에 새 페이지 추가',
                    icon: Icons.add_rounded,
                    onPressed: () => _insertAfter(index),
                  ),
                  _pageAction(
                    semanticsLabel: '${index + 1}페이지 삭제',
                    icon: Icons.delete_outline_rounded,
                    onPressed: () => _remove(index),
                    destructive: true,
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Divider(height: 1, color: tokens.borderSubtle),
              const SizedBox(height: 8),
              LayoutBuilder(
                builder: (context, constraints) {
                  final editorHeight = constraints.maxWidth < 520 ? 260.0 : 320.0;
                  return SizedBox(
                    height: editorHeight,
                    child: TextField(
                      controller: draft.controller,
                      focusNode: draft.focusNode,
                      expands: true,
                      minLines: null,
                      maxLines: null,
                      maxLength: _maxLength,
                      maxLengthEnforcement: MaxLengthEnforcement.enforced,
                      keyboardType: TextInputType.multiline,
                      textInputAction: TextInputAction.newline,
                      textAlignVertical: TextAlignVertical.top,
                      onTap: () {
                        if (_activePage != index) {
                          setState(() => _activePage = index);
                        }
                      },
                      onTapOutside: (_) => FocusScope.of(context).unfocus(),
                      onChanged: (_) => _handleChanged(index),
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: tokens.textPrimary,
                        height: 1.58,
                        fontWeight: FontWeight.w500,
                      ),
                      decoration: _flatDecoration(),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPageDivider(BuildContext context, int afterIndex) {
    final tokens = CommonUiTheme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Row(
        children: [
          Expanded(child: Divider(height: 1, color: tokens.borderSubtle)),
          const SizedBox(width: 10),
          Text(
            '페이지 구분',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: tokens.textSecondary,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(child: Divider(height: 1, color: tokens.borderSubtle)),
          const SizedBox(width: 4),
          _pageAction(
            semanticsLabel: '${afterIndex + 1}페이지 뒤에 새 페이지 삽입',
            icon: Icons.add_circle_outline_rounded,
            onPressed: () => _insertAfter(afterIndex),
          ),
        ],
      ),
    );
  }

  Widget _buildPageList(BuildContext context) {
    final children = <Widget>[];
    for (var index = 0; index < _pages.length; index += 1) {
      children.add(_buildPageCard(context, index));
      if (index < _pages.length - 1) {
        children.add(_buildPageDivider(context, index));
      }
    }
    children.add(const SizedBox(height: 16));
    children.add(
      CommonButton(
        label: '새 페이지 추가',
        icon: Icons.add_rounded,
        onPressed: () => _insertAfter(_pages.length - 1),
        variant: CommonButtonVariant.secondary,
        haptic: CommonHaptic.none,
        expand: true,
      ),
    );
    return ListView(
      physics: const ClampingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(2, 2, 2, 8),
      children: children,
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final media = MediaQuery.of(context);
    final availableHeight =
        media.size.height - media.padding.vertical - media.viewInsets.bottom - 40;
    final dialogHeight = availableHeight.clamp(0.0, 800.0).toDouble();
    final error = _submitted ? _error : '';
    final savedPages = _snapshotPages;

    return Dialog(
      backgroundColor: tokens.surfaceRaised,
      surfaceTintColor: tokens.transparent,
      shadowColor: tokens.shadow,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(CommonUiShapes.dialog),
        side: BorderSide(color: tokens.borderSubtle),
      ),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 860),
        child: SizedBox(
          width: 860,
          height: dialogHeight,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.menu_book_rounded,
                      size: 22,
                      color: tokens.accent,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '업무 메뉴얼',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: tokens.textPrimary,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    AnimatedSwitcher(
                      duration: _reduceMotion
                          ? Duration.zero
                          : CommonUiMotion.selection,
                      child: Text(
                        '${_pages.length}페이지 편집',
                        key: ValueKey<int>(_pages.length),
                        style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          color: tokens.textSecondary,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    if (widget.trace.developerMode)
                      _headerAction(
                        semanticsLabel: '업무 메뉴얼 편집 상태 확인',
                        icon: Icons.bug_report_rounded,
                        onPressed: _showDeveloperStatus,
                      ),
                    _headerAction(
                      semanticsLabel: '업무 메뉴얼 편집 닫기',
                      icon: Icons.close_rounded,
                      onPressed: _cancel,
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Divider(height: 1, color: tokens.borderStrong),
                const SizedBox(height: 12),
                Expanded(child: _buildPageList(context)),
                const SizedBox(height: 10),
                Divider(height: 1, color: tokens.borderSubtle),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Text(
                      savedPages.isEmpty ? '저장 페이지 없음' : '저장 ${savedPages.length}페이지',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: savedPages.isEmpty
                            ? tokens.textSecondary
                            : tokens.success,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const Spacer(),
                    AnimatedDefaultTextStyle(
                      duration: _reduceMotion
                          ? Duration.zero
                          : CommonUiMotion.selection,
                      style: (Theme.of(context).textTheme.labelSmall ??
                              const TextStyle())
                          .copyWith(
                        color: _totalLength > _maxLength
                            ? tokens.danger
                            : tokens.textSecondary,
                        fontWeight: FontWeight.w700,
                      ),
                      child: Text('$_totalLength/$_maxLength자'),
                    ),
                  ],
                ),
                AnimatedSize(
                  duration: _reduceMotion
                      ? Duration.zero
                      : CommonUiMotion.selection,
                  curve: CommonUiMotion.enter,
                  child: error.isEmpty
                      ? const SizedBox(height: 10)
                      : Padding(
                          padding: const EdgeInsets.only(top: 8, bottom: 2),
                          child: Text(
                            error,
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: tokens.danger,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                ),
                Row(
                  children: [
                    Expanded(
                      child: CommonButton(
                        label: '취소',
                        onPressed: _cancel,
                        variant: CommonButtonVariant.secondary,
                        expand: true,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: CommonButton(
                        label: '적용',
                        icon: Icons.check_rounded,
                        onPressed: _apply,
                        haptic: CommonHaptic.medium,
                        expand: true,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RuleManualPageDraft {
  const _RuleManualPageDraft({
    required this.id,
    required this.controller,
    required this.focusNode,
  });

  final String id;
  final TextEditingController controller;
  final FocusNode focusNode;

  void dispose() {
    controller.dispose();
    focusNode.dispose();
  }
}
