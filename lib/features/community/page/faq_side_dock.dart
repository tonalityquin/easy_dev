import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/utils/status_dialog.dart';
import '../../../design_system/common_ui/common_ui_components.dart';
import '../../../design_system/common_ui/common_ui_side_dock.dart';
import '../../../design_system/common_ui/common_ui_side_dock_frame.dart';
import '../../../design_system/common_ui/common_ui_theme.dart';
import '../../../shared/secondary/widgets/ops_console_widgets.dart';
import '../../selector/application/dev_auth.dart';

@immutable
class _FaqEntry {
  const _FaqEntry({
    required this.code,
    required this.question,
    required this.answer,
  });

  final String code;
  final String question;
  final String answer;

  String get searchable => '$code $question $answer';
}

const List<_FaqEntry> _faqCatalog = [
  _FaqEntry(
    code: 'err_launcher_clean',
    question: '런처 터미널 로그인 화면',
    answer:
        '입력한 계정 정보를 다시 확인하세요. (err_launcher_clean)\n\n'
        '입력한 계정 코드에 해당하는 사용자 계정을 확인할 수 없는 경우 표시됩니다.\n\n'
        '계정 코드를 다시 확인한 후 로그인해주세요.',
  ),
  _FaqEntry(
    code: 'err_launcher_cool_cool',
    question: '런처 터미널 로그인 화면',
    answer:
        '입력한 계정 정보를 다시 확인하세요. (err_launcher_cool_cool)\n\n'
        '사용자 계정은 존재하지만 현재 활성 상태가 아닌 경우 표시됩니다.\n\n'
        '관리자에게 계정 활성 상태를 확인해주세요.',
  ),
  _FaqEntry(
    code: 'err_launcher_wrong',
    question: '런처 터미널 로그인 화면',
    answer:
        '입력한 계정 정보를 다시 확인하세요. (err_launcher_wrong)\n\n'
        '사용자 계정은 존재하고 활성 상태이지만 입력한 이름과 계정 정보가 일치하지 않는 경우 표시됩니다.\n\n'
        '이름과 계정 정보를 다시 확인한 후 로그인해주세요.',
  ),
  _FaqEntry(
    code: 'err_lost_user',
    question: '출근 화면 · 계정 확인',
    answer:
        '출근 계정 정보를 확인할 수 없습니다. (err_lost_user)\n\n'
        '출근 직전 서버에서 현재 사용자 계정 문서를 확인할 수 없는 경우 표시됩니다.\n\n'
        '현재 로그인 계정을 확인한 후 다시 시도해주세요.',
  ),
  _FaqEntry(
    code: 'err_cool_cool_user',
    question: '출근 화면 · 계정 확인',
    answer:
        '현재 계정으로 출근할 수 없습니다. (err_cool_cool_user)\n\n'
        '출근 직전 서버에서 확인한 사용자 계정이 현재 활성 상태가 아닌 경우 표시됩니다.\n\n'
        '관리자에게 계정 활성 상태를 확인해주세요.',
  ),
  _FaqEntry(
    code: 'err_lost_internet',
    question: '출근 화면 · 계정 확인 및 서버 동기화',
    answer:
        '네트워크 연결을 확인한 후 다시 시도하세요. (err_lost_internet)\n\n'
        '출근 계정 확인 또는 서버 근무 상태 동기화 중 네트워크 연결을 사용할 수 없는 경우 표시됩니다.\n\n'
        '인터넷 연결 상태를 확인한 후 다시 시도해주세요.',
  ),
  _FaqEntry(
    code: 'err_block_working',
    question: '출근 화면 · 계정 확인 및 서버 동기화',
    answer:
        '출근 권한을 확인할 수 없습니다. (err_block_working)\n\n'
        '출근 계정 확인 또는 서버 근무 상태 반영 과정에서 접근 권한이 허용되지 않은 경우 표시됩니다.\n\n'
        '반복해서 발생하면 관리자에게 문의해주세요.',
  ),
  _FaqEntry(
    code: 'err_check_sync_user',
    question: '출근 화면 · 계정 확인',
    answer:
        '출근 계정 확인 중 오류가 발생했습니다. (err_check_sync_user)\n\n'
        '출근 직전 사용자 계정을 서버에서 확인하는 과정에서 기타 오류가 발생한 경우 표시됩니다.\n\n'
        '잠시 후 다시 시도하고 반복해서 발생하면 관리자에게 문의해주세요.',
  ),
  _FaqEntry(
    code: 'err_local_save_commute',
    question: '출근 화면 · 출근 기록 저장',
    answer:
        '출근 기록을 저장하지 못했습니다. (err_local_save_commute)\n\n'
        '단말에 새로운 출근 기록을 저장하는 과정에서 오류가 발생한 경우 표시됩니다.\n\n'
        '다시 시도하고 반복해서 발생하면 관리자에게 문의해주세요.',
  ),
  _FaqEntry(
    code: 'err_switch_fallen',
    question: '출근 화면 · 근무 상태 저장',
    answer:
        '근무 상태를 저장하지 못했습니다. (err_switch_fallen)\n\n'
        '단말의 로컬 근무 상태를 isWorking으로 저장하는 과정에서 오류가 발생한 경우 표시됩니다.\n\n'
        '다시 시도하고 반복해서 발생하면 관리자에게 문의해주세요.',
  ),
  _FaqEntry(
    code: 'err_lost_switch',
    question: '출근 화면 · 서버 근무 상태 동기화',
    answer:
        '서버에 근무 상태를 반영하지 못했습니다. (err_lost_switch)\n\n'
        '로컬 출근 처리 후 서버의 근무 상태를 갱신하는 과정에서 오류가 발생한 경우 표시됩니다.\n\n'
        '네트워크 상태를 확인한 후 다시 시도해주세요.',
  ),
  _FaqEntry(
    code: 'err_runtime_error',
    question: '출근 화면 · 근무 기능 시작',
    answer:
        '근무 기능을 시작하지 못했습니다. (err_runtime_error)\n\n'
        '출근 처리 후 근무에 필요한 런타임 기능을 활성화하는 과정에서 오류가 발생한 경우 표시됩니다.\n\n'
        '다시 시도하고 반복해서 발생하면 관리자에게 문의해주세요.',
  ),
  _FaqEntry(
    code: 'err_noti_fallen',
    question: '출근 화면 · 근무 알림 시작',
    answer:
        '근무 알림을 시작하지 못했습니다. (err_noti_fallen)\n\n'
        '출근 처리 후 근무 상태 알림을 시작하거나 갱신하는 과정에서 오류가 발생한 경우 표시됩니다.\n\n'
        '알림 설정을 확인하고 반복해서 발생하면 관리자에게 문의해주세요.',
  ),
  _FaqEntry(
    code: 'err_take_mistake',
    question: '출근 화면 · 출근 처리',
    answer:
        '출근 처리 중 오류가 발생했습니다. (err_take_mistake)\n\n'
        '분류된 출근 오류 외의 예상하지 못한 문제가 발생한 경우 표시됩니다.\n\n'
        '오류 코드와 함께 관리자에게 문의해주세요.',
  ),
];

const String _faqContactFormUrl = 'https://forms.gle/nbwaFeLhJfAKAf6o8';

Future<T?> showFaqSideDock<T>({
  required BuildContext context,
  required CommonSideDockSide side,
  required String source,
}) {
  final builder = (BuildContext _) => FaqSideDockContent(
        side: side,
        source: source,
      );
  if (side == CommonSideDockSide.left) {
    return showCommonLeftSideDock<T>(
      context: context,
      builder: builder,
      barrierLabel: '오류 코드 / 문의',
      useRootNavigator: true,
      maxWidth: 460,
      widthFactor: .94,
      barrierDismissible: true,
    );
  }
  return showCommonRightSideDock<T>(
    context: context,
    builder: builder,
    barrierLabel: '오류 코드 / 문의',
    useRootNavigator: true,
    maxWidth: 460,
    widthFactor: .94,
    barrierDismissible: true,
  );
}

class FaqSideDockContent extends StatefulWidget {
  const FaqSideDockContent({
    super.key,
    required this.side,
    required this.source,
    this.onClose,
  });

  final CommonSideDockSide side;
  final String source;
  final VoidCallback? onClose;

  @override
  State<FaqSideDockContent> createState() => _FaqSideDockContentState();
}

class _FaqSideDockContentState extends State<FaqSideDockContent> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  final List<String> _debugLines = <String>[];

  String _query = '';
  String? _expandedCode;
  String _lastSearchSignature = '';
  bool _developerMode = false;
  bool _contactBusy = false;

  @override
  void initState() {
    super.initState();
    DevAuth.devModeEnabled.addListener(_handleDeveloperModeChanged);
    _developerMode = DevAuth.devModeEnabled.value;
    _recordDebug(
      'dock_open side=${widget.side.name} source=${widget.source} itemCount=${_faqCatalog.length}',
    );
    unawaited(_resolveDeveloperMode());
  }

  @override
  void dispose() {
    _recordDebug(
      'dock_closed side=${widget.side.name} source=${widget.source} queryActive=${_query.trim().isNotEmpty}',
    );
    DevAuth.devModeEnabled.removeListener(_handleDeveloperModeChanged);
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _handleDeveloperModeChanged() {
    if (!mounted) return;
    final enabled = DevAuth.devModeEnabled.value;
    if (_developerMode == enabled) return;
    setState(() => _developerMode = enabled);
    _recordDebug('developer_mode=$enabled');
  }

  Future<void> _resolveDeveloperMode() async {
    final enabled = await DevAuth.isDevModeEnabled();
    if (!mounted) return;
    if (_developerMode != enabled) {
      setState(() => _developerMode = enabled);
    }
    _recordDebug('developer_mode_resolved=$enabled');
  }

  void _recordDebug(String message) {
    final now = DateTime.now().toIso8601String();
    final line = '[FaqSideDock] $now $message';
    _debugLines.add(line);
    if (_debugLines.length > 240) {
      _debugLines.removeRange(0, _debugLines.length - 240);
    }
    debugPrint(line);
  }

  String get _debugPrintCode {
    return _debugLines.map((line) {
      final escaped = line
          .replaceAll('\\', '\\\\')
          .replaceAll('"', '\\"')
          .replaceAll('\r', '\\r')
          .replaceAll('\n', '\\n');
      return 'debugPrint("$escaped");';
    }).join('\n');
  }

  String _normalize(String value) {
    return value.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  bool _matches(_FaqEntry entry, String query) {
    final normalized = _normalize(query);
    if (normalized.isEmpty) return true;
    return _normalize(entry.searchable).contains(normalized);
  }

  List<_FaqEntry> get _filtered {
    return _faqCatalog
        .where((entry) => _matches(entry, _query))
        .toList(growable: false);
  }

  void _onSearchChanged(String value) {
    final nextFiltered = _faqCatalog
        .where((entry) => _matches(entry, value))
        .toList(growable: false);
    final currentExpanded = _expandedCode;
    setState(() {
      _query = value;
      if (currentExpanded != null &&
          !nextFiltered.any((entry) => entry.code == currentExpanded)) {
        _expandedCode = null;
      }
    });
    final queryLength = value.trim().length;
    final signature = '$queryLength:${nextFiltered.length}';
    if (_lastSearchSignature != signature) {
      _lastSearchSignature = signature;
      _recordDebug(
        'search_changed active=${queryLength > 0} queryLength=$queryLength resultCount=${nextFiltered.length}',
      );
    }
  }

  void _clearSearch() {
    if (_searchController.text.isEmpty) return;
    _searchController.clear();
    _onSearchChanged('');
    _searchFocusNode.requestFocus();
  }

  void _toggleEntry(_FaqEntry entry) {
    HapticFeedback.selectionClick();
    final opening = _expandedCode != entry.code;
    setState(() => _expandedCode = opening ? entry.code : null);
    _recordDebug(
      'faq_${opening ? 'expanded' : 'collapsed'} code=${entry.code}',
    );
  }

  Future<void> _requestClose() async {
    _searchFocusNode.unfocus();
    _recordDebug(
      'dock_close_requested side=${widget.side.name} source=${widget.source}',
    );
    if (!mounted) return;
    final externalClose = widget.onClose;
    if (externalClose != null) {
      externalClose();
      return;
    }
    await Navigator.of(context).maybePop();
  }

  Future<void> _showDeveloperStatus() async {
    if (!_developerMode || !mounted) return;
    _recordDebug(
      'developer_status_opened side=${widget.side.name} source=${widget.source}',
    );
    final code = _debugPrintCode;
    await StatusDialog.showSuccess(
      context,
      title: '오류 안내 개발자 상태',
      description:
          'side=${widget.side.name} · source=${widget.source} · logs=${_debugLines.length}',
      copyText: code,
      copyButtonLabel: 'debugPrint 코드 복사',
      useCommonUi: true,
      awaitManualClose: true,
    );
  }

  Future<void> _showContactFailure({
    required String reason,
  }) async {
    if (!mounted) return;
    await StatusDialog.showFailure(
      context,
      title: '문의 페이지를 열 수 없습니다.',
      description: reason,
      copyText: _developerMode ? _debugPrintCode : null,
      copyButtonLabel: 'debugPrint 코드 복사',
      useCommonUi: true,
      awaitManualClose: _developerMode,
    );
  }

  Future<void> _openContactForm() async {
    if (_contactBusy) return;
    setState(() => _contactBusy = true);
    _recordDebug('contact_requested source=${widget.source}');
    try {
      final uri = Uri.tryParse(_faqContactFormUrl);
      if (uri == null) {
        _recordDebug('contact_open_failure reason=invalid_uri');
        await _showContactFailure(reason: '문의 주소를 확인할 수 없습니다.');
        return;
      }
      final opened = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      _recordDebug('contact_open_result opened=$opened');
      if (!opened) {
        await _showContactFailure(reason: '외부 브라우저 실행에 실패했습니다.');
      }
    } catch (error, stackTrace) {
      final compactError =
          error.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
      _recordDebug('contact_open_failure error=$compactError');
      debugPrintStack(
        label: '[FaqSideDock] contact_open_failure',
        stackTrace: stackTrace,
      );
      await _showContactFailure(reason: '외부 브라우저 실행 중 오류가 발생했습니다.');
    } finally {
      if (mounted) {
        setState(() => _contactBusy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final filtered = _filtered;
    final queryActive = _query.trim().isNotEmpty;
    final subtitle = queryActive
        ? '${_faqCatalog.length}개 중 ${filtered.length}개 표시'
        : '${_faqCatalog.length}개 항목';

    return CommonSideDockFrame(
      showCloseTooltip: false,
      title: '오류 코드 / 문의',
      subtitle: subtitle,
      icon: Icons.help_center_rounded,
      onClose: () => unawaited(_requestClose()),
      headerAction: _developerMode
          ? Semantics(
              button: true,
              label: '오류 안내 개발자 상태',
              child: IconButton(
                onPressed: () => unawaited(_showDeveloperStatus()),
                icon: Icon(
                  Icons.bug_report_rounded,
                  color: tokens.accent,
                ),
              ),
            )
          : null,
      footer: OpsDockContextFooterTransition(
        child: OpsDockContextFooter(
          children: [
            Expanded(
              child: CommonButton(
                label: '문의하기',
                icon: Icons.contact_support_rounded,
                onPressed: _contactBusy ? null : _openContactForm,
                loading: _contactBusy,
                expand: true,
                variant: CommonButtonVariant.primary,
                haptic: CommonHaptic.light,
              ),
            ),
          ],
        ),
      ),
      child: ListView(
        padding: const EdgeInsets.only(bottom: 8),
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        children: [
          CommonSideDockSection(
            title: '검색',
            order: 1,
            child: _buildSearchSurface(context),
          ),
          const SizedBox(height: 12),
          CommonSideDockSection(
            title: '오류 코드',
            order: 2,
            child: OpsDockResultSwitcher(
              child: KeyedSubtree(
                key: ValueKey<String>(
                  'faq_${_normalize(_query)}_${filtered.length}',
                ),
                child: filtered.isEmpty
                    ? _buildEmptySurface(context)
                    : _buildFaqSurface(context, filtered),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchSurface(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    return OpsDockListSurface(
      child: Semantics(
        textField: true,
        label: '오류 코드 검색',
        child: TextField(
          controller: _searchController,
          focusNode: _searchFocusNode,
          onChanged: _onSearchChanged,
          textInputAction: TextInputAction.search,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: tokens.textPrimary,
                fontWeight: FontWeight.w600,
              ),
          decoration: InputDecoration(
            prefixIcon: Icon(
              Icons.search_rounded,
              color: tokens.iconSecondary,
            ),
            suffixIcon: _query.trim().isEmpty
                ? null
                : Semantics(
                    button: true,
                    label: '검색 지우기',
                    child: IconButton(
                      onPressed: _clearSearch,
                      icon: Icon(
                        Icons.close_rounded,
                        color: tokens.iconSecondary,
                      ),
                    ),
                  ),
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            filled: false,
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 14,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptySurface(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    return OpsDockListSurface(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 22),
        child: Row(
          children: [
            Icon(
              Icons.search_off_rounded,
              color: tokens.iconSecondary,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '검색 결과가 없습니다.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: tokens.textSecondary,
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFaqSurface(
    BuildContext context,
    List<_FaqEntry> entries,
  ) {
    final tokens = CommonUiTheme.of(context);
    return OpsDockListSurface(
      child: Column(
        children: [
          for (var index = 0; index < entries.length; index++) ...[
            _buildFaqRow(context, entries[index]),
            if (index != entries.length - 1)
              Divider(
                height: 1,
                thickness: 1,
                color: tokens.borderSubtle,
              ),
          ],
        ],
      ),
    );
  }

  Widget _buildFaqRow(
    BuildContext context,
    _FaqEntry entry,
  ) {
    final tokens = CommonUiTheme.of(context);
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final expanded = _expandedCode == entry.code;
    final duration =
        reduceMotion ? Duration.zero : CommonUiMotion.selection;

    return OpsDockSelectableRowSurface(
      selected: expanded,
      selectionColor: tokens.accent,
      selectedContainer: tokens.accentContainer,
      onTap: () => _toggleEntry(entry),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AnimatedContainer(
                duration: duration,
                curve: CommonUiMotion.standard,
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: expanded
                      ? tokens.accentContainer
                      : tokens.surfaceSelected,
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Icon(
                  Icons.question_answer_rounded,
                  size: 18,
                  color: expanded ? tokens.accent : tokens.iconSecondary,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.question,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: tokens.textPrimary,
                            fontWeight: FontWeight.w800,
                            height: 1.3,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'code. ${entry.code}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: tokens.textSecondary,
                            fontWeight: FontWeight.w600,
                            fontFamily: 'monospace',
                            height: 1.2,
                          ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              AnimatedRotation(
                turns: expanded ? .5 : 0,
                duration: duration,
                curve: CommonUiMotion.standard,
                child: Icon(
                  Icons.keyboard_arrow_down_rounded,
                  color: expanded ? tokens.accent : tokens.iconSecondary,
                ),
              ),
            ],
          ),
          AnimatedSwitcher(
            duration: duration,
            switchInCurve: CommonUiMotion.enter,
            switchOutCurve: CommonUiMotion.exit,
            transitionBuilder: (child, animation) {
              if (reduceMotion) return child;
              return FadeTransition(
                opacity: animation,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0, -.025),
                    end: Offset.zero,
                  ).animate(animation),
                  child: child,
                ),
              );
            },
            child: expanded
                ? Padding(
                    key: ValueKey<String>('answer_${entry.code}'),
                    padding: const EdgeInsets.fromLTRB(44, 12, 24, 2),
                    child: Text(
                      entry.answer,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: tokens.textSecondary,
                            height: 1.55,
                            fontWeight: FontWeight.w500,
                          ),
                    ),
                  )
                : SizedBox.shrink(
                    key: ValueKey<String>('collapsed_${entry.code}'),
                  ),
          ),
        ],
      ),
    );
  }
}
