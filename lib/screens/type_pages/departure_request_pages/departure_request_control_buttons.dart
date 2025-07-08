// ⚙️ import 생략 없이 정리
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
import 'widgets/set_departure_completed_dialog.dart';
import 'widgets/departure_request_status_dialog.dart';
import '../../../widgets/dialog/plate_remove_dialog.dart';

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
          backgroundColor: Colors.white,
          // ✅ 흰 배경 적용
          elevation: 0,
          type: BottomNavigationBarType.fixed,
          selectedItemColor: Theme.of(context).primaryColor,
          unselectedItemColor: Colors.grey[700],
          items: [
            BottomNavigationBarItem(
              icon: Tooltip(
                message: isPlateSelected ? '정산 관리' : (isSearchMode ? '검색 초기화' : '번호판 검색'),
                child: Icon(
                  isPlateSelected
                      ? (selectedPlate.isLockedFee ? Icons.lock_open : Icons.lock)
                      : (isSearchMode ? Icons.cancel : Icons.search),
                  color: isPlateSelected ? Colors.grey[700] : (isSearchMode ? Colors.orange[600] : Colors.grey[700]),
                ),
              ),
              label: isPlateSelected ? '정산 관리' : (isSearchMode ? '검색 초기화' : '검색'),
            ),
            BottomNavigationBarItem(
              icon: Tooltip(
                message: isPlateSelected ? '출차 완료 처리' : (isParkingAreaMode ? '구역 초기화' : '주차 구역 선택'),
                child: Icon(
                  isPlateSelected ? Icons.check_circle : (isParkingAreaMode ? Icons.clear : Icons.local_parking),
                  color:
                      isPlateSelected ? Colors.green[600] : (isParkingAreaMode ? Colors.orange[600] : Colors.grey[700]),
                ),
              ),
              label: isPlateSelected ? '출차' : (isParkingAreaMode ? '초기화' : '구역 선택'),
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
                      color: Colors.grey[700],
                    ),
                  ),
                ),
              ),
              label: isPlateSelected ? '상태 수정' : (isSorted ? '최신순' : '오래된순'),
            ),
          ],
          onTap: (index) async {
            final repo = context.read<PlateRepository>();
            final division = context.read<AreaState>().currentDivision;
            final area = context.read<AreaState>().currentArea.trim();
            final uploader = GcsJsonUploader();

            if (!isPlateSelected) {
              if (index == 0) isSearchMode ? resetSearch() : showSearchDialog();
              if (index == 1) isParkingAreaMode ? resetParkingAreaFilter() : showParkingAreaDialog();
              if (index == 2) toggleSortIcon();
              return;
            }

            if (index == 0) {
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
                await plateState.updatePlateLocally(PlateType.departureRequests, updatedPlate);

                await uploader.uploadForPlateLogTypeJson({
                  'plateNumber': selectedPlate.plateNumber,
                  'action': '사전 정산 취소',
                  'performedBy': context.read<UserState>().name,
                  'timestamp': now.toIso8601String(),
                  'billingType': billingType,
                }, selectedPlate.plateNumber, division, area);

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
                await plateState.updatePlateLocally(PlateType.departureRequests, updatedPlate);

                await uploader.uploadForPlateLogTypeJson({
                  'plateNumber': selectedPlate.plateNumber,
                  'action': '사전 정산',
                  'performedBy': context.read<UserState>().name,
                  'timestamp': now.toIso8601String(),
                  'lockedFee': result.lockedFee,
                  'paymentMethod': result.paymentMethod,
                  'billingType': billingType,
                }, selectedPlate.plateNumber, division, area);

                showSuccessSnackbar(context, '사전 정산 완료: ₩${result.lockedFee} (${result.paymentMethod})');
              }
            } else if (index == 1) {
              showDialog(
                context: context,
                builder: (_) => SetDepartureCompletedDialog(
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
                      builder: (_) => PlateRemoveDialog(
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
