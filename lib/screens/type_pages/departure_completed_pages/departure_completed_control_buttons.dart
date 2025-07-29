import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../enums/plate_type.dart';
import '../../../repositories/plate/plate_repository.dart';
import '../../../states/area/area_state.dart';
import '../../../states/plate/plate_state.dart';
import '../../../states/user/user_state.dart';
import '../../../states/calendar/field_selected_date_state.dart';
import '../../../utils/snackbar_helper.dart';
import '../../../widgets/dialog/billing_bottom_sheet/billing_bottom_sheet.dart';
import 'widgets/departure_completed_status_bottom_sheet.dart';

class DepartureCompletedControlButtons extends StatelessWidget {
  final bool isSearchMode;
  final bool isSorted;
  final bool showMergedLog;
  final bool hasCalendarBeenReset;
  final VoidCallback onResetSearch;
  final VoidCallback onShowSearchDialog;
  final VoidCallback onToggleMergedLog;
  final VoidCallback onToggleCalendar;

  const DepartureCompletedControlButtons({
    super.key,
    required this.isSearchMode,
    required this.isSorted,
    required this.showMergedLog,
    required this.hasCalendarBeenReset,
    required this.onResetSearch,
    required this.onShowSearchDialog,
    required this.onToggleMergedLog,
    required this.onToggleCalendar,
  });

  @override
  Widget build(BuildContext context) {
    final plateState = context.watch<PlateState>();
    final userName = context.read<UserState>().name;
    final selectedPlate = plateState.getSelectedPlate(PlateType.departureCompleted, userName);
    final isPlateSelected = selectedPlate != null && selectedPlate.isSelected;

    final selectedDate = context.watch<FieldSelectedDateState>().selectedDate ?? DateTime.now();
    final formattedDate =
        '${selectedDate.year}-${selectedDate.month.toString().padLeft(2, '0')}-${selectedDate.day.toString().padLeft(2, '0')}';

    return BottomNavigationBar(
      backgroundColor: Colors.white,
      elevation: 0,
      type: BottomNavigationBarType.fixed,
      selectedItemColor: Theme.of(context).primaryColor,
      unselectedItemColor: Colors.grey[700],
      items: isPlateSelected
          ? [
        BottomNavigationBarItem(
          icon: Tooltip(
            message: '정산 관리',
            child: Icon(
              selectedPlate.isLockedFee ? Icons.lock_open : Icons.lock,
              color: Colors.grey[700],
            ),
          ),
          label: '정산 관리',
        ),
        BottomNavigationBarItem(
          icon: Tooltip(
            message: '상태 수정',
            child: Icon(Icons.settings, color: Colors.grey[700]),
          ),
          label: '상태 수정',
        ),
      ]
          : [
        BottomNavigationBarItem(
          icon: Tooltip(
            message: isSearchMode ? '검색 초기화' : '번호판 검색',
            child: Icon(
              isSearchMode ? Icons.cancel : Icons.search,
              color: isSearchMode ? Colors.orange[600] : Colors.grey[700],
            ),
          ),
          label: isSearchMode ? '검색 초기화' : '번호판 검색',
        ),
        BottomNavigationBarItem(
          icon: Tooltip(
            message: '날짜 선택',
            child: Icon(Icons.calendar_today, color: Colors.grey[700]),
          ),
          label: formattedDate,
        ),
      ],
      onTap: (index) async {
        if (isPlateSelected) {
          if (index == 0) {
            final billType = selectedPlate.billingType;
            if (billType == null || billType.trim().isEmpty) {
              showFailedSnackbar(context, '정산 타입이 지정되지 않아 사전 정산이 불가능합니다.');
              return;
            }

            if (selectedPlate.isLockedFee) {
              showFailedSnackbar(context, '정산 완료된 항목은 취소할 수 없습니다.');
              return;
            }

            final now = DateTime.now();
            final entryTime = selectedPlate.requestTime.toUtc().millisecondsSinceEpoch ~/ 1000;
            final currentTime = now.toUtc().millisecondsSinceEpoch ~/ 1000;

            final result = await showOnTapBillingBottomSheet(
              context: context,
              entryTimeInSeconds: entryTime,
              currentTimeInSeconds: currentTime,
              basicStandard: selectedPlate.basicStandard ?? 0,
              basicAmount: selectedPlate.basicAmount ?? 0,
              addStandard: selectedPlate.addStandard ?? 0,
              addAmount: selectedPlate.addAmount ?? 0,
            );

            if (result == null) return;

            final updatedPlate = selectedPlate.copyWith(
              isLockedFee: true,
              isSelected: false,
              lockedAtTimeInSeconds: currentTime,
              lockedFeeAmount: result.lockedFee,
              paymentMethod: result.paymentMethod,
            );

            final repo = context.read<PlateRepository>();
            final division = context.read<AreaState>().currentDivision;
            final area = context.read<AreaState>().currentArea.trim();
            final firestore = FirebaseFirestore.instance;

            await repo.addOrUpdatePlate(selectedPlate.id, updatedPlate);
            await context.read<PlateState>().updatePlateLocally(PlateType.departureCompleted, updatedPlate);

            final log = {
              'plateNumber': selectedPlate.plateNumber,
              'action': '사전 정산',
              'performedBy': userName,
              'timestamp': now.toIso8601String(),
              'lockedFee': result.lockedFee,
              'paymentMethod': result.paymentMethod,
              'billingType': billType,
              'division': division,
              'area': area,
            };

            await firestore.collection('plates').doc(selectedPlate.id).update({
              'logs': FieldValue.arrayUnion([log])
            });

            showSuccessSnackbar(context, '사전 정산 완료: ₩${result.lockedFee} (${result.paymentMethod})');
          } else if (index == 1) {
            await showDepartureCompletedStatusBottomSheet(
              context: context,
              plate: selectedPlate,
            );
          }
        } else {
          if (index == 0) {
            isSearchMode ? onResetSearch() : onShowSearchDialog();
          } else if (index == 1) {
            onToggleCalendar();
          }
        }
      },
    );
  }
}
