// lib/screens/tablet_pages/tablet_right_panel.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

// 재사용 UI 컴포넌트(기존 상대 경로 유지)
import '../../../models/plate_model.dart';
import '../../../repositories/plate/firestore_plate_repository.dart';
import '../../../utils/snackbar_helper.dart';
import '../widgets/keypad/animated_keypad.dart';
import '../sections/plate_number_display_section.dart';
import '../sections/plate_search_header_section.dart';
import '../sections/plate_search_result_section.dart';
import '../widgets/tablet_page_status_bottom_sheet.dart';
import '../states/pad_mode_state.dart';

/// 우측 패널: 키패드 + 4자리 검색 → 결과 다이얼로그 + 상태 바텀시트.
/// 키패드는 항상 **오른쪽 패널 내부**에서만 렌더링됩니다.
class RightPaneSearchPanel extends StatefulWidget {
  final String area;

  const RightPaneSearchPanel({
    super.key,
    required this.area,
  });

  @override
  State<RightPaneSearchPanel> createState() => _RightPaneSearchPanelState();
}

class _RightPaneSearchPanelState extends State<RightPaneSearchPanel> with SingleTickerProviderStateMixin {
  final TextEditingController _controller = TextEditingController();

  bool _isLoading = false;
  bool _navigating = false; // 빠른 중복 탭 방지

  late final AnimationController _keypadController;
  late final Animation<Offset> _slideAnimation;
  late final Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _keypadController = AnimationController(vsync: this, duration: const Duration(milliseconds: 500));
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

  Future<void> _showResultsDialog(List<PlateModel> results) async {
    final rootContext = Navigator.of(context, rootNavigator: true).context;

    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (dialogCtx) {
        return Dialog(
          insetPadding: const EdgeInsets.all(16),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 640,
              maxHeight: MediaQuery.of(dialogCtx).size.height * 0.8,
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.search, color: Colors.blueAccent),
                      const SizedBox(width: 8),
                      const Text('검색 결과', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.of(dialogCtx).pop(),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '입력 번호: ${_controller.text}   /   구역: ${widget.area.isEmpty ? "-" : widget.area}',
                    style: const TextStyle(fontSize: 12, color: Colors.black54),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: results.isEmpty
                        ? const _InlineEmpty(text: '검색 결과가 없습니다.')
                        : SingleChildScrollView(
                      child: PlateSearchResultSection(
                        results: results,
                        onSelect: (selected) async {
                          if (_navigating) return;
                          _navigating = true;

                          Navigator.of(dialogCtx).pop();

                          final didConfirm = await showTabletPageStatusBottomSheet(
                            context: rootContext,
                            plate: selected,
                            onRequestEntry: () async {},
                            onDelete: () {},
                          );

                          if (didConfirm != null) {
                            _resetToInitial();
                          } else {
                            _navigating = false;
                          }
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () => Navigator.of(dialogCtx).pop(),
                      child: const Text('닫기'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    // pad 모드에 따라 우측 패널 내부 레이아웃 분기
    final isSmallPad = context.select<PadModeState, bool>((s) => s.isSmall);

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
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const PlateSearchHeaderSection(),
                      const SizedBox(height: 16),
                      PlateNumberDisplaySection(controller: _controller, isValidPlate: _isValidPlate),
                      const SizedBox(height: 24),
                      if (_isLoading)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 8),
                          child: LinearProgressIndicator(minHeight: 3),
                        ),
                      const Spacer(),
                    ],
                  ),
                ),
              ),

            // 👇 키패드 영역 (오른쪽 패널 **내부**)
            if (isSmallPad)
              Expanded(
                child: SafeArea(
                  top: false,
                  bottom: true,
                  child: AnimatedKeypad(
                    slideAnimation: _slideAnimation,
                    fadeAnimation: _fadeAnimation,
                    controller: _controller,
                    maxLength: 4,
                    enableDigitModeSwitch: false,
                    onComplete: _onKeypadComplete,
                    onReset: _resetToInitial,
                    fullHeight: true, // ← small pad: 우측 패널 높이를 100% 사용
                  ),
                ),
              )
            else
              SafeArea(
                top: false,
                bottom: true,
                child: AnimatedKeypad(
                  slideAnimation: _slideAnimation,
                  fadeAnimation: _fadeAnimation,
                  controller: _controller,
                  maxLength: 4,
                  enableDigitModeSwitch: false, // 마지막 행: ['처음','0','검색']
                  onComplete: _onKeypadComplete,
                  onReset: _resetToInitial,
                  // fullHeight 기본 false → 높이 45% 제한
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// 공통: 빈 상태(인라인)
class _InlineEmpty extends StatelessWidget {
  final String text;

  const _InlineEmpty({required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Center(
        child: Text(
          text,
          style: const TextStyle(color: Colors.redAccent, fontSize: 16),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}
