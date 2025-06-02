// ⚙️ import 생략 없이 정리
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../enums/plate_type.dart';
import '../../../repositories/plate/plate_repository.dart';
import '../../../states/area/area_state.dart';
import '../../../states/plate/delete_plate.dart';
import '../../../states/plate/plate_state.dart';
import '../../../states/user/user_state.dart';
import '../../../utils/gcs_uploader.dart';
import '../../../utils/snackbar_helper.dart';
import '../../../widgets/dialog/adjustment_type_confirm_dialog.dart';
import '../../../widgets/dialog/confirm_cancel_fee_dialog.dart';
import '../../../widgets/dialog/departure_completed_confirm_dialog.dart';
import '../../../widgets/dialog/departure_request_status_dialog.dart';
import '../../../widgets/dialog/parking_request_delete_dialog.dart';

class DepartureRequestControlButtons extends StatelessWidget {
  final bool isSearchMode;
  final bool isParkingAreaMode;
  final bool isSorted;

  final VoidCallback showSearchDialog;
  final VoidCallback resetSearch;
  final VoidCallback showParkingAreaDialog;
  final VoidCallback resetParkingAreaFilter;
  final VoidCallback toggleSortIcon;

  final Function(BuildContext context) handleDepartureCompleted;
  final Function(BuildContext context, String plateNumber, String area) handleEntryParkingRequest;
  final Function(BuildContext context, String plateNumber, String area, String location) handleEntryParkingCompleted;

  const DepartureRequestControlButtons({
    super.key,
    required this.isSearchMode,
    required this.isParkingAreaMode,
    required this.isSorted,
    required this.showSearchDialog,
    required this.resetSearch,
    required this.showParkingAreaDialog,
    required this.resetParkingAreaFilter,
    required this.toggleSortIcon,
    required this.handleDepartureCompleted,
    required this.handleEntryParkingRequest,
    required this.handleEntryParkingCompleted,
  });

  @override
  Widget build(BuildContext context) {
    return Consumer<PlateState>(
      builder: (context, plateState, _) {
        final userName = context.read<UserState>().name;
        final selectedPlate = plateState.getSelectedPlate(PlateType.departureRequests, userName);
        final isPlateSelected = selectedPlate != null && selectedPlate.isSelected;

        return BottomNavigationBar(
          items: [
            BottomNavigationBarItem(
              icon: AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                transitionBuilder: (child, animation) => ScaleTransition(scale: animation, child: child),
                child: isPlateSelected
                    ? (selectedPlate.isLockedFee
                        ? const Icon(Icons.lock_open, key: ValueKey('unlock'), color: Colors.grey)
                        : const Icon(Icons.lock, key: ValueKey('lock'), color: Colors.grey))
                    : Icon(
                        isSearchMode ? Icons.cancel : Icons.search,
                        key: ValueKey(isSearchMode),
                        color: isSearchMode ? Colors.orange : Colors.grey,
                      ),
              ),
              label: isPlateSelected
                  ? (selectedPlate.isLockedFee ? '정산 취소' : '사전 정산')
                  : (isSearchMode ? '검색 초기화' : '번호판 검색'),
            ),
            BottomNavigationBarItem(
              icon: AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                transitionBuilder: (child, animation) => ScaleTransition(scale: animation, child: child),
                child: isPlateSelected
                    ? const Icon(Icons.check_circle, key: ValueKey('selected'), color: Colors.green)
                    : Icon(
                        isParkingAreaMode ? Icons.clear : Icons.local_parking,
                        key: ValueKey(isParkingAreaMode),
                        color: isParkingAreaMode ? Colors.orange : Colors.grey,
                      ),
              ),
              label: isPlateSelected ? '출차 완료' : (isParkingAreaMode ? '구역 초기화' : '주차 구역'),
            ),
            BottomNavigationBarItem(
              icon: AnimatedRotation(
                turns: isSorted ? 0.5 : 0.0,
                duration: const Duration(milliseconds: 300),
                child: Transform.scale(
                  scaleX: isSorted ? -1 : 1,
                  child: Icon(isPlateSelected ? Icons.settings : Icons.sort),
                ),
              ),
              label: isPlateSelected ? '상태 수정' : (isSorted ? '최신순' : '오래된순'),
            ),
          ],
          onTap: (index) async {
            final repo = context.read<PlateRepository>();
            final division = context.read<AreaState>().currentDivision;
            final area = context.read<AreaState>().currentArea.trim();
            final uploader = GCSUploader();

            if (!isPlateSelected) {
              if (index == 0) isSearchMode ? resetSearch() : showSearchDialog();
              if (index == 1) isParkingAreaMode ? resetParkingAreaFilter() : showParkingAreaDialog();
              if (index == 2) toggleSortIcon();
              return;
            }

            if (index == 0) {
              final adjustmentType = selectedPlate.adjustmentType;
              if (adjustmentType == null || adjustmentType.trim().isEmpty) {
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
                await plateState.updatePlateLocally(PlateType.departureRequests, updatedPlate);

                await uploader.uploadLogJson({
                  'plateNumber': selectedPlate.plateNumber,
                  'action': '사전 정산 취소',
                  'performedBy': context.read<UserState>().name,
                  'timestamp': now.toIso8601String(),
                  'adjustmentType': adjustmentType,
                }, selectedPlate.plateNumber, division, area);

                showSuccessSnackbar(context, '사전 정산이 취소되었습니다.');
              } else {
                final result = await showAdjustmentTypeConfirmDialog(
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
                await plateState.updatePlateLocally(PlateType.departureRequests, updatedPlate);

                await uploader.uploadLogJson({
                  'plateNumber': selectedPlate.plateNumber,
                  'action': '사전 정산',
                  'performedBy': context.read<UserState>().name,
                  'timestamp': now.toIso8601String(),
                  'lockedFee': result.lockedFee,
                  'paymentMethod': result.paymentMethod,
                  'adjustmentType': adjustmentType,
                }, selectedPlate.plateNumber, division, area);

                showSuccessSnackbar(context, '사전 정산 완료: ₩${result.lockedFee} (${result.paymentMethod})');
              }
            } else if (index == 1) {
              showDialog(
                context: context,
                builder: (_) => DepartureCompletedConfirmDialog(
                  onConfirm: () => handleDepartureCompleted(context),
                ),
              );
            } else if (index == 2) {
              showDialog(
                context: context,
                builder: (_) => DepartureRequestStatusDialog(
                  plate: selectedPlate,
                  plateNumber: selectedPlate.plateNumber,
                  area: selectedPlate.area,
                  onRequestEntry: () => handleEntryParkingRequest(
                    context,
                    selectedPlate.plateNumber,
                    selectedPlate.area,
                  ),
                  onCompleteEntry: () => handleEntryParkingCompleted(
                    context,
                    selectedPlate.plateNumber,
                    selectedPlate.area,
                    selectedPlate.location,
                  ),
                  onDelete: () {
                    showDialog(
                      context: context,
                      builder: (_) => ParkingRequestDeleteDialog(
                        onConfirm: () {
                          context.read<DeletePlate>().deleteFromDepartureRequest(
                                selectedPlate.plateNumber,
                                selectedPlate.area,
                              );
                          showSuccessSnackbar(context, "삭제 완료: ${selectedPlate.plateNumber}");
                        },
                      ),
                    );
                  },
                ),
              );
            }
          },
        );
      },
    );
  }
}
