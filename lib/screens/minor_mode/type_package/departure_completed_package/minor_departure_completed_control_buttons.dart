import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../enums/plate_type.dart';
import '../../../../states/plate/minor_plate_state.dart';
import '../../../../states/user/user_state.dart';
import '../../../../states/area/area_state.dart';
import 'departure_completed_plate_search_bottom_sheet/minor_departure_completed_search_bottom_sheet.dart';
import 'widgets/minor_departure_completed_status_bottom_sheet.dart';

class MinorDepartureCompletedControlButtons extends StatelessWidget {
  final bool isSearchMode;
  final VoidCallback onResetSearch;

  /// ✅ 기존 시그니처 호환 유지용
  /// - 현재 구현에서는 내부에서 바텀시트를 직접 띄우므로, 상위 hook 용도로만 남겨둡니다.
  /// - (중요) analyzer unused 경고 방지 + 기존 호출부 호환을 위해 실제로 호출합니다.
  final VoidCallback onShowSearchDialog;

  const MinorDepartureCompletedControlButtons({
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
      builder: (_) => MinorDepartureCompletedSearchBottomSheet(
        area: area,
        onSearch: (_) {}, // 이 화면에서는 no-op
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final plateState = context.watch<MinorPlateState>();
    final userName = context.read<UserState>().name;

    final selectedPlate = plateState.minorGetSelectedPlate(
      PlateType.departureCompleted,
      userName,
    );
    final isPlateSelected = selectedPlate != null && selectedPlate.isSelected;

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
                await showMinorDepartureCompletedStatusBottomSheet(
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
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              ),
            )
                : TextButton.icon(
              onPressed: isSearchMode
                  ? onResetSearch
                  : () async {
                // ✅ (호환) 상위 hook 호출(원래는 상위가 dialog 열던 용도)
                // 현재는 "호출만" 하고, 실제 검색은 이 버튼이 직접 bottomSheet로 수행
                onShowSearchDialog();

                await _openPlateSearchBottomSheet(context);
              },
              icon: Icon(
                isSearchMode ? Icons.cancel : Icons.search,
                color: isSearchMode ? cs.tertiary : cs.onSurfaceVariant,
              ),
              label: Text(
                isSearchMode ? '검색 초기화' : '번호판 검색',
                style: TextStyle(
                  color: isSearchMode ? cs.tertiary : cs.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
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
