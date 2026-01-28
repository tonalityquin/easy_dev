import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../enums/plate_type.dart';
import '../../../../states/plate/triple_plate_state.dart';
import '../../../../states/user/user_state.dart';
import '../../../../states/area/area_state.dart';
import 'departure_completed_plate_search_bottom_sheet/triple_departure_completed_search_bottom_sheet.dart';
import 'widgets/triple_departure_completed_status_bottom_sheet.dart';

class TripleDepartureCompletedControlButtons extends StatelessWidget {
  final bool isSearchMode;
  final VoidCallback onResetSearch;

  /// ✅ 시그니처 호환 유지
  /// - 기존 상위에서 callback을 넘기던 구조 유지
  /// - 이 위젯 내부에서도 검색 바텀시트를 직접 열고, callback은 "부수효과(로그/추적 등)" 용도로 호출
  final VoidCallback onShowSearchDialog;

  const TripleDepartureCompletedControlButtons({
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
      builder: (_) => TripleDepartureCompletedSearchBottomSheet(
        area: area,
        onSearch: (_) {}, // ✅ 이 화면은 별도 상태 토글 없음
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final plateState = context.watch<TriplePlateState>();
    final userName = context.read<UserState>().name;

    final selectedPlate = plateState.tripleGetSelectedPlate(
      PlateType.departureCompleted,
      userName,
    );
    final isPlateSelected = selectedPlate != null && selectedPlate.isSelected;

    Future<void> handleSearchPressed() async {
      // ✅ 검색 모드면 reset, 아니면 내부에서 바텀시트를 직접 열기
      if (isSearchMode) {
        onResetSearch();
        return;
      }

      await _openPlateSearchBottomSheet(context);

      // ✅ 기존 시그니처 호환(로그/추적 등 용도)
      onShowSearchDialog();
    }

    return BottomAppBar(
      color: cs.surface,
      elevation: 0,
      child: SafeArea(
        top: false,
        child: Container(
          height: 56,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(color: cs.outlineVariant.withOpacity(0.85), width: 1),
            ),
          ),
          child: Center(
            child: isPlateSelected
                ? TextButton.icon(
              onPressed: () async {
                await showTripleDepartureCompletedStatusBottomSheet(
                  context: context,
                  plate: selectedPlate,
                  performedBy: userName,
                );
              },
              icon: Icon(Icons.settings, color: cs.primary),
              label: Text(
                '상태 수정',
                style: TextStyle(
                  color: cs.onSurface,
                  fontWeight: FontWeight.w900,
                ),
              ),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                foregroundColor: cs.onSurface,
                overlayColor: cs.outlineVariant.withOpacity(0.12),
              ),
            )
                : TextButton.icon(
              onPressed: () async => handleSearchPressed(),
              icon: Icon(
                isSearchMode ? Icons.cancel : Icons.search,
                color: isSearchMode ? cs.error : cs.primary,
              ),
              label: Text(
                isSearchMode ? '검색 초기화' : '번호판 검색',
                style: TextStyle(
                  color: cs.onSurface,
                  fontWeight: FontWeight.w900,
                ),
              ),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                foregroundColor: cs.onSurface,
                overlayColor: cs.outlineVariant.withOpacity(0.12),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
