// lib/screens/tablet_page.dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

// 분리한 좌/우 패널
import '../../models/plate_model.dart';
import '../../states/area/area_state.dart';
import '../../states/plate/plate_state.dart';
import '../tablet_package/body_panels/tablet_left_panel.dart';
import '../tablet_package/body_panels/tablet_right_panel.dart';
import '../tablet_package/widgets/tablet_top_navigation.dart';
import '../tablet_package/states/tablet_pad_mode_state.dart';

class TabletPage extends StatefulWidget {
  const TabletPage({super.key});

  @override
  State<TabletPage> createState() => _TabletPageState();
}

class _TabletPageState extends State<TabletPage> {
  StreamSubscription<PlateModel>? _removedSub;

  final List<String> _completedChips = <String>[];
  final Set<String> _completedChipSet = <String>{};
  final Set<String> _selectedChips = <String>{};
  String? _areaCache;

  void _addCompletedChip(String plateNumber) {
    if (_completedChipSet.add(plateNumber)) {
      setState(() => _completedChips.insert(0, plateNumber));
    }
  }

  void _removeCompletedChip(String plateNumber) {
    if (_completedChipSet.remove(plateNumber)) {
      setState(() {
        _completedChips.remove(plateNumber);
        _selectedChips.remove(plateNumber);
      });
    }
  }

  void _toggleChipSelection(String plateNumber) {
    setState(() {
      if (_selectedChips.contains(plateNumber)) {
        _selectedChips.remove(plateNumber);
      } else {
        _selectedChips.add(plateNumber);
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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final plateState = context.read<PlateState>();
      final areaState = context.read<AreaState>();

      _removedSub = plateState.onDepartureRequestRemoved.listen((removed) {
        final currentArea = areaState.currentArea;
        if (!mounted || removed.area != currentArea) return;

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('출차 완료 처리됨: ${removed.plateNumber}'),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 3),
          ),
        );
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
    final area = context.select<AreaState, String?>((s) => s.currentArea) ?? '';
    final padMode = context.select<TabletPadModeState, PadMode>((s) => s.mode);

    if (_areaCache != area) {
      _areaCache = area;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _clearChipsForAreaChange();
      });
    }

    // ✅ 뒤로가기(시스템 back)로 이 라우트를 pop하지 않음 → 앱이 종료되지 않음
    return PopScope(
      canPop: false, // 루트 pop 차단
      onPopInvoked: (didPop) {
        if (didPop) return;
        // 안내만 제공(원하면 삭제 가능)
        final messenger = ScaffoldMessenger.maybeOf(context);
        messenger?.hideCurrentSnackBar();
        messenger?.showSnackBar(
          const SnackBar(
            content: Text('뒤로가기가 비활성화되어 앱이 종료되지 않습니다. 상단 메뉴에서 이동하세요.'),
            duration: Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
      },
      // Flutter <3.7 사용 시:
      // return WillPopScope(
      //   onWillPop: () async => false,
      //   child: Scaffold(...),
      // );
      child: Scaffold(
        backgroundColor: Colors.white,

        appBar: const PreferredSize(
          preferredSize: Size.fromHeight(kToolbarHeight),
          child: SafeArea(
            bottom: false,
            child: TabletTopNavigation(isAreaSelectable: true),
          ),
        ),

        body: SafeArea(
          top: false,
          child: Column(
            children: [
              _StickyNoticeBar(
                plates: _completedChips,
                selectedPlates: _selectedChips,
                onToggleSelect: _toggleChipSelection,
                onRemove: _removeCompletedChip,
              ),

              Expanded(
                child: padMode == PadMode.show
                // ▶ show 모드: 왼쪽 패널만 전체 화면
                    ? ColoredBox(
                  color: const Color(0xFFF7F8FA),
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: LeftPaneDeparturePlates(
                      key: ValueKey('left-pane-$area-show'),
                    ),
                  ),
                )
                // ▶ big/small: 2열 유지 (small은 우측 패널 내부에서 키패드 100%)
                    : Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // ⬅️ 왼쪽 패널
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

                    // ➡️ 오른쪽 패널
                    Expanded(
                      child: ClipRRect(
                        borderRadius: const BorderRadius.only(topLeft: Radius.circular(12)),
                        child: RightPaneSearchPanel(
                          key: ValueKey('right-pane-$area'),
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
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────────────
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
          border: Border(bottom: BorderSide(color: Colors.amber.shade200)),
        ),
        child: Row(
          children: [
            const Icon(Icons.info_outline, size: 18, color: Colors.amber),
            const SizedBox(width: 8),
            Expanded(
              child: hasChips
                  ? Row(
                children: [
                  const Text(
                    '출차 완료: ',
                    style: TextStyle(fontSize: 13, color: Color(0xFF5D4037), fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(width: 6),
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
                              onSelected: (_) => onToggleSelect(p),
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
                style: TextStyle(fontSize: 13, color: Color(0xFF5D4037), fontWeight: FontWeight.w600),
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
