import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

// 재사용 UI 컴포넌트(기존 상대 경로 유지)
import '../../../models/plate_model.dart';
import '../../../repositories/plate_repo_services/firestore_plate_repository.dart';
import '../../../utils/snackbar_helper.dart';
import '../widgets/keypad/tablet_animated_keypad.dart';
import '../sections/tablet_plate_number_display_section.dart';
import '../sections/tablet_plate_search_header_section.dart';
import '../sections/tablet_plate_search_result_section.dart';
import '../widgets/tablet_page_status_bottom_sheet.dart';
import '../states/tablet_pad_mode_state.dart';

/// 결과 다이얼로그 종료 사유(명시적으로 구분)
enum _ResultsDialogCloseReason {
  reset, // 초기화 버튼으로 닫힘
  selected, // 결과 선택으로 닫힘
}

/// 우측(또는 단일) 패널: 키패드 + 4자리 검색 → 결과 다이얼로그 + 상태 바텀시트.
///
/// 모드별 레이아웃:
/// - big   : 상단 카드(헤더/입력/가이드) + 하단 키패드(45% 제한)
/// - small : 키패드만(패널 높이 100%)
/// - mobile: 단일 화면(상단 입력 표시 + 하단 키패드가 남은 영역을 채움)
class RightPaneSearchPanel extends StatefulWidget {
  final String area;

  const RightPaneSearchPanel({
    super.key,
    required this.area,
  });

  @override
  State<RightPaneSearchPanel> createState() => _RightPaneSearchPanelState();
}

class _RightPaneSearchPanelState extends State<RightPaneSearchPanel>
    with SingleTickerProviderStateMixin {
  final TextEditingController _controller = TextEditingController();

  bool _isLoading = false;
  bool _navigating = false; // 빠른 중복 탭 방지

  late final AnimationController _keypadController;
  late final Animation<Offset> _slideAnimation;
  late final Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _keypadController =
        AnimationController(vsync: this, duration: const Duration(milliseconds: 500));
    _slideAnimation = Tween<Offset>(begin: const Offset(0, 0.2), end: Offset.zero)
        .animate(CurvedAnimation(parent: _keypadController, curve: Curves.easeOut));
    _fadeAnimation = CurvedAnimation(parent: _keypadController, curve: Curves.easeIn);
    _keypadController.forward();
  }

  @override
  void didUpdateWidget(covariant RightPaneSearchPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.area != widget.area) {
      _resetToInitial();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _keypadController.dispose();
    super.dispose();
  }

  bool _isValidPlate(String value) => RegExp(r'^\d{4}$').hasMatch(value); // 숫자 4자리만 유효

  Color _tintOnSurface(ColorScheme cs, {required double opacity}) {
    // primary를 surface 위에 아주 얇게 얹어서 브랜드 톤 “힌트”만 주는 용도
    return Color.alphaBlend(cs.primary.withOpacity(opacity), cs.surface);
  }

  Future<void> _refreshSearchResults() async {
    if (!mounted || _isLoading) return;
    setState(() => _isLoading = true);

    try {
      final repository = FirestorePlateRepository();
      final input = _controller.text;

      final results = await repository.fourDigitForTabletQuery(
        plateFourDigit: input,
        area: widget.area,
      );

      if (!mounted) return;
      setState(() => _isLoading = false);

      await _showResultsDialog(results);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      showFailedSnackbar(context, '검색 중 오류가 발생했습니다: $e');
    }
  }

  void _resetToInitial() {
    setState(() {
      _controller.clear();
      _isLoading = false;
    });
    _keypadController.forward(from: 0);
    _navigating = false;
  }

  void _onKeypadComplete() {
    final input = _controller.text;
    if (_isValidPlate(input) && !_navigating) {
      _refreshSearchResults();
    }
  }

  /// ✅ 요구사항 반영 핵심:
  /// - 다이얼로그의 "닫기"를 "초기화"로 변경
  /// - 초기화 버튼을 누르면 다이얼로그가 닫힌 뒤 상태 초기화
  /// - 바깥 탭/뒤로가기(= barrier dismiss)로 닫히는 경우에도 상태 초기화
  ///
  /// ✅ UI 개선 핵심:
  /// - 다이얼로그 폭을 화면 기반으로 반응형 확장(기존 680 하드캡 제거)
  /// - 결과 리스트는 SingleChildScrollView 제거 → ListView 단일 스크롤로 정리
  /// - 카드 섹션의 “좁음 체감”을 줄이도록 패딩/폭/레이아웃 최적화
  Future<void> _showResultsDialog(List<PlateModel> results) async {
    final rootContext = Navigator.of(context, rootNavigator: true).context;

    final closeReason = await showDialog<_ResultsDialogCloseReason>(
      context: context,
      barrierDismissible: true, // 바깥 탭으로 닫기 허용(요구사항: 이 경우도 초기화)
      builder: (dialogCtx) {
        final cs = Theme.of(dialogCtx).colorScheme;
        final text = Theme.of(dialogCtx).textTheme;
        final size = MediaQuery.of(dialogCtx).size;

        void requestResetAndClose() {
          // pop은 먼저 실행되고, 초기화는 showDialog가 완전히 닫힌 뒤에 아래에서 처리
          Navigator.of(dialogCtx).pop(_ResultsDialogCloseReason.reset);
        }

        // ✅ 반응형 폭: 화면 폭(인셋 고려)을 최대한 사용하되 과도하게 넓지 않게 상한 부여
        // - (size.width - 32): Dialog insetPadding(all:16) 기준 실사용 가능 폭
        // - 상한 980: 태블릿에서 카드가 답답하지 않게 넓히되 “모달” 느낌은 유지
        final maxDialogWidth = (size.width - 32).clamp(0.0, 980.0).toDouble();

        final headerIconBg = _tintOnSurface(
          cs,
          opacity: cs.brightness == Brightness.dark ? 0.18 : 0.10,
        );

        final inputLine = '입력 번호: ${_controller.text}   /   구역: ${widget.area.isEmpty ? "-" : widget.area}';
        final countLabel = results.isEmpty ? '0건' : '${results.length}건';

        return Dialog(
          insetPadding: const EdgeInsets.all(16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: maxDialogWidth,
              maxHeight: size.height * 0.86,
            ),
            child: Padding(
              // ✅ 바깥 패딩을 과하지 않게 조정(폭 체감 개선)
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Header
                  Row(
                    children: [
                      Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: headerIconBg,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: cs.outline.withOpacity(.10)),
                        ),
                        child: Icon(Icons.search, color: cs.primary, size: 18),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          '검색 결과 · $countLabel',
                          style: (text.titleMedium ?? const TextStyle()).copyWith(
                            fontWeight: FontWeight.w900,
                            color: cs.onSurface,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      // ✅ 상단 X(닫기) 대신 "초기화" 액션
                      IconButton(
                        tooltip: '초기화',
                        icon: const Icon(Icons.restart_alt),
                        onPressed: requestResetAndClose,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  // 입력 정보(상단 안내 바)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: _tintOnSurface(
                        cs,
                        opacity: cs.brightness == Brightness.dark ? 0.12 : 0.06,
                      ),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: cs.outline.withOpacity(.14)),
                    ),
                    child: Text(
                      inputLine,
                      style: (text.bodySmall ?? const TextStyle()).copyWith(
                        color: cs.onSurfaceVariant,
                        fontWeight: FontWeight.w700,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),

                  const SizedBox(height: 12),

                  Expanded(
                    child: results.isEmpty
                        ? const _InlineEmpty(text: '검색 결과가 없습니다.')
                        : Container(
                      decoration: BoxDecoration(
                        color: cs.surface,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: cs.outline.withOpacity(.12)),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: Scrollbar(
                          child: TabletPlateSearchResultSection(
                            results: results,
                            onSelect: (selected) async {
                              if (_navigating) return;
                              _navigating = true;

                              // ✅ 선택으로 닫힘 사유를 명시
                              Navigator.of(dialogCtx).pop(_ResultsDialogCloseReason.selected);

                              final didConfirm = await showTabletPageStatusBottomSheet(
                                context: rootContext,
                                plate: selected,
                                onRequestEntry: () async {},
                                onDelete: () {},
                              );

                              if (!mounted) return;

                              if (didConfirm != null) {
                                // 확인/취소 등 명시 결과면 초기화(기존 정책 유지)
                                _resetToInitial();
                              } else {
                                // 바텀시트가 null(dismiss)로 닫히면 다시 선택 가능
                                _navigating = false;
                              }
                            },
                          ),
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.centerRight,
                    // ✅ 하단 버튼도 "초기화"
                    child: TextButton(
                      onPressed: requestResetAndClose,
                      child: Text(
                        '초기화',
                        style: (text.labelLarge ?? const TextStyle()).copyWith(
                          color: cs.primary,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );

    if (!mounted) return;

    // ✅ 바깥 탭/뒤로가기 등으로 dismiss되면 closeReason == null
    // ✅ 초기화 버튼으로 닫히면 closeReason == reset
    // 두 경우 모두: "다이얼로그가 닫힌 뒤" 상태 초기화
    if (closeReason == null || closeReason == _ResultsDialogCloseReason.reset) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _resetToInitial();
      });
      return;
    }

    // selected로 닫힌 경우:
    // - onSelect에서 BottomSheet 흐름을 계속 진행
    // - 초기화는 BottomSheet 결과에 따라 기존 정책대로 처리
  }

  Widget _panelCard({required Widget child}) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: cs.outline.withOpacity(.12)),
        boxShadow: [
          BoxShadow(
            color: cs.shadow.withOpacity(.04),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: child,
    );
  }

  Widget _buildHeaderCard({required EdgeInsets padding}) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Padding(
      padding: padding,
      child: _panelCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const TabletPlateSearchHeaderSection(),
            const SizedBox(height: 16),
            TabletPlateNumberDisplaySection(
              controller: _controller,
              isValidPlate: _isValidPlate,
            ),
            const SizedBox(height: 16),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              child: _isLoading
                  ? ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(
                  minHeight: 3,
                  valueColor: AlwaysStoppedAnimation<Color>(cs.primary),
                  backgroundColor: cs.outlineVariant.withOpacity(.35),
                ),
              )
                  : const SizedBox.shrink(),
            ),
            const SizedBox(height: 12),
            Text(
              '키패드로 4자리 입력 후 자동 검색됩니다.',
              style: (text.bodySmall ?? const TextStyle()).copyWith(
                color: cs.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _keypadWrapper({
    required Widget child,
    required bool fullHeight,
    required bool useTopDivider,
  }) {
    final cs = Theme.of(context).colorScheme;

    if (fullHeight) {
      return Container(
        color: cs.surface,
        child: child,
      );
    }

    // big 모드에서 키패드 영역은 “바탕은 표면 + 살짝 primary 톤”
    final bg = _tintOnSurface(cs, opacity: cs.brightness == Brightness.dark ? 0.08 : 0.03);

    return Container(
      decoration: BoxDecoration(
        color: bg,
        border: useTopDivider
            ? Border(top: BorderSide(color: cs.outline.withOpacity(.10)))
            : null,
      ),
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    // pad 모드에 따라 우측/단일 패널 내부 레이아웃 분기
    final isSmallPad = context.select<TabletPadModeState, bool>((s) => s.isSmall);
    final padMode = context.select<TabletPadModeState, PadMode>((s) => s.mode);
    final isMobile = padMode == PadMode.mobile;

    final cs = Theme.of(context).colorScheme;

    // ─────────────────────────────────────────────────────────────────────
    // ✅ mobile: 단일 화면(상단 입력 표시 + 하단 키패드)
    // ─────────────────────────────────────────────────────────────────────
    if (isMobile) {
      return Material(
        color: cs.surface,
        child: SafeArea(
          top: false,
          child: Column(
            children: [
              _buildHeaderCard(padding: const EdgeInsets.fromLTRB(16, 16, 16, 10)),
              Expanded(
                child: SafeArea(
                  top: false,
                  bottom: true,
                  child: _keypadWrapper(
                    fullHeight: true,
                    useTopDivider: false,
                    child: TabletAnimatedKeypad(
                      slideAnimation: _slideAnimation,
                      fadeAnimation: _fadeAnimation,
                      controller: _controller,
                      maxLength: 4,
                      enableDigitModeSwitch: false,
                      onComplete: _onKeypadComplete,
                      onReset: _resetToInitial,
                      fullHeight: true,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    // ─────────────────────────────────────────────────────────────────────
    // 기존: small/big 레이아웃 (색만 브랜드 테마로 치환)
    // ─────────────────────────────────────────────────────────────────────
    final text = Theme.of(context).textTheme;

    return Material(
      color: cs.surface,
      child: SafeArea(
        top: false,
        child: Column(
          children: [
            // big pad: 헤더/표시/로딩 노출
            if (!isSmallPad)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: _panelCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const TabletPlateSearchHeaderSection(),
                        const SizedBox(height: 16),
                        TabletPlateNumberDisplaySection(
                          controller: _controller,
                          isValidPlate: _isValidPlate,
                        ),
                        const SizedBox(height: 16),

                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 180),
                          child: _isLoading
                              ? ClipRRect(
                            borderRadius: BorderRadius.circular(999),
                            child: LinearProgressIndicator(
                              minHeight: 3,
                              valueColor: AlwaysStoppedAnimation<Color>(cs.primary),
                              backgroundColor: cs.outlineVariant.withOpacity(.35),
                            ),
                          )
                              : const SizedBox.shrink(),
                        ),

                        const Spacer(),
                        Text(
                          '키패드로 4자리 입력 후 자동 검색됩니다.',
                          style: (text.bodySmall ?? const TextStyle()).copyWith(
                            color: cs.onSurfaceVariant,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

            // 👇 키패드 영역 (오른쪽 패널 내부)
            if (isSmallPad)
              Expanded(
                child: SafeArea(
                  top: false,
                  bottom: true,
                  child: _keypadWrapper(
                    fullHeight: true,
                    useTopDivider: false,
                    child: TabletAnimatedKeypad(
                      slideAnimation: _slideAnimation,
                      fadeAnimation: _fadeAnimation,
                      controller: _controller,
                      maxLength: 4,
                      enableDigitModeSwitch: false,
                      onComplete: _onKeypadComplete,
                      onReset: _resetToInitial,
                      fullHeight: true, // small pad: 우측 패널 높이를 100% 사용
                    ),
                  ),
                ),
              )
            else
              SafeArea(
                top: false,
                bottom: true,
                child: _keypadWrapper(
                  fullHeight: false,
                  useTopDivider: true,
                  child: TabletAnimatedKeypad(
                    slideAnimation: _slideAnimation,
                    fadeAnimation: _fadeAnimation,
                    controller: _controller,
                    maxLength: 4,
                    enableDigitModeSwitch: false, // 마지막 행: ['처음','0','검색']
                    onComplete: _onKeypadComplete,
                    onReset: _resetToInitial,
                    // fullHeight 기본 false → 높이 45% 제한(기존 유지)
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// 공통: 빈 상태(인라인) - 중립 안내
class _InlineEmpty extends StatelessWidget {
  final String text;

  const _InlineEmpty({required this.text});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.inbox_outlined, size: 40, color: cs.outline),
            const SizedBox(height: 10),
            Text(
              text,
              style: (t.bodyMedium ?? const TextStyle()).copyWith(
                color: cs.onSurfaceVariant,
                fontWeight: FontWeight.w700,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
