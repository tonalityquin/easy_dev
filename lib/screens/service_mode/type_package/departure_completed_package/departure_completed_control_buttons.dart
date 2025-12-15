import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../enums/plate_type.dart';
import '../../../../states/plate/lite_plate_state.dart';
import '../../../../states/user/user_state.dart';
import '../../../../states/area/area_state.dart';
import 'departure_completed_plate_search_bottom_sheet/departure_completed_search_bottom_sheet.dart';
import 'departure_completed_plate_search_bottom_sheet/departure_completed_status_bottom_sheet.dart';

class DepartureCompletedControlButtons extends StatelessWidget {
  final bool isSearchMode;
  final VoidCallback onResetSearch;
  final VoidCallback onShowSearchDialog;

  const DepartureCompletedControlButtons({
    super.key,
    required this.isSearchMode,
    required this.onResetSearch,
    required this.onShowSearchDialog,
  });

  Future<void> _openPlateSearchBottomSheet(BuildContext context) async {
    final area = context.read<AreaState>().currentArea.trim();

    // area가 비어있으면 검색 불가(방어)
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
      builder: (_) => DepartureCompletedSearchBottomSheet(
        area: area,
        // ✅ 이 화면에서는 별도 상태 토글이 없으므로 no-op
        onSearch: (_) {},
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final plateState = context.watch<LitePlateState>();
    final userName = context.read<UserState>().name;

    final selectedPlate = plateState.getSelectedPlate(
      PlateType.departureCompleted,
      userName,
    );
    final isPlateSelected = selectedPlate != null && selectedPlate.isSelected;

    return BottomAppBar(
      color: Colors.white,
      elevation: 0,
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 56,
          child: Center(
            child: isPlateSelected
                ? TextButton.icon(
              onPressed: () async {
                await showDepartureCompletedStatusBottomSheet(
                  context: context,
                  plate: selectedPlate,
                  performedBy: userName, // ✅ 추가 반영
                );
              },
              icon: const Icon(Icons.settings, color: Colors.black87),
              label: const Text(
                '상태 수정',
                style: TextStyle(
                  color: Colors.black87,
                  fontWeight: FontWeight.w600,
                ),
              ),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              ),
            )
                : TextButton.icon(
              onPressed: isSearchMode
                  ? onResetSearch
                  : () async {
                // ✅ 기존: onShowSearchDialog (상위에서 구현 필요)
                // ✅ 변경: 컨트롤 버튼에서 직접 검색 바텀시트를 띄워 기능 복구
                await _openPlateSearchBottomSheet(context);
              },
              icon: Icon(
                isSearchMode ? Icons.cancel : Icons.search,
                color: isSearchMode ? Colors.orange[600] : Colors.grey[800],
              ),
              label: Text(
                isSearchMode ? '검색 초기화' : '번호판 검색',
                style: TextStyle(
                  color: isSearchMode ? Colors.orange[600] : Colors.grey[800],
                  fontWeight: FontWeight.w600,
                ),
              ),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
