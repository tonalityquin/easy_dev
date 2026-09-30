import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/utils/developer_operation_status_dialog.dart';
import '../../../design_system/common_ui/common_ui_overlays.dart';
import '../../../design_system/common_ui/common_ui_theme.dart';

Future<void> showUpdateDialog(
  BuildContext context, {
  List<UpdateEntry>? entries,
  String source = 'unknown',
}) async {
  final trace = await DeveloperOperationTrace.start(
    context: context,
    title: '업데이트 Dialog 상태',
    initialMessage: 'update_dialog_open_requested source=$source',
    useCommonUi: true,
    developerModeMessage: 'developer_mode=true debug_copy_enabled=true',
    standardModeMessage: 'developer_mode=false debug_copy_enabled=false',
    showDialogImmediately: false,
  );
  if (!context.mounted) return;
  final list = entries ?? UpdateDialog.defaultEntries;
  final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
  trace.log('presentation=center_dialog', progress: 0.12);
  trace.log('surface=list_surface', progress: 0.2);
  trace.log('entryCount=${list.length}', progress: 0.28);
  trace.log('latestVersion=${list.isEmpty ? 'none' : list.first.version}', progress: 0.32);
  trace.log('reduceMotion=$reduceMotion', progress: 0.36);
  trace.log('source=$source', progress: 0.44);
  await showCommonOverlayDialog<void>(
    context: context,
    barrierDismissible: true,
    useRootNavigator: true,
    barrierLabel: '업데이트',
    builder: (dialogContext) => UpdateDialog(
      entries: list,
      trace: trace,
      source: source,
    ),
  );
  trace.log('update_dialog_closed source=$source', progress: 0.96);
  await trace.succeed('update_dialog_session_complete source=$source');
}

class UpdateDialog extends StatefulWidget {
  const UpdateDialog({
    super.key,
    required this.trace,
    required this.source,
    this.entries,
  });

  final DeveloperOperationTrace trace;
  final String source;
  final List<UpdateEntry>? entries;

  static final List<UpdateEntry> defaultEntries = <UpdateEntry>[
    const UpdateEntry(
      version: 'v0.2.1',
      highlights: <String>[
        '로컬 저장소를 개편하여 전반적인 앱 메모리 사용량 개선',
        '전반적인 앱 UI 디자인 수정',
        '일부 차량 주차 구역 로직과 애니메이션 수정',
        '내방한 차량의 방문 목적 선택 관리 기능 추가',
        '본사 직원의 업무 대응 및 접근성 개선',
        '지사 직원의 업무 흐름 개선',
        '정기 주차 업무 흐름 개선',
        '권한 설정 화면 편의성 개선',
        '로그인 중 계정 탐색 로직 개편',
        '업무 지역 변경 시 지역 탐색 로직 및 조건 개편',
        '출퇴근 기록형의 출근 로직 개선',
        '본사 내부 로직 개선',
      ],
      footerNote: "각 계정 별 '내려받기' 기능 실행 시, 이메일이 삽입되지 않던 문제를 수정했습니다",
    ),
    const UpdateEntry(
      version: 'v0.1.4',
      highlights: <String>[
        'UI/UX 디자인 및 애니메이션 개선',
        '상기의 업데이트로 다크모드 지원은 일시적으로 제한됩니다.',
        '본사 대시보드 일부 기능 추가 및 개선',
        '일부 과도하게 메모리 사용을 유발하는 기능 개선',
        '일부 본사 관련 기능 사전 UI 업데이트',
        'OCR 인식 로직 일부 개선',
      ],
    ),
    const UpdateEntry(
      version: 'v0.1.3',
      highlights: <String>[
        '휴무, 휴게 상세 옵션 설정 기능 추가',
        '정기(월) 주차 관리 기능의 접근성 개선',
        '정기(월) 주차 관리의 상태 메모 시 한글로 작성이 되지 않던 버그 수정',
        '보조 페이지의 관리자 화면 개선',
        '대시보드 및 본사 페이지와 시트 UI 개선',
        '출차 완료 시트의 정산 탭에서 촬영자 정보와 날짜가 뜨지 않던 오류 수정',
        '차량 번호판 검색 시, 일부 기기에서 버튼과 핸드폰 홈 영역이 겹치던 이슈 수정',
      ],
    ),
    const UpdateEntry(
      version: 'v0.1.2',
      highlights: <String>[
        '업무 별 통계 시각화 기능 개선',
        '차량 현황 출력 화면 개선',
        '주차 도면으로 자동 전환 분기점 개선',
        '로그 저장 확장값을 json에서 csv로 변경',
        '본사 메모장 기능을 문서로 확대 개편',
        '출*퇴근 알림 등 로직 개선',
        '앱 첫 설치 후, 권한 설정 화면 다음 순서에 약관 관련 동의 화면 추가',
      ],
    ),
    const UpdateEntry(
      version: 'v0.1.1',
      highlights: <String>[
        '개인정보 보안용 스키마 추가',
        '과거 업무 차량 별 조회 기능 추가',
        '차종 및 제조사 데이터 삽입 기능 추가',
        '차량 상태가 영어로 출력되던 문제 수정',
        '무전기 기능 추가',
      ],
    ),
    const UpdateEntry(
      version: 'v0.1.0',
      highlights: <String>[
        '어플리케이션 릴리즈',
      ],
    ),
  ];

  @override
  State<UpdateDialog> createState() => _UpdateDialogState();
}

class UpdateEntry {
  const UpdateEntry({
    required this.version,
    required this.highlights,
    this.footerNote,
  });

  final String version;
  final List<String> highlights;
  final String? footerNote;
}

class _UpdateDialogState extends State<UpdateDialog> {
  int? _expandedIndex;

  List<UpdateEntry> get _entries => widget.entries ?? UpdateDialog.defaultEntries;

  @override
  void initState() {
    super.initState();
    _expandedIndex = _entries.isEmpty ? null : 0;
    widget.trace.log(
      'initial_expanded_index=$_expandedIndex initial_version=${_expandedIndex == null ? 'none' : _entries[_expandedIndex!].version}',
      progress: 0.48,
    );
  }

  @override
  void didUpdateWidget(covariant UpdateDialog oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_entries.isEmpty) {
      _expandedIndex = null;
      return;
    }
    if (_expandedIndex == null || _expandedIndex! >= _entries.length) {
      _expandedIndex = 0;
    }
  }

  Future<void> _toggle(int index) async {
    await HapticFeedback.selectionClick();
    final previousIndex = _expandedIndex;
    final previousVersion = previousIndex == null || previousIndex >= _entries.length
        ? 'none'
        : _entries[previousIndex].version;
    final nextIndex = previousIndex == index ? null : index;
    final nextVersion = nextIndex == null ? 'none' : _entries[nextIndex].version;
    setState(() {
      _expandedIndex = nextIndex;
    });
    widget.trace.log(
      'entry_toggle previousIndex=$previousIndex previousVersion=$previousVersion nextIndex=$nextIndex nextVersion=$nextVersion',
      progress: 0.56,
    );
  }

  Future<void> _showDeveloperStatus() async {
    final expandedVersion = _expandedIndex == null || _expandedIndex! >= _entries.length
        ? 'none'
        : _entries[_expandedIndex!].version;
    widget.trace.log(
      'developer_status_requested source=${widget.source} expandedIndex=$_expandedIndex expandedVersion=$expandedVersion',
      progress: 0.78,
    );
    await widget.trace.showSnapshotStatusDialog(
      context,
      title: '업데이트 Dialog 상태',
      description:
          'source=${widget.source} entries=${_entries.length} expandedIndex=$_expandedIndex expandedVersion=$expandedVersion',
    );
  }

  void _close() {
    widget.trace.log(
      'close_button_pressed source=${widget.source} expandedIndex=$_expandedIndex',
      progress: 0.9,
    );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.maybeOf(context);
    final reduceMotion = media?.disableAnimations ?? false;
    final tokens = CommonUiTheme.of(context);
    final text = Theme.of(context).textTheme;
    final maxHeight = (media?.size.height ?? 720) * 0.82;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 560,
          maxHeight: maxHeight,
        ),
        child: Material(
          color: tokens.surfaceRaised,
          elevation: 0,
          shadowColor: tokens.shadow,
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(CommonUiShapes.dialog),
            side: BorderSide(color: tokens.borderSubtle),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 14, 10, 12),
                child: Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: tokens.accentContainer,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        Icons.new_releases_rounded,
                        size: 21,
                        color: tokens.onAccentContainer,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        '업데이트',
                        style: text.titleLarge?.copyWith(
                          color: tokens.textPrimary,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    if (widget.trace.developerMode)
                      Semantics(
                        button: true,
                        label: '업데이트 Dialog 상태',
                        child: IconButton(
                          onPressed: _showDeveloperStatus,
                          icon: Icon(
                            Icons.bug_report_rounded,
                            color: tokens.warning,
                          ),
                        ),
                      ),
                    Semantics(
                      button: true,
                      label: '닫기',
                      child: IconButton(
                        onPressed: _close,
                        icon: Icon(
                          Icons.close_rounded,
                          color: tokens.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Divider(height: 1, color: tokens.borderSubtle),
              Flexible(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: _UpdateListSurface(
                    entries: _entries,
                    expandedIndex: _expandedIndex,
                    reduceMotion: reduceMotion,
                    onToggle: _toggle,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _UpdateListSurface extends StatelessWidget {
  const _UpdateListSurface({
    required this.entries,
    required this.expandedIndex,
    required this.reduceMotion,
    required this.onToggle,
  });

  final List<UpdateEntry> entries;
  final int? expandedIndex;
  final bool reduceMotion;
  final Future<void> Function(int index) onToggle;

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    return Material(
      color: tokens.surface,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: tokens.borderSubtle),
      ),
      child: ListView.builder(
        shrinkWrap: true,
        itemCount: entries.length,
        itemBuilder: (context, index) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _UpdateListRow(
                entry: entries[index],
                expanded: expandedIndex == index,
                latest: index == 0,
                reduceMotion: reduceMotion,
                onTap: () => onToggle(index),
              ),
              if (index < entries.length - 1)
                Divider(
                  height: 1,
                  indent: 16,
                  endIndent: 16,
                  color: tokens.borderSubtle,
                ),
            ],
          );
        },
      ),
    );
  }
}

class _UpdateListRow extends StatelessWidget {
  const _UpdateListRow({
    required this.entry,
    required this.expanded,
    required this.latest,
    required this.reduceMotion,
    required this.onTap,
  });

  final UpdateEntry entry;
  final bool expanded;
  final bool latest;
  final bool reduceMotion;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final text = Theme.of(context).textTheme;
    final duration = reduceMotion ? Duration.zero : const Duration(milliseconds: 190);

    return AnimatedContainer(
      duration: duration,
      curve: Curves.easeOutCubic,
      color: expanded ? tokens.surfaceSelected : tokens.surface,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Semantics(
            button: true,
            label: entry.version,
            child: InkWell(
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 13, 12, 13),
                child: Row(
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          Text(
                            entry.version,
                            style: text.titleSmall?.copyWith(
                              color: tokens.textPrimary,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          if (latest) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: tokens.accentContainer,
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                '최신',
                                style: text.labelSmall?.copyWith(
                                  color: tokens.onAccentContainer,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    AnimatedRotation(
                      duration: duration,
                      curve: Curves.easeOutCubic,
                      turns: expanded ? 0.5 : 0,
                      child: Icon(
                        Icons.keyboard_arrow_down_rounded,
                        color: tokens.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          AnimatedSize(
            duration: duration,
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: AnimatedSwitcher(
              duration: duration,
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (child, animation) {
                final offset = Tween<Offset>(
                  begin: const Offset(0, -0.018),
                  end: Offset.zero,
                ).animate(animation);
                return FadeTransition(
                  opacity: animation,
                  child: SlideTransition(
                    position: offset,
                    child: child,
                  ),
                );
              },
              child: expanded
                  ? Padding(
                      key: ValueKey<String>('${entry.version}_expanded'),
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                      child: _UpdateEntryDetails(
                        entry: entry,
                        tokens: tokens,
                        text: text,
                      ),
                    )
                  : SizedBox.shrink(
                      key: ValueKey<String>('${entry.version}_collapsed'),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _UpdateEntryDetails extends StatelessWidget {
  const _UpdateEntryDetails({
    required this.entry,
    required this.tokens,
    required this.text,
  });

  final UpdateEntry entry;
  final CommonUiTokens tokens;
  final TextTheme text;

  @override
  Widget build(BuildContext context) {
    final footerNote = entry.footerNote?.trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < entry.highlights.length; i++)
          Padding(
            padding: EdgeInsets.only(
              top: i == 0 ? 2 : 8,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 7),
                  child: Container(
                    width: 5,
                    height: 5,
                    decoration: BoxDecoration(
                      color: tokens.accent,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    entry.highlights[i],
                    style: text.bodyMedium?.copyWith(
                      color: tokens.textPrimary,
                      height: 1.45,
                    ),
                  ),
                ),
              ],
            ),
          ),
        if (footerNote != null && footerNote.isNotEmpty) ...[
          const SizedBox(height: 16),
          Divider(
            height: 1,
            color: tokens.borderSubtle,
          ),
          const SizedBox(height: 12),
          Text(
            footerNote,
            style: text.bodyMedium?.copyWith(
              color: tokens.textPrimary,
              height: 1.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ],
    );
  }
}
