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

/// 이전 Deep Blue 컨셉과 동일한 팔레트
class _Palette {
  static const base = Color(0xFF0D47A1);
  static const dark = Color(0xFF09367D);
}

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
  Future<void> _showResultsDialog(List<PlateModel> results) async {
    final rootContext = Navigator.of(context, rootNavigator: true).context;

    final closeReason = await showDialog<_ResultsDialogCloseReason>(
      context: context,
      barrierDismissible: true, // 바깥 탭으로 닫기 허용(요구사항: 이 경우도 초기화)
      builder: (dialogCtx) {
        final cs = Theme.of(dialogCtx).colorScheme;
        final text = Theme.of(dialogCtx).textTheme;

        void requestResetAndClose() {
          // pop은 먼저 실행되고, 초기화는 showDialog가 완전히 닫힌 뒤에 아래에서 처리
          Navigator.of(dialogCtx).pop(_ResultsDialogCloseReason.reset);
        }

        return Dialog(
          insetPadding: const EdgeInsets.all(16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 680,
              maxHeight: MediaQuery.of(dialogCtx).size.height * 0.82,
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 12),
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
                          color: _Palette.base.withOpacity(.08),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(Icons.search, color: _Palette.base, size: 18),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          '검색 결과',
                          style: text.titleMedium?.copyWith(
                            fontWeight: FontWeight.w900,
                            color: _Palette.dark,
                          ),
                        ),
                      ),
                      // ✅ 상단 X(닫기) 대신 "초기화" 액션으로 변경
                      IconButton(
                        tooltip: '초기화',
                        icon: const Icon(Icons.restart_alt),
                        onPressed: requestResetAndClose,
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: _Palette.base.withOpacity(.04),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: cs.outline.withOpacity(.14)),
                    ),
                    child: Text(
                      '입력 번호: ${_controller.text}   /   구역: ${widget.area.isEmpty ? "-" : widget.area}',
                      style: text.bodySmall?.copyWith(
                        color: cs.outline,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  Expanded(
                    child: results.isEmpty
                        ? const _InlineEmpty(text: '검색 결과가 없습니다.')
                        : Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: cs.outline.withOpacity(.12)),
                      ),
                      child: Scrollbar(
                        child: SingleChildScrollView(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
                            child: TabletPlateSearchResultSection(
                              results: results,
                              onSelect: (selected) async {
                                if (_navigating) return;
                                _navigating = true;

                                // ✅ 선택으로 닫힘 사유를 명시
                                Navigator.of(dialogCtx)
                                    .pop(_ResultsDialogCloseReason.selected);

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
                  ),

                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.centerRight,
                    // ✅ 하단 "닫기" 버튼도 "초기화"로 변경
                    child: TextButton(
                      onPressed: requestResetAndClose,
                      child: Text(
                        '초기화',
                        style: text.labelLarge?.copyWith(
                          color: _Palette.base,
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
      // post-frame로 한 번 더 보수적으로 보장(닫힌 뒤 초기화)
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
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: cs.outline.withOpacity(.12)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(.04),
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
                child: const LinearProgressIndicator(minHeight: 3),
              )
                  : const SizedBox.shrink(),
            ),
            const SizedBox(height: 12),
            Text(
              '키패드로 4자리 입력 후 자동 검색됩니다.',
              style: text.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.outline,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // pad 모드에 따라 우측/단일 패널 내부 레이아웃 분기
    final isSmallPad =
    context.select<TabletPadModeState, bool>((s) => s.isSmall);
    final padMode =
    context.select<TabletPadModeState, PadMode>((s) => s.mode);
    final isMobile = padMode == PadMode.mobile;

    // ─────────────────────────────────────────────────────────────────────
    // ✅ mobile: 단일 화면(상단 입력 표시 + 하단 키패드)
    // - 좌/우 패널 분할이 없으므로, 상단 카드 + 하단 키패드(남은 공간 채움)로 고정
    // - 검색/출차 요청 로직은 기존과 동일(컨트롤러/콜백 재사용)
    // ─────────────────────────────────────────────────────────────────────
    if (isMobile) {
      return Material(
        color: Colors.white,
        child: SafeArea(
          top: false,
          child: Column(
            children: [
              _buildHeaderCard(padding: const EdgeInsets.fromLTRB(16, 16, 16, 10)),
              Expanded(
                child: SafeArea(
                  top: false,
                  bottom: true,
                  child: Container(
                    color: Colors.white,
                    child: TabletAnimatedKeypad(
                      slideAnimation: _slideAnimation,
                      fadeAnimation: _fadeAnimation,
                      controller: _controller,
                      maxLength: 4,
                      enableDigitModeSwitch: false,
                      onComplete: _onKeypadComplete,
                      onReset: _resetToInitial,
                      // mobile에서는 하단 영역(남은 공간)을 키패드가 충분히 채우도록 fullHeight 사용
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
    // 기존: small/big 레이아웃
    // ─────────────────────────────────────────────────────────────────────
    final text = Theme.of(context).textTheme;

    return Material(
      color: Colors.white,
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
                            child: const LinearProgressIndicator(minHeight: 3),
                          )
                              : const SizedBox.shrink(),
                        ),

                        const Spacer(),
                        Text(
                          '키패드로 4자리 입력 후 자동 검색됩니다.',
                          style: text.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.outline,
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
                  child: Container(
                    color: Colors.white,
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
                child: Container(
                  decoration: BoxDecoration(
                    color: _Palette.base.withOpacity(.02),
                    border: Border(
                      top: BorderSide(
                        color: Theme.of(context).colorScheme.outline.withOpacity(.10),
                      ),
                    ),
                  ),
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
              style: t.bodyMedium?.copyWith(
                color: cs.outline,
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
