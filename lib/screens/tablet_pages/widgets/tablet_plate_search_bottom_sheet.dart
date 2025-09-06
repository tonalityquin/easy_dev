import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../../../models/plate_model.dart';
import '../../../../../../repositories/plate/firestore_plate_repository.dart';
import '../../../../../../states/plate/movement_plate.dart';
import '../../../../../../states/plate/delete_plate.dart';
import '../../../../../../states/user/user_state.dart';
import '../../../../../../enums/plate_type.dart';
import '../../../../../../utils/snackbar_helper.dart';

// ⬇️ Provider에서 현재 area를 직접도 비교 로그 찍기 위해 import
import '../../../../../../states/area/area_state.dart';
import 'tablet_page_status_bottom_sheet.dart';
import 'tablet_plate_search_bottom_sheet/keypad/animated_keypad.dart';
import 'tablet_plate_search_bottom_sheet/sections/plate_number_display.dart';
import 'tablet_plate_search_bottom_sheet/sections/plate_search_header.dart';
import 'tablet_plate_search_bottom_sheet/sections/plate_search_results.dart';
import 'tablet_plate_search_bottom_sheet/sections/search_button.dart';

class TabletPlateSearchBottomSheet extends StatefulWidget {
  final void Function(String) onSearch;
  final String area;

  const TabletPlateSearchBottomSheet({
    super.key,
    required this.onSearch,
    required this.area,
  });

  @override
  State<TabletPlateSearchBottomSheet> createState() => _TabletPlateSearchBottomSheetState();
}

class _TabletPlateSearchBottomSheetState extends State<TabletPlateSearchBottomSheet>
    with SingleTickerProviderStateMixin {
  final TextEditingController _controller = TextEditingController();

  bool _isLoading = false;
  bool _hasSearched = false;
  bool _navigating = false; // 빠른 중복 탭 방지

  List<PlateModel> _results = [];

  late AnimationController _keypadController;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _fadeAnimation;

  // 문자열 정규화(전각 괄호 → 반각, trim)
  String _norm(String s) => s.replaceAll('（', '(').replaceAll('）', ')').trim();

  @override
  void initState() {
    super.initState();
    _keypadController = AnimationController(vsync: this, duration: const Duration(milliseconds: 500));
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.2),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _keypadController, curve: Curves.easeOut));
    _fadeAnimation = CurvedAnimation(parent: _keypadController, curve: Curves.easeIn);
    _keypadController.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    _keypadController.dispose();
    super.dispose();
  }

  bool isValidPlate(String value) {
    return RegExp(r'^\d{4}$').hasMatch(value);
  }

  Future<void> _refreshSearchResults() async {
    if (!mounted) return; // 가드 1
    setState(() {
      _isLoading = true;
    });

    try {
      final repository = FirestorePlateRepository();

      // ⬇️⬇️⬇️  검색 직전 진단 로그 추가  ⬇️⬇️⬇️
      final input = _controller.text;
      final valid = isValidPlate(input);
      final widgetArea = widget.area;
      final providerArea = context.read<AreaState>().currentArea;
      final normWidgetArea = _norm(widgetArea);
      final normProviderArea = _norm(providerArea);

      debugPrint('🔎 [TabletPlateSearch] BEFORE QUERY | '
          'input="$input" valid=$valid | '
          'widget.area="$widgetArea" codeUnits=${widgetArea.codeUnits} | '
          'provider.area="$providerArea" codeUnits=${providerArea.codeUnits} | '
          'norm.widget="$normWidgetArea" norm.provider="$normProviderArea" | '
          'key=${widget.key} stateHash=${identityHashCode(this)}');
      // ⬆️⬆️⬆️  검색 직전 진단 로그 추가  ⬆️⬆️⬆️

      final results = await repository.fourDigitSignatureQuery(
        plateFourDigit: input,
        area: widgetArea,
      );

      // 검색 결과 로그(개수)
      debugPrint('✅ [TabletPlateSearch] AFTER QUERY | resultCount=${results.length}');

      if (!mounted) return; // 가드 2
      setState(() {
        _results = results;
        _hasSearched = true;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return; // 가드 3
      setState(() {
        _isLoading = false;
      });
      // 🔁 SnackbarHelper로 대체
      showFailedSnackbar(context, '검색 중 오류가 발생했습니다: $e');
      debugPrint('❗ [TabletPlateSearch] QUERY ERROR: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    // rootNavigator 컨텍스트를 미리 확보(현재 시트 닫은 뒤에도 사용 가능)
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
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                ),
                child: ClipRRect(
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                  child: ListView(
                    controller: scrollController,
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                    children: [
                      Center(
                        child: Container(
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                            color: Colors.grey.shade300,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      const PlateSearchHeader(),
                      const SizedBox(height: 24),
                      PlateNumberDisplay(controller: _controller, isValidPlate: isValidPlate),
                      const SizedBox(height: 24),

                      // 결과 영역
                      Builder(
                        builder: (_) {
                          final text = _controller.text;
                          final valid = isValidPlate(text);

                          if (!_hasSearched) {
                            return const SizedBox.shrink();
                          }

                          if (_isLoading) {
                            return const Padding(
                              padding: EdgeInsets.symmetric(vertical: 24),
                              child: Center(child: CircularProgressIndicator()),
                            );
                          }

                          // 유효하지 않은 형식
                          if (!valid) {
                            return const _EmptyState(text: '유효하지 않은 번호 형식입니다. (숫자 4자리)');
                          }

                          // 유효하지만 결과 없음
                          if (_results.isEmpty) {
                            return const _EmptyState(text: '검색 결과가 없습니다.');
                          }

                          // 결과 표시
                          return PlateSearchResults(
                            results: _results,
                            onSelect: (selected) {
                              if (_navigating) return; // 중복 탭 방지
                              _navigating = true;

                              // 먼저 현재 시트를 닫고
                              Navigator.pop(context);

                              // 다음 프레임에 안전하게 실행(바텀시트 컨텍스트 분리)
                              WidgetsBinding.instance.addPostFrameCallback((_) {
                                // 이 시점에 본 위젯은 dispose 되었어도 rootContext는 유효
                                showTabletPageStatusBottomSheet(
                                  context: rootContext,
                                  plate: selected,
                                  onRequestEntry: () async {
                                    final user = rootContext.read<UserState>().name;
                                    await rootContext.read<MovementPlate>().goBackToParkingRequest(
                                          fromType: PlateType.parkingCompleted,
                                          plateNumber: selected.plateNumber,
                                          area: selected.area,
                                          newLocation: "미지정",
                                          performedBy: user,
                                        );
                                    await _refreshSearchResults();
                                  },
                                  onDelete: () async {
                                    await rootContext.read<DeletePlate>().deleteFromParkingCompleted(
                                          selected.plateNumber,
                                          selected.area,
                                        );
                                    await _refreshSearchResults();
                                  },
                                );
                              });
                            },
                          );
                        },
                      ),

                      Center(
                        child: TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('닫기'),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // 검색 버튼
                      ValueListenableBuilder<TextEditingValue>(
                        valueListenable: _controller,
                        builder: (context, value, child) {
                          final valid = isValidPlate(value.text);
                          return SearchButton(
                            isValid: valid,
                            isLoading: _isLoading,
                            onPressed: valid
                                ? () async {
                                    await _refreshSearchResults();
                                    widget.onSearch(value.text);
                                  }
                                : null,
                          );
                        },
                      ),

                      const SizedBox(height: 16),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        bottomNavigationBar: _hasSearched
            ? const SizedBox.shrink()
            : AnimatedKeypad(
                slideAnimation: _slideAnimation,
                fadeAnimation: _fadeAnimation,
                controller: _controller,
                maxLength: 4,
                enableDigitModeSwitch: false,
                onComplete: () => setState(() {}),
                onReset: () => setState(() {
                  _controller.clear();
                  _hasSearched = false;
                  _results.clear();
                }),
              ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final String text;

  const _EmptyState({required this.text});

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
