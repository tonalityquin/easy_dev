// lib/screens/tablet_right_panel.dart
import 'dart:async';
import 'package:flutter/material.dart';

// 재사용 UI 컴포넌트(기존 상대 경로 유지)
import '../../models/plate_model.dart';
import '../../repositories/plate/firestore_plate_repository.dart';
import '../../utils/snackbar_helper.dart';
import 'widgets/tablet_plate_search_bottom_sheet/keypad/animated_keypad.dart';
import 'widgets/tablet_plate_search_bottom_sheet/sections/plate_number_display.dart';
import 'widgets/tablet_plate_search_bottom_sheet/sections/plate_search_header.dart';
import 'widgets/tablet_plate_search_bottom_sheet/sections/plate_search_results.dart';
import 'widgets/tablet_page_status_bottom_sheet.dart';

/// 우측 패널: 키패드 + 4자리 검색 → 결과 다이얼로그 + 상태 바텀시트.
/// 키패드는 항상 열려 있으며, '검색'은 키패드 마지막 행에서 실행합니다.
/// ✅ 검색창과 키패드를 모두 body 안 같은 Column 트리에서 빌드(빌딩 방식 통일).
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
    // area가 변경되면 입력 초기화
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

      // ✅ 결과는 Dialog로 표시 (패널은 그대로 유지)
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

  // 키패드에서 '검색' 키(또는 자동완료 트리거)를 통해 호출
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
                  // 헤더
                  Row(
                    children: [
                      const Icon(Icons.search, color: Colors.blueAccent),
                      const SizedBox(width: 8),
                      const Text(
                        '검색 결과',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
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

                  // 본문
                  Expanded(
                    child: results.isEmpty
                        ? const _InlineEmpty(text: '검색 결과가 없습니다.')
                        : SingleChildScrollView(
                      child: PlateSearchResults(
                        results: results,
                        onSelect: (selected) async {
                          if (_navigating) return;
                          _navigating = true;

                          // 결과 다이얼로그 먼저 닫기
                          Navigator.of(dialogCtx).pop();

                          // 상태 확인 바텀시트(네/아니요)
                          final didConfirm = await showTabletPageStatusBottomSheet(
                            context: rootContext,
                            plate: selected,
                            onRequestEntry: () async {}, // 시그니처 유지용(미사용)
                            onDelete: () {}, // 시그니처 유지용(미사용)
                          );

                          // 버튼으로 닫혔으면 오른쪽 초기화 (좌측은 PlateState가 알아서 반영)
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
    return Scaffold(
      backgroundColor: Colors.white,

      // ✅ 검색창과 키패드를 모두 body 안에서 같은 Column으로 빌드
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            // 상단 컨텐츠는 Padding으로 감싸고, 아래 키패드는 전체 폭으로 배치
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const PlateSearchHeader(),
                    const SizedBox(height: 16),

                    // (키패드 토글 버튼 없음)

                    // 현재 입력·유효성 표시
                    PlateNumberDisplay(controller: _controller, isValidPlate: _isValidPlate),
                    const SizedBox(height: 24),

                    // 🔎 결과는 다이얼로그로 보여주므로, 본문에는 로딩만 표시
                    if (_isLoading)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: LinearProgressIndicator(minHeight: 3),
                      ),

                    // 본문 여백 채우기
                    const Spacer(),
                  ],
                ),
              ),
            ),

            // 👇 동일한 빌딩 경로(body 내부)에서 키패드 배치
            // SafeArea(bottom:true)로 하단 시스템 영역을 피하고, 전체 폭 사용
            SafeArea(
              top: false,
              bottom: true,
              child: AnimatedKeypad(
                slideAnimation: _slideAnimation,
                fadeAnimation: _fadeAnimation,
                controller: _controller,
                maxLength: 4,
                enableDigitModeSwitch: false, // 마지막 행: ['처음','0','검색']
                onComplete: _onKeypadComplete, // '검색' 또는 자동완료 시 검색 실행
                onReset: _resetToInitial,
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
