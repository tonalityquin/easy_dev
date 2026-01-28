import 'package:flutter/material.dart';

import '../../../../../../models/plate_model.dart';
import '../widgets/minor_departure_completed_status_bottom_sheet.dart';
import 'keypad/animated_keypad.dart';
import 'widgets/minor_departure_completed_plate_number_display.dart';
import 'widgets/minor_departure_completed_plate_search_header.dart';
import 'widgets/minor_departure_completed_plate_search_results.dart';
import 'widgets/minor_departure_completed_search_button.dart';
import '../../../../../../repositories/plate_repo_services/firestore_plate_repository.dart';

// ✅ 프로젝트 공통 스낵바 헬퍼 사용(기존 SnackBar 직접 호출 제거)
import '../../../../../../utils/snackbar_helper.dart';

class MinorDepartureCompletedSearchBottomSheet extends StatefulWidget {
  final void Function(String) onSearch;
  final String area;

  const MinorDepartureCompletedSearchBottomSheet({
    super.key,
    required this.onSearch,
    required this.area,
  });

  @override
  State<MinorDepartureCompletedSearchBottomSheet> createState() =>
      _MinorDepartureCompletedSearchBottomSheetState();
}

class _MinorDepartureCompletedSearchBottomSheetState
    extends State<MinorDepartureCompletedSearchBottomSheet>
    with SingleTickerProviderStateMixin {
  // ✅ 요청 팔레트(기존 톤 유지)
  static const Color _base = Color(0xFF546E7A); // BlueGrey 600
  static const Color _dark = Color(0xFF37474F); // BlueGrey 800

  final TextEditingController _controller = TextEditingController();

  bool _isLoading = false;
  bool _hasSearched = false;
  bool _navigating = false;

  List<PlateModel> _results = [];

  late final AnimationController _keypadController;
  late final Animation<Offset> _slideAnimation;
  late final Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _keypadController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.2),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _keypadController, curve: Curves.easeOut));
    _fadeAnimation =
        CurvedAnimation(parent: _keypadController, curve: Curves.easeIn);
    _keypadController.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    _keypadController.dispose();
    super.dispose();
  }

  bool _isValidPlate(String value) => RegExp(r'^\d{4}$').hasMatch(value.trim());

  Future<void> _refreshSearchResults() async {
    if (!mounted) return;
    if (_isLoading) return;

    final q = _controller.text.trim();
    final area = widget.area.trim();

    // ✅ 방어: invalid 입력이면 쿼리하지 않음
    if (!_isValidPlate(q)) {
      showSelectedSnackbar(context, '숫자 4자리를 입력해주세요.');
      return;
    }

    // ✅ 방어: area 비어있으면 쿼리하지 않음
    if (area.isEmpty) {
      showFailedSnackbar(context, '현재 지역(area)이 설정되지 않아 검색할 수 없습니다.');
      return;
    }

    setState(() => _isLoading = true);

    try {
      final repository = FirestorePlateRepository();

      final results = await repository.fourDigitDepartureCompletedQuery(
        plateFourDigit: q,
        area: area,
      );

      if (!mounted) return;
      setState(() {
        _results = results;
        _hasSearched = true;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      // ✅ 기존 SnackBar 직접 호출 제거 → 공통 헬퍼로 통일
      showFailedSnackbar(context, '검색 중 오류가 발생했습니다: $e');
    }
  }

  void _resetSearch() {
    if (!mounted) return;
    setState(() {
      _controller.clear();
      _hasSearched = false;
      _results.clear();
      _navigating = false; // ✅ 재진입 안전(패턴 통일)
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final rootContext = Navigator.of(context, rootNavigator: true).context;

    return SafeArea(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Material(
          color: Colors.transparent,
          child: DraggableScrollableSheet(
            initialChildSize: 0.7,
            minChildSize: 0.4,
            maxChildSize: 0.95,
            builder: (context, scrollController) {
              return Container(
                decoration: BoxDecoration(
                  color: cs.surface, // ✅ 테마 대응(기존 white 하드코딩 최소화)
                  borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(20)),
                ),
                child: ClipRRect(
                  borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(20)),
                  child: Column(
                    children: [
                      const SizedBox(height: 10),
                      Center(
                        child: Container(
                          width: 44,
                          height: 4,
                          decoration: BoxDecoration(
                            color: cs.outlineVariant.withOpacity(0.75),
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),

                      // 상단 헤더(닫기 버튼 포함)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: Row(
                          children: [
                            const Expanded(
                              child: MinorDepartureCompletedPlateSearchHeader(),
                            ),
                            IconButton(
                              tooltip: '닫기',
                              onPressed: () => Navigator.pop(context),
                              icon: Icon(Icons.close, color: _dark),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 8),

                      Expanded(
                        child: ListView(
                          controller: scrollController,
                          padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                          children: [
                            // 입력 카드
                            _CardSection(
                              title: '번호 4자리 입력',
                              subtitle: '예: 1234',
                              accent: _base,
                              child: MinorDepartureCompletedPlateNumberDisplay(
                                controller: _controller,
                                isValidPlate: (v) => _isValidPlate(v),
                              ),
                            ),
                            const SizedBox(height: 12),

                            // 결과 영역
                            AnimatedSwitcher(
                              duration: const Duration(milliseconds: 220),
                              switchInCurve: Curves.easeOut,
                              switchOutCurve: Curves.easeIn,
                              child: _buildResultSection(rootContext),
                            ),

                            const SizedBox(height: 12),
                          ],
                        ),
                      ),

                      // 하단 CTA (검색 버튼)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 10, 20, 14),
                        child: ValueListenableBuilder<TextEditingValue>(
                          valueListenable: _controller,
                          builder: (context, value, child) {
                            final valid = _isValidPlate(value.text);
                            return MinorDepartureCompletedSearchButton(
                              isValid: valid,
                              isLoading: _isLoading,
                              onPressed: valid
                                  ? () async {
                                await _refreshSearchResults();
                                // ✅ 외부 콜백은 검색 시도 시점에 호출(기존 정책 유지)
                                // 필요하면 성공 시에만 호출하도록 변경 가능
                                widget.onSearch(value.text.trim());
                              }
                                  : null,
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),

        // 키패드(검색 전만 노출)
        bottomNavigationBar: _hasSearched
            ? const SizedBox.shrink()
            : AnimatedKeypad(
          slideAnimation: _slideAnimation,
          fadeAnimation: _fadeAnimation,
          controller: _controller,
          maxLength: 4,
          enableDigitModeSwitch: false,
          onComplete: () => setState(() {}),
          onReset: _resetSearch, // ✅ 공통 reset 함수로 통일
        ),
      ),
    );
  }

  // ✅ scrollController는 내부에서 사용하지 않으므로 제거(불필요 인자/경고 예방)
  Widget _buildResultSection(BuildContext rootContext) {
    final text = _controller.text.trim();
    final valid = _isValidPlate(text);

    if (!_hasSearched) {
      return const SizedBox.shrink();
    }

    if (_isLoading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 26),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (!valid) {
      return const _EmptyState(
        icon: Icons.error_outline,
        title: '유효하지 않은 번호 형식',
        message: '숫자 4자리를 입력해주세요.',
        tone: _EmptyTone.danger,
      );
    }

    if (_results.isEmpty) {
      return const _EmptyState(
        icon: Icons.search_off,
        title: '검색 결과 없음',
        message: '해당 4자리 번호판을 찾지 못했습니다.',
        tone: _EmptyTone.neutral,
      );
    }

    return MinorDepartureCompletedPlateSearchResults(
      results: _results,
      onSelect: (selected) {
        if (_navigating) return;
        _navigating = true;

        Navigator.pop(context);

        WidgetsBinding.instance.addPostFrameCallback((_) {
          showMinorDepartureCompletedStatusBottomSheet(
            context: rootContext,
            plate: selected,
          );
        });
      },
    );
  }
}

class _CardSection extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget child;
  final Color accent;

  const _CardSection({
    required this.title,
    required this.subtitle,
    required this.child,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outlineVariant.withOpacity(0.8)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 12,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
              ),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

enum _EmptyTone { neutral, danger }

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final _EmptyTone tone;

  const _EmptyState({
    required this.icon,
    required this.title,
    required this.message,
    required this.tone,
  });

  @override
  Widget build(BuildContext context) {
    final Color fg =
    (tone == _EmptyTone.danger) ? Colors.redAccent : Colors.black54;
    final Color bg = (tone == _EmptyTone.danger)
        ? Colors.red.withOpacity(0.05)
        : Colors.grey.shade100;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.black12),
      ),
      child: Row(
        children: [
          Icon(icon, color: fg),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: TextStyle(color: fg, fontWeight: FontWeight.w900)),
                const SizedBox(height: 4),
                Text(
                  message,
                  style: TextStyle(
                    color: fg.withOpacity(0.85),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
