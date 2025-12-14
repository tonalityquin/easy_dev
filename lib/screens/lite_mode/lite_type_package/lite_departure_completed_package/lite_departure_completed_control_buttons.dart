import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../enums/plate_type.dart';
import '../../../../states/plate/plate_state.dart';
import '../../../../states/user/user_state.dart';
import 'widgets/lite_departure_completed_status_bottom_sheet.dart';

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

  @override
  Widget build(BuildContext context) {
    final plateState = context.watch<PlateState>();
    final userName = context.read<UserState>().name;
    final selectedPlate =
    plateState.getSelectedPlate(PlateType.departureCompleted, userName);
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
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 10),
              ),
            )
                : TextButton.icon(
              onPressed:
              isSearchMode ? onResetSearch : onShowSearchDialog,
              icon: Icon(
                isSearchMode ? Icons.cancel : Icons.search,
                color:
                isSearchMode ? Colors.orange[600] : Colors.grey[800],
              ),
              label: Text(
                isSearchMode ? '검색 초기화' : '번호판 검색',
                style: TextStyle(
                  color: isSearchMode
                      ? Colors.orange[600]
                      : Colors.grey[800],
                  fontWeight: FontWeight.w600,
                ),
              ),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 10),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
