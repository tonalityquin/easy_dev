import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../enums/plate_type.dart';
import '../../../repositories/plate/plate_repository.dart';
import '../../../states/plate/delete_plate.dart';
import '../../../states/plate/plate_state.dart';
import '../../../states/user/user_state.dart';
import '../../../utils/snackbar_helper.dart';

import '../../../widgets/dialog/billing_bottom_sheet/billing_bottom_sheet.dart';
import '../../../widgets/dialog/confirm_cancel_fee_dialog.dart';
import 'widgets/departure_request_status_bottom_sheet.dart';
import 'widgets/set_departure_completed_dialog.dart';
import '../../../widgets/dialog/plate_remove_dialog.dart';

class DepartureRequestControlButtons extends StatelessWidget {
  final bool isSorted;
  final bool isLocked;

  final VoidCallback showSearchDialog;
  final VoidCallback toggleSortIcon;
  final VoidCallback handleDepartureCompleted;
  final VoidCallback toggleLock;

  final Function(BuildContext context, String plateNumber, String area) handleEntryParkingRequest;
  final Function(BuildContext context, String plateNumber, String area, String location) handleEntryParkingCompleted;

  const DepartureRequestControlButtons({
    super.key,
    required this.isSorted,
    required this.isLocked,
    required this.showSearchDialog,
    required this.toggleSortIcon,
    required this.handleDepartureCompleted,
    required this.toggleLock,
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
          elevation: 0,
          type: BottomNavigationBarType.fixed,
          selectedItemColor: Theme.of(context).primaryColor,
          unselectedItemColor: Colors.grey[700],
          selectedFontSize: 12,
          unselectedFontSize: 12,
          iconSize: 24,
          items: [
            BottomNavigationBarItem(
              icon: Tooltip(
                message: isPlateSelected ? '정산 관리' : '화면 잠금',
                child: Icon(
                  isPlateSelected
                      ? Icons.payments  // 🔄 여기서 변경
                      : (isLocked ? Icons.lock : Icons.lock_open),
                  color: Colors.grey[700],
                ),
              ),
              label: isPlateSelected ? '정산 관리' : '화면 잠금',
            ),
            BottomNavigationBarItem(
              icon: Tooltip(
                message: isPlateSelected ? '출차 완료' : '번호판 검색',
                child: Icon(
                  isPlateSelected ? Icons.check_circle : Icons.search,
                  color: isPlateSelected ? Colors.green[600] : Colors.grey[700],
                ),
              ),
              label: isPlateSelected ? '출차' : '검색',
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
            final firestore = FirebaseFirestore.instance;

            if (!isPlateSelected) {
              if (index == 0) {
                toggleLock();
              } else if (index == 1) {
                showSearchDialog();
              } else if (index == 2) {
                toggleSortIcon();
              }
              return;
            }

            final billingType = selectedPlate.billingType ?? '';
            final now = DateTime.now();
            final currentTime = now.toUtc().millisecondsSinceEpoch ~/ 1000;
            final entryTime = selectedPlate.requestTime.toUtc().millisecondsSinceEpoch ~/ 1000;
            final documentId = selectedPlate.id;

            if (index == 0) {
              if (billingType.trim().isEmpty) {
                showFailedSnackbar(context, '정산 타입이 지정되지 않아 사전 정산이 불가능합니다.');
                return;
              }

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

                await repo.addOrUpdatePlate(documentId, updatedPlate);
                await plateState.updatePlateLocally(PlateType.departureRequests, updatedPlate);

                final cancelLog = {
                  'action': '사전 정산 취소',
                  'performedBy': userName,
                  'timestamp': now.toIso8601String(),
                };

                await firestore.collection('plates').doc(documentId).update({
                  'logs': FieldValue.arrayUnion([cancelLog])
                });

                showSuccessSnackbar(context, '사전 정산이 취소되었습니다.');
              } else {
                final result = await showOnTapBillingBottomSheet(
                  context: context,
                  entryTimeInSeconds: entryTime,
                  currentTimeInSeconds: currentTime,
                  basicStandard: selectedPlate.basicStandard ?? 0,
                  basicAmount: selectedPlate.basicAmount ?? 0,
                  addStandard: selectedPlate.addStandard ?? 0,
                  addAmount: selectedPlate.addAmount ?? 0,
                  billingType: selectedPlate.billingType ?? '변동',
                  regularAmount: selectedPlate.regularAmount,
                  regularDurationHours: selectedPlate.regularDurationHours,
                );
                if (result == null) return;

                final updatedPlate = selectedPlate.copyWith(
                  isLockedFee: true,
                  lockedAtTimeInSeconds: currentTime,
                  lockedFeeAmount: result.lockedFee,
                  paymentMethod: result.paymentMethod,
                );

                await repo.addOrUpdatePlate(documentId, updatedPlate);
                await plateState.updatePlateLocally(PlateType.departureRequests, updatedPlate);

                final log = {
                  'action': '사전 정산',
                  'performedBy': userName,
                  'timestamp': now.toIso8601String(),
                  'lockedFee': result.lockedFee,
                  'paymentMethod': result.paymentMethod,
                  if (result.reason != null && result.reason!.trim().isNotEmpty)
                    'reason': result.reason!.trim(), // ★ 사유 저장
                };

                await firestore.collection('plates').doc(documentId).update({
                  'logs': FieldValue.arrayUnion([log])
                });

                showSuccessSnackbar(context, '사전 정산 완료: ₩${result.lockedFee} (${result.paymentMethod})');
              }
            } else if (index == 1) {
              showDialog(
                context: context,
                builder: (_) => SetDepartureCompletedBottomSheet(
                  onConfirm: () => handleDepartureCompleted(),
                ),
              );
            } else if (index == 2) {
              await showDepartureRequestStatusBottomSheet(
                context: context,
                plate: selectedPlate,
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
              );
            }
          },
        );
      },
    );
  }
}
