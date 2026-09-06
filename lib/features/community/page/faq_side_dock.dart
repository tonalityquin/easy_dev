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
    code: "common_user_00",
    question: "로그인이 안되고 있어요.",
    answer: "진입한 창이 부여받은 계정에 호환이 되나요?\n\n각 로그인 창마다 다른 검증 로직을 가지고 있습니다. 관리자로부터 제공 받은 계정이 호환되는 창을 다시 확인해주세요.",
  ),
  _FaqEntry(
    code: "common_user_01",
    question: "계정 비밀번호를 분실했어요.",
    answer: "비밀번호는 계정 추가 시 랜덤 함수로 생성됩니다.\n\n관리자로부터 개발사에 직접 문의하세요. 꼭 개인적으로 비밀번호를 저장하시기 바랍니다.",
  ),
  _FaqEntry(
    code: "common_user_02",
    question: "로그아웃을 하고 앱을 실행했어요. 그런데 404가 떠요.",
    answer: "정상적인 앱 종료가 이루어지지 않았습니다.\n\n로그아웃을 하고 꼭 탭에서 앱을 완전히 종료해주세요.",
  ),
  _FaqEntry(
    code: "service_user_commute",
    question: "출근 보고 버튼을 눌러도 반응이 없어요.",
    answer: "문제는 세 가지 중에 있습니다.\n\n1.오픈 카카오톡 채팅방이 아니다.\n2.채팅방이 삭제되었거나 추방당한 적이 있다.\n3.URL을 잘못 복사하여 붙여넣었다.\n\n위의 내용을 점검 후 다시 실행하시면 됩니다.",
  ),
  _FaqEntry(
    code: "service_user_humanResource_00",
    question: "지역과 사용자를 골랐습니다. 그런데 데이터가 없어요.",
    answer: "문제는 세 가지 중에 있습니다.\n\n1.해당 계정으로 저장된 로그가 없다.\n2.링크를 잘못 삽입했다.\n3.계정 권한을 부여하지 않았다.\n\n위의 내용을 점검 후 다시 실행하시면 됩니다.",
  ),
  _FaqEntry(
    code: "service_userAccounts_HeadQuarter_00",
    question: "회사 일정 달력을 열었어요. 그런데 일정을 불러오지 못하고 있어요.",
    answer: "문제는 세 가지 중에 있습니다.\n\n1.링크를 잘못 삽입했다.\n2.계정 권한을 부여하지 않았다.\n3.해당 월에 생성한 할 일이 없다.\n\n위의 내용을 점검 후 다시 실행하시면 됩니다.",
  ),
  _FaqEntry(
    code: "service_userAccounts_HeadQuarter_01",
    question: "완료 탭을 열었어요. 그런데 완료된 일을 불러오지 못하고 있어요.",
    answer: "문제는 두 가지 중에 있습니다.\n1.계정 권한을 부여하지 않았다.\n2.완료된 할 일이 없다.\n\n기본적으로 markdown 문법을 따르고 있습니다.\n\n위의 내용을 점검 후 다시 실행하시면 됩니다.",
  ),
  _FaqEntry(
    code: "service_area_HeadQuarter_02",
    question: "완료된 할 일을 엑셀에 저장하지 못 했습니다. 그런데 실수로 먼저 지웠는데 복구하고 싶어요.",
    answer: "지워진 할 일은 복구할 수 없습니다.\n\n반드시 사전에 저장 후 삭제해야 합니다.",
  ),
  _FaqEntry(
    code: "service_area_plate_tts",
    question: "번호판을 생성할 때와 출차 요청했어요. 그런데 소리가 안들려요.",
    answer: "본 앱은 기본적으로 Google TTS를 사용 중입니다.\n\n1.설정->일반->글자 읽어주기->기본 엔진\n\"Google 음성 인식 및 합성\"을 선택해주세요.\n2.플레이스토어에 가서 최신 업데이트 버전을 확인하세요.",
  ),
  _FaqEntry(
    code: "service_area_userManagement_00",
    question: "계정의 근무지를 변경하고 싶어요.",
    answer: "동일 계정으로 근무지를 변경할 수 없습니다.\n\n1.이전 근무자의 계정을 삭제하세요.\n2.변경된 지역에서 계정을 새롭게 생성하세요.",
  ),
  _FaqEntry(
    code: "service_area_page_00",
    question: "홈 화면의 구역 내 잔여 데이터를 보고 싶어요.",
    answer: "구역 내 잔여 데이터 열람은 제한이 있습니다.\n\n1. 홈 버튼을 누른 후, 구역 현황 화면에 진입 하세요.\n2. 각 지역마다 5대의 기본값을 설정하고 있습니다.\n3. 현재 4대의 데이터가 있는 경우 열람이 가능합니다.\n4. 현재 5대의 데이터가 있는 경우 열람이 가능합니다.\n5. 현재 6대의 데이터가 있는 경우 열람이 불가능합니다.\n\n해당 기능의 범위를 늘리고자 하는 경우, 개인 문의 부탁드립니다.",
  ),
  _FaqEntry(
    code: "service_area_page_01",
    question: "입차 요청과 출차 요청 탭을 눌렀어요. 아무 반응이 없어요.",
    answer: "데이터가 없다는 뜻입니다.\n\n입차 요청 혹은 출차 요청에 데이터가 없는 경우에는 해당 화면을 눌러도 진입이 되지 않습니다.",
  ),
  _FaqEntry(
    code: "service_area_page_02",
    question: "입차 요청과 출차 요청 탭을 눌렀어요. 아무 반응이 없어요.",
    answer: "데이터가 없다는 뜻입니다.\n\n입차 요청 혹은 출차 요청에 데이터가 없는 경우에는 해당 화면을 눌러도 진입이 되지 않습니다.",
  ),
  _FaqEntry(
    code: "service_area_page_03",
    question: "번호판 검색이 안되고 있어요.",
    answer: "어느 화면에서 번호판을 검색했나요?\n\n1. 모든 상태를 검색할 수 있는 경우\n- 입차 요청\n- 출차 요청\n\n2. 입차 완료만 검색할 수 있는 경우\n- 입차 완료\n\n3. 출차 완료만 검색할 수 있는 경우\n- 출차 완료(정산 탭)\n\n해당 화면을 눌러도 진입이 되지 않습니다.",
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
      barrierLabel: 'FAQ / 문의',
      useRootNavigator: true,
      maxWidth: 460,
      widthFactor: .94,
      barrierDismissible: true,
    );
  }
  return showCommonRightSideDock<T>(
    context: context,
    builder: builder,
    barrierLabel: 'FAQ / 문의',
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
  });

  final CommonSideDockSide side;
  final String source;

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
      title: 'FAQ 개발자 상태',
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
      title: 'FAQ / 문의',
      subtitle: subtitle,
      icon: Icons.help_center_rounded,
      onClose: () => unawaited(_requestClose()),
      headerAction: _developerMode
          ? Semantics(
              button: true,
              label: 'FAQ 개발자 상태',
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
            title: '질문',
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
        label: 'FAQ 검색',
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
