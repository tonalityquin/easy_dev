import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../enums/plate_type.dart';
import '../../../../states/plate/double_plate_state.dart';
import '../../../../states/user/user_state.dart';
import '../../../../states/area/area_state.dart';
import 'departure_completed_plate_search_bottom_sheet/double_departure_completed_search_bottom_sheet.dart';
import 'widgets/double_departure_completed_status_bottom_sheet.dart';

class DoubleDepartureCompletedControlButtons extends StatelessWidget {
  final bool isSearchMode;
  final VoidCallback onResetSearch;
  final VoidCallback onShowSearchDialog;

  const DoubleDepartureCompletedControlButtons({
    super.key,
    required this.isSearchMode,
    required this.onResetSearch,
    required this.onShowSearchDialog,
  });

  Future<void> _openPlateSearchBottomSheet(BuildContext context) async {
    final area = context.read<AreaState>().currentArea.trim();

    if (area.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('현재 지역(area)이 설정되지 않아 검색을 열 수 없습니다.')),
      );
      return;
    }

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DoubleDepartureCompletedSearchBottomSheet(
        area: area,
        onSearch: (_) {},
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final plateState = context.watch<DoublePlateState>();
    final userName = context.read<UserState>().name;

    final selectedPlate = plateState.doubleGetSelectedPlate(
      PlateType.departureCompleted,
      userName,
    );
    final isPlateSelected = selectedPlate != null && selectedPlate.isSelected;

    // 상태 수정 / 검색 버튼 공통 스타일
    final baseStyle = TextButton.styleFrom(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      foregroundColor: cs.onSurface,
    );

    return BottomAppBar(
      color: cs.surface,
      elevation: 0,
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 56,
          child: Center(
            child: isPlateSelected
                ? TextButton.icon(
              onPressed: () async {
                await showDoubleDepartureCompletedStatusBottomSheet(
                  context: context,
                  plate: selectedPlate,
                  performedBy: userName,
                );
              },
              icon: Icon(Icons.settings, color: cs.onSurface),
              label: Text(
                '상태 수정',
                style: TextStyle(
                  color: cs.onSurface,
                  fontWeight: FontWeight.w700,
                ),
              ),
              style: baseStyle,
            )
                : TextButton.icon(
              onPressed: isSearchMode
                  ? onResetSearch
                  : () async {
                await _openPlateSearchBottomSheet(context);
              },
              icon: Icon(
                isSearchMode ? Icons.cancel : Icons.search,
                // ✅ 검색 초기화는 "주의" 톤(tertiary), 검색은 기본 톤(onSurface)
                color: isSearchMode ? cs.tertiary : cs.onSurface,
              ),
              label: Text(
                isSearchMode ? '검색 초기화' : '번호판 검색',
                style: TextStyle(
                  color: isSearchMode ? cs.tertiary : cs.onSurface,
                  fontWeight: FontWeight.w700,
                ),
              ),
              style: baseStyle,
            ),
          ),
        ),
      ),
    );
  }
}
