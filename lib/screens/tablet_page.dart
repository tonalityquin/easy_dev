// lib/screens/tablet_page.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

// 분리한 좌/우 패널
import '../models/plate_model.dart';
import '../states/area/area_state.dart';
import '../states/plate/plate_state.dart';
import 'tablet_pages/tablet_left_panel.dart';
import 'tablet_pages/tablet_right_panel.dart';
import 'tablet_pages/widgets/tablet_top_navigation.dart';

// 상단 네비게이션

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
        _selectedChips.add(plateNumber); // 선택 → X 표시
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
                        child: LeftPaneDeparturePlates(
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
                      child: RightPaneSearchPanel(
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
                          style: TextStyle(fontSize: 13, color: Color(0xFF5D4037), fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(width: 6),
                        // 칩들만 스크롤
                        Expanded(
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children: plates.map((p) {
                                final selected = selectedPlates.contains(p);
                                return Padding(
                                  padding: const EdgeInsets.only(right: 6),
                                  child: InputChip(
                                    label: Text(p),
                                    selected: selected,
                                    showCheckmark: false,
                                    // 체크 표시 대신 선택 배경만
                                    onSelected: (_) => onToggleSelect(p),
                                    // 탭 → 선택/해제
                                    // 선택 상태일 때만 X(삭제) 노출
                                    onDeleted: selected ? () => onRemove(p) : null,
                                    deleteIcon: selected ? const Icon(Icons.close, size: 16) : null,
                                    visualDensity: VisualDensity.compact,
                                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                  ),
                                );
                              }).toList(),
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
