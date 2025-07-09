import 'package:easydev/utils/gcs_json_uploader.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../enums/plate_type.dart';
import '../../../repositories/plate/plate_repository.dart';
import '../../../states/area/area_state.dart';
import '../../../states/plate/delete_plate.dart';
import '../../../states/plate/plate_state.dart';
import '../../../states/user/user_state.dart';
import '../../../utils/snackbar_helper.dart';
import '../../../widgets/dialog/on_tap_billing_type_bottom_sheet.dart';
import '../../../widgets/dialog/confirm_cancel_fee_dialog.dart';
import 'widgets/parking_request_status_bottom_sheet.dart';

class ParkingRequestControlButtons extends StatelessWidget {
  final bool isSorted;
  final VoidCallback onSearchPressed;
  final VoidCallback onSortToggle;
  final VoidCallback onParkingCompleted;
  final VoidCallback onToggleReportDialog;

  const ParkingRequestControlButtons({
    super.key,
    required this.isSorted,
    required this.onSearchPressed,
    required this.onSortToggle,
    required this.onParkingCompleted,
    required this.onToggleReportDialog,
  });

  @override
  Widget build(BuildContext context) {
    return Consumer<PlateState>(
      builder: (context, plateState, _) {
        final userName = context.read<UserState>().name;
        final selectedPlate = plateState.getSelectedPlate(PlateType.parkingRequests, userName);
        final isPlateSelected = selectedPlate != null && selectedPlate.isSelected;
        final iconColor = Colors.grey[700];

        return BottomNavigationBar(
          backgroundColor: Colors.white,
          items: [
            BottomNavigationBarItem(
              icon: Tooltip(
                message: isPlateSelected ? '정산 관리' : '보고서 열기',
                child: isPlateSelected
                    ? Icon(Icons.lock, color: iconColor)
                    : Image.asset(
                  'assets/icons/icon_belivussnc.PNG',
                  width: 24.0,
                  height: 24.0,
                  fit: BoxFit.contain,
                ),
              ),
              label: isPlateSelected ? '정산 관리' : 'Belivus',
            ),
            BottomNavigationBarItem(
              icon: Tooltip(
                message: isPlateSelected ? '입차 완료' : '번호판 검색',
                child: isPlateSelected
                    ? Icon(Icons.check_circle, color: Colors.green[600])
                    : Icon(Icons.search, color: iconColor),
              ),
              label: isPlateSelected ? '입차' : '번호판 검색',
            ),
            BottomNavigationBarItem(
              icon: Tooltip(
                message: isPlateSelected ? '상태 수정' : '정렬 변경',
                child: AnimatedRotation(
                  turns: isSorted ? 0.5 : 0.0,
                  duration: const Duration(milliseconds: 300),
                  child: Transform.scale(
                    scaleX: isSorted ? -1 : 1,
                    child: Icon(
                      isPlateSelected ? Icons.settings : Icons.sort,
                      color: iconColor,
                    ),
                  ),
                ),
              ),
              label: isPlateSelected ? '상태 수정' : (isSorted ? '최신순' : '오래된순'),
            ),
          ],
          onTap: (index) async {
            final repo = context.read<PlateRepository>();
            final uploader = GcsJsonUploader();
            final division = context.read<AreaState>().currentDivision;
            final area = context.read<AreaState>().currentArea.trim();

            if (index == 0) {
              isPlateSelected
                  ? await _handleBillingAction(
                  context, selectedPlate, userName, repo, uploader, division, area, plateState)
                  : onToggleReportDialog();
            } else if (index == 1) {
              isPlateSelected ? onParkingCompleted() : onSearchPressed();
            } else if (index == 2) {
              if (isPlateSelected) {
                await showParkingRequestStatusBottomSheet(
                  context: context,
                  plate: selectedPlate,
                  onCancelEntryRequest: () {
                    context.read<DeletePlate>().deleteFromParkingRequest(
                      selectedPlate.plateNumber,
                      selectedPlate.area,
                    );
                    showSuccessSnackbar(context, "입차 요청이 취소되었습니다: ${selectedPlate.plateNumber}");
                  },
                  onDelete: () {},
                );
              } else {
                onSortToggle();
              }
            }
          },
        );
      },
    );
  }

  Future<void> _handleBillingAction(
      BuildContext context,
      dynamic selectedPlate,
      String userName,
      PlateRepository repo,
      GcsJsonUploader uploader,
      String division,
      String area,
      PlateState plateState,
      ) async {
    final billingType = selectedPlate.billingType;

    if (billingType == null || billingType.trim().isEmpty) {
      showFailedSnackbar(context, '정산 타입이 지정되지 않아 사전 정산이 불가능합니다.');
      return;
    }

    final now = DateTime.now();
    final entryTime = selectedPlate.requestTime.toUtc().millisecondsSinceEpoch ~/ 1000;
    final currentTime = now.toUtc().millisecondsSinceEpoch ~/ 1000;

    if (selectedPlate.isLockedFee) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (_) => const ConfirmCancelFeeDialog(),
      );
      if (confirm != true) return;

      final updatedPlate = selectedPlate.copyWith(
        isLockedFee: false,
        lockedAtTimeInSeconds: null,
        lockedFeeAmount: null,
        paymentMethod: null,
      );

      await repo.addOrUpdatePlate(selectedPlate.id, updatedPlate);
      await plateState.updatePlateLocally(PlateType.parkingRequests, updatedPlate);

      final cancelLog = {
        'plateNumber': selectedPlate.plateNumber,
        'action': '사전 정산 취소',
        'performedBy': userName,
        'timestamp': now.toIso8601String(),
        if (billingType.isNotEmpty) 'billingType': billingType,
      };

      await uploader.uploadForPlateLogTypeJson(cancelLog, selectedPlate.plateNumber, division, area);
      showSuccessSnackbar(context, '사전 정산이 취소되었습니다.');
    } else {
      final result = await showOnTapBillingTypeBottomSheet(
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
        lockedAtTimeInSeconds: currentTime,
        lockedFeeAmount: result.lockedFee,
        paymentMethod: result.paymentMethod,
      );

      await repo.addOrUpdatePlate(selectedPlate.id, updatedPlate);
      await plateState.updatePlateLocally(PlateType.parkingRequests, updatedPlate);

      final log = {
        'plateNumber': selectedPlate.plateNumber,
        'action': '사전 정산',
        'performedBy': userName,
        'timestamp': now.toIso8601String(),
        'lockedFee': result.lockedFee,
        'paymentMethod': result.paymentMethod,
        if (billingType.isNotEmpty) 'billingType': billingType,
      };

      await uploader.uploadForPlateLogTypeJson(log, selectedPlate.plateNumber, division, area);
      showSuccessSnackbar(context, '사전 정산 완료: ₩${result.lockedFee} (${result.paymentMethod})');
    }
  }
}
