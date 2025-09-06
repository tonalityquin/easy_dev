import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

// 프로젝트 패키지 경로 (필요에 맞게 조정하세요)
import 'package:easydev/models/plate_model.dart';
import 'package:easydev/repositories/plate/firestore_plate_repository.dart';
import 'package:easydev/states/area/area_state.dart';
import 'package:easydev/states/plate/plate_state.dart';
import 'package:easydev/enums/plate_type.dart';
import 'package:easydev/utils/snackbar_helper.dart';

// 🔁 우측 패널에서 재사용할 하위 컴포넌트(기존 바텀시트 내 구성요소 그대로 재사용)
import 'tablet_pages/widgets/tablet_plate_search_bottom_sheet/keypad/animated_keypad.dart';
import 'tablet_pages/widgets/tablet_plate_search_bottom_sheet/sections/plate_number_display.dart';
import 'tablet_pages/widgets/tablet_plate_search_bottom_sheet/sections/plate_search_header.dart';
import 'tablet_pages/widgets/tablet_plate_search_bottom_sheet/sections/plate_search_results.dart';
import 'tablet_pages/widgets/tablet_plate_search_bottom_sheet/sections/search_button.dart';
import 'tablet_pages/widgets/tablet_page_status_bottom_sheet.dart';
import 'tablet_pages/widgets/tablet_top_navigation.dart';

// ────────────────────────────────────────────────────────────────────────────
// TabletPage: 좌(출차요청 번호판만 리스트) + 우(키패드+검색)
//  - 출차요청에서 사라진 번호판(=출차 완료 추정)에 대해 1회 스낵바 보조 알림
//  - 상단 배너에 ‘출차 완료’ 칩을 누적 표시 + 칩 선택 시 X 노출 → X로 삭제
// ────────────────────────────────────────────────────────────────────────────

class TabletPage extends StatefulWidget {
  const TabletPage({super.key});

  @override
  State<TabletPage> createState() => _TabletPageState();
}

class _TabletPageState extends State<TabletPage> {
  StreamSubscription<PlateModel>? _removedSub;

  // 배너에 표시할 ‘출차 완료로 추정되는’ 번호판 칩(로컬, 중복 방지)
  final List<String> _completedChips = <String>[];
  final Set<String> _completedChipSet = <String>{};

  // 칩의 선택 상태(선택 시 X가 보이고, 다시 선택 해제하면 X 숨김)
  final Set<String> _selectedChips = <String>{};

  String? _areaCache; // 지역 변경 시 배너 칩 초기화를 위한 캐시

  void _addCompletedChip(String plateNumber) {
    if (_completedChipSet.add(plateNumber)) {
      setState(() {
        _completedChips.insert(0, plateNumber); // 최신이 앞에 오도록
      });
    }
  }

  void _removeCompletedChip(String plateNumber) {
    if (_completedChipSet.remove(plateNumber)) {
      setState(() {
        _completedChips.remove(plateNumber);
        _selectedChips.remove(plateNumber); // 함께 정리
      });
    }
  }

  void _toggleChipSelection(String plateNumber) {
    setState(() {
      if (_selectedChips.contains(plateNumber)) {
        _selectedChips.remove(plateNumber); // 선택 해제 → X 숨김
      } else {
        _selectedChips.add(plateNumber);    // 선택 → X 표시
      }
    });
  }

  void _clearChipsForAreaChange() {
    setState(() {
      _completedChips.clear();
      _completedChipSet.clear();
      _selectedChips.clear();
    });
  }

  @override
  void initState() {
    super.initState();
    // 이벤트 기반 1회 토스트/스낵바(보조): 출차요청에서 사라진 번호판 알림
    // departureCompleted 구독 없이도 PlateState가 departureRequests 스트림 변화로 감지함
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final plateState = context.read<PlateState>();
      final areaState = context.read<AreaState>();

      _removedSub = plateState.onDepartureRequestRemoved.listen((removed) {
        // 현재 화면의 지역과 동일한 경우에만 보조 알림 & 배너 반영
        final currentArea = areaState.currentArea;
        if (!mounted || removed.area != currentArea) return;

        // 스낵바 알림
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('출차 완료 처리됨: ${removed.plateNumber}'),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 3),
          ),
        );

        // 상단 배너 칩에도 추가(중복 방지)
        _addCompletedChip(removed.plateNumber);
      });
    });
  }

  @override
  void dispose() {
    _removedSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Area 변경 시 패널들이 반응하도록 select 사용 (null 방지)
    final area = context.select<AreaState, String?>((s) => s.currentArea) ?? '';

    // 지역이 바뀌면 배너 칩은 혼동 방지를 위해 초기화
    if (_areaCache != area) {
      _areaCache = area;
      // build 중 setState는 피하려고 프레임 후 초기화
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _clearChipsForAreaChange();
      });
    }

    return Scaffold(
      backgroundColor: Colors.white,

      // ✅ 앱바에 TabletTopNavigation 삽입 (탭 시 다이얼로그 열림)
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(kToolbarHeight),
        child: const SafeArea(
          bottom: false,
          child: TabletTopNavigation(
            isAreaSelectable: true, // 탭 시 다이얼로그가 열리도록 활성화
          ),
        ),
      ),

      // ✅ 본문(상단 고정 안내/칩 + 2열 레이아웃)
      body: SafeArea(
        top: false, // 상단 SafeArea는 appBar가 처리하므로 false
        child: Column(
          children: [
            // ⛳ 상시 노출 안내/칩 배너 (앱바 아래 고정) — 칩 선택 시 X 노출, X로 삭제
            _StickyNoticeBar(
              plates: _completedChips,
              selectedPlates: _selectedChips,
              onToggleSelect: _toggleChipSelection,
              onRemove: _removeCompletedChip,
            ),

            // 본문 2열
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ⬅️ 왼쪽 패널: plates 컬렉션에서 type=출차요청인 데이터만 번호판 표시
                  Expanded(
                    child: ColoredBox(
                      color: const Color(0xFFF7F8FA),
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: _LeftPaneDeparturePlates(
                          key: ValueKey('left-pane-$area'),
                        ),
                      ),
                    ),
                  ),

                  const VerticalDivider(width: 1, thickness: 1, color: Color(0xFFEBEDF0)),

                  // ➡️ 오른쪽 패널: 키패드+검색 UI 직접 삽입
                  Expanded(
                    child: ClipRRect(
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(12),
                      ),
                      child: _RightPaneSearchPanel(
                        key: ValueKey('right-pane-$area'), // 🔑 area 변경 시 패널 자체 재생성
                        area: area,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),

      // ✅ 하단 펠리컨
      bottomNavigationBar: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: SizedBox(
                height: 48,
                child: Image.asset('assets/images/pelican.png'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────
/* 앱바 아래 상시 노출 안내/칩 배너
   - 칩 목록(plates)
   - 선택된 칩 집합(selectedPlates) : 선택 시 X 표시, 선택 해제 시 X 숨김
   - onToggleSelect: 칩을 탭할 때 선택/해제 토글
   - onRemove: X를 눌러 칩을 삭제(숨김)
*/
class _StickyNoticeBar extends StatelessWidget {
  final List<String> plates;
  final Set<String> selectedPlates;
  final void Function(String plateNumber) onToggleSelect;
  final void Function(String plateNumber) onRemove;

  const _StickyNoticeBar({
    required this.plates,
    required this.selectedPlates,
    required this.onToggleSelect,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final hasChips = plates.isNotEmpty;

    return Material(
      color: Colors.amber.shade50,
      borderOnForeground: false,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: Colors.amber.shade200),
          ),
        ),
        child: Row(
          children: [
            const Icon(Icons.info_outline, size: 18, color: Colors.amber),
            const SizedBox(width: 8),

            // 칩이 없으면 안내 문구, 있으면 '출차 완료:' + 칩들 (가로 스크롤)
            Expanded(
              child: hasChips
                  ? Row(
                children: [
                  const Text(
                    '출차 완료: ',
                    style: TextStyle(
                      fontSize: 13,
                      color: Color(0xFF5D4037),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 6),
                  // 칩들만 스크롤
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: plates
                            .map(
                              (p) {
                            final selected = selectedPlates.contains(p);
                            return Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: InputChip(
                                label: Text(p),
                                selected: selected,
                                showCheckmark: false, // 체크 표시 대신 선택 배경만
                                onSelected: (_) => onToggleSelect(p), // 탭 → 선택/해제
                                // 선택 상태일 때만 X(삭제) 노출
                                onDeleted: selected ? () => onRemove(p) : null,
                                deleteIcon: selected ? const Icon(Icons.close, size: 16) : null,
                                visualDensity: VisualDensity.compact,
                                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              ),
                            );
                          },
                        )
                            .toList(),
                      ),
                    ),
                  ),
                ],
              )
                  : const Text(
                '출차 요청 목록에서 방금 누른 번호가 사라졌다면, 출차 완료 처리된 것입니다.',
                style: TextStyle(
                  fontSize: 13,
                  color: Color(0xFF5D4037),
                  fontWeight: FontWeight.w600,
                ),
                overflow: TextOverflow.ellipsis,
                maxLines: 2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────
// 왼쪽 패널: plates 컬렉션에서 type=출차 요청만 실시간으로 받아 "번호판만" 렌더링
// PlateState의 구독 스트림(현재 지역 기준)에 의존
// ────────────────────────────────────────────────────────────────────────────
class _LeftPaneDeparturePlates extends StatelessWidget {
  const _LeftPaneDeparturePlates({super.key});

  @override
  Widget build(BuildContext context) {
    final currentArea = context.select<AreaState, String?>((s) => s.currentArea) ?? '';
    return Consumer<PlateState>(
      builder: (context, plateState, _) {
        // PlateState가 현재 지역(currentArea)로 구독 중인 출차 요청 목록
        List<PlateModel> plates = plateState.getPlatesByCollection(PlateType.departureRequests);

        // 혹시 모를 안전장치로 type/area 재확인
        plates = plates
            .where((p) => p.type == PlateType.departureRequests.firestoreValue && p.area == currentArea)
            .toList();

        // 최신순 정렬(요청시간 내림차순)
        plates.sort((a, b) => b.requestTime.compareTo(a.requestTime));

        final isEmpty = plates.isEmpty;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '출차 요청 번호판',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: isEmpty
                  ? const Center(
                child: Text(
                  '출차 요청이 없습니다.',
                  style: TextStyle(color: Colors.black45),
                ),
              )
                  : ListView.separated(
                itemCount: plates.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (_, idx) {
                  final p = plates[idx];
                  return ListTile(
                    dense: true,
                    leading: const Icon(Icons.directions_car, color: Colors.blueAccent),
                    title: Text(
                      p.plateNumber,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    onTap: null, // 좌측 패널은 단순 표시만
                    visualDensity: VisualDensity.compact,
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────
// 우측 패널: 키패드 + 4자리 검색 → 결과 다이얼로그 + 상태 바텀시트
// ────────────────────────────────────────────────────────────────────────────
class _RightPaneSearchPanel extends StatefulWidget {
  final String area;

  const _RightPaneSearchPanel({
    super.key,
    required this.area,
  });

  @override
  State<_RightPaneSearchPanel> createState() => _RightPaneSearchPanelState();
}

class _RightPaneSearchPanelState extends State<_RightPaneSearchPanel> with SingleTickerProviderStateMixin {
  final TextEditingController _controller = TextEditingController();

  bool _isLoading = false;
  bool _navigating = false; // 빠른 중복 탭 방지

  // 🔥 검색 UI(키패드/입력)는 항상 유지
  bool _keypadVisible = true;

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
  void didUpdateWidget(covariant _RightPaneSearchPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    // area가 변경되면 입력 초기화 + 키패드 유지
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
    if (!mounted) return;
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

      // ✅ 패널을 건드리지 않고, 결과는 Dialog로 표시
      await _showResultsDialog(results);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      showFailedSnackbar(context, '검색 중 오류가 발생했습니다: $e');
    }
  }

  void _toggleKeypad([bool? force]) {
    setState(() {
      _keypadVisible = force ?? !_keypadVisible;
      if (_keypadVisible) {
        _keypadController.forward(from: 0);
      }
    });
  }

  void _resetToInitial() {
    setState(() {
      _controller.clear();
      _keypadVisible = true;
      _isLoading = false;
    });
    _keypadController.forward(from: 0);
    _navigating = false;
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

                          // 상태 확인 바텀시트(네/아니요) → true/false/null
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
      body: SafeArea(
        top: false, // 상단 SafeArea는 상위 Scaffold(appBar)가 처리
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const PlateSearchHeader(),
              const SizedBox(height: 16),

              // ✅ 키패드 열기/닫기 토글 버튼
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: _toggleKeypad,
                  icon: Icon(_keypadVisible ? Icons.keyboard_hide : Icons.keyboard),
                  label: Text(_keypadVisible ? '키패드 닫기' : '키패드 열기'),
                ),
              ),

              // 현재 입력·유효성 표시 (탭하면 키패드 열기)
              GestureDetector(
                onTap: () {
                  if (!_keypadVisible) _toggleKeypad(true); // 표시부 탭으로도 키패드 열기
                },
                child: PlateNumberDisplay(controller: _controller, isValidPlate: _isValidPlate),
              ),
              const SizedBox(height: 24),

              // 🔎 결과는 다이얼로그로 보여주므로, 본문에는 로딩만 표시
              if (_isLoading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: LinearProgressIndicator(minHeight: 3),
                ),

              const Spacer(),

              // 검색 버튼 (키패드와 독립)
              ValueListenableBuilder<TextEditingValue>(
                valueListenable: _controller,
                builder: (context, value, _) {
                  final valid = _isValidPlate(value.text);
                  return SearchButton(
                    isValid: valid,
                    isLoading: _isLoading,
                    onPressed: valid ? _refreshSearchResults : null,
                  );
                },
              ),
            ],
          ),
        ),
      ),

      // 🔻 숫자 키패드: 토글 상태(_keypadVisible)로 제어 (검색 후에도 유지)
      bottomNavigationBar: _keypadVisible
          ? AnimatedKeypad(
        slideAnimation: _slideAnimation,
        fadeAnimation: _fadeAnimation,
        controller: _controller,
        maxLength: 4,
        enableDigitModeSwitch: false,
        onComplete: () => setState(() {}), // 입력 완료 시 버튼 활성화를 위해 리빌드
        onReset: _resetToInitial,
      )
          : const SizedBox.shrink(),
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────
// 공통: 빈 상태(인라인)
// ────────────────────────────────────────────────────────────────────────────

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
