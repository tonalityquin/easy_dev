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
import '../departure_completed_bottom_sheet.dart';
import 'widgets/parking_completed_status_bottom_sheet.dart';
import 'widgets/set_departure_request_dialog.dart';
import '../../../widgets/dialog/plate_remove_dialog.dart';

class ParkingCompletedControlButtons extends StatelessWidget {
  final bool isParkingAreaMode;
  final bool isStatusMode;
  final bool isLocationPickerMode;
  final bool isSorted;
  final bool isLocked;
  final VoidCallback onToggleLock;
  final VoidCallback showSearchDialog;
  final VoidCallback resetParkingAreaFilter;
  final VoidCallback toggleSortIcon;
  final Function(BuildContext context, String plateNumber, String area) handleEntryParkingRequest;
  final Function(BuildContext context) handleDepartureRequested;

  const ParkingCompletedControlButtons({
    super.key,
    required this.isParkingAreaMode,
    required this.isStatusMode,
    required this.isLocationPickerMode,
    required this.isSorted,
    required this.isLocked,
    required this.onToggleLock,
    required this.showSearchDialog,
    required this.resetParkingAreaFilter,
    required this.toggleSortIcon,
    required this.handleEntryParkingRequest,
    required this.handleDepartureRequested,
  });

  @override
  Widget build(BuildContext context) {
    return Consumer<PlateState>(
      builder: (context, plateState, _) {
        final userName = context.read<UserState>().name;
        final selectedPlate = plateState.getSelectedPlate(PlateType.parkingCompleted, userName);
        final isPlateSelected = selectedPlate != null && selectedPlate.isSelected;

        return BottomNavigationBar(
          type: BottomNavigationBarType.fixed,
          backgroundColor: Colors.white,
          elevation: 0,
          selectedFontSize: 12,
          unselectedFontSize: 12,
          iconSize: 24,
          selectedItemColor: Theme.of(context).primaryColor,
          unselectedItemColor: Colors.grey[700],
          items: isLocationPickerMode || isStatusMode
              ? [
            BottomNavigationBarItem(
              icon: Icon(isLocked ? Icons.lock : Icons.lock_open),
              label: '화면 잠금',
            ),
            const BottomNavigationBarItem(
              icon: Icon(Icons.search),
              label: '번호판 검색',
            ),
            const BottomNavigationBarItem(
              icon: Icon(Icons.directions_car),
              label: '출차 완료',
            ),
          ]
              : [
            BottomNavigationBarItem(
              icon: AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                transitionBuilder: (child, animation) => ScaleTransition(scale: animation, child: child),
                child: isPlateSelected
                    ? (selectedPlate.isLockedFee
                    ? const Icon(Icons.lock_open, key: ValueKey('unlock'), color: Colors.grey)
                    : const Icon(Icons.lock, key: ValueKey('lock'), color: Colors.grey))
                    : Icon(Icons.refresh, key: const ValueKey('refresh'), color: Colors.grey[700]),
              ),
              label: isPlateSelected ? (selectedPlate.isLockedFee ? '정산 취소' : '사전 정산') : '채팅하기',
            ),
            BottomNavigationBarItem(
              icon: Icon(
                isPlateSelected ? Icons.check_circle : Icons.search,
                color: isPlateSelected ? Colors.green[600] : Colors.grey[700],
              ),
              label: isPlateSelected ? '출차 요청' : '번호판 검색',
            ),
            BottomNavigationBarItem(
              icon: AnimatedRotation(
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
              label: isPlateSelected ? '상태 수정' : (isSorted ? '최신순' : '오래된 순'),
            ),
          ],
          onTap: (index) async {
            if (isLocationPickerMode || isStatusMode) {
              if (index == 0) {
                onToggleLock();
              } else if (index == 1) {
                showSearchDialog();
              } else if (index == 2) {
                showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  backgroundColor: Colors.transparent,
                  builder: (context) => const DepartureCompletedBottomSheet(),
                );
              }
              return;
            }

            if (!isParkingAreaMode || !isPlateSelected) {
              if (index == 0 || index == 1) {
                showSearchDialog();
              } else if (index == 2) {
                toggleSortIcon();
              }
              return;
            }

            final repo = context.read<PlateRepository>();
            final billingType = selectedPlate.billingType;
            final now = DateTime.now();
            final entryTime = selectedPlate.requestTime.toUtc().millisecondsSinceEpoch ~/ 1000;
            final currentTime = now.toUtc().millisecondsSinceEpoch ~/ 1000;
            final firestore = FirebaseFirestore.instance;
            final documentId = selectedPlate.id;

            if (index == 0) {
              // === [추가] 0원 규칙: basicAmount==0 && addAmount==0
              final bool isZeroZero =
                  ((selectedPlate.basicAmount ?? 0) == 0) && ((selectedPlate.addAmount ?? 0) == 0);

              // 0원 + 이미 잠금 -> 해제 금지 (안내 후 종료)
              if (isZeroZero && selectedPlate.isLockedFee) {
                showFailedSnackbar(context, '이 차량은 0원 규칙으로 잠금 상태이며 해제할 수 없습니다.');
                return;
              }

              // 0원 + 아직 잠금 아님 -> 바텀시트 생략, 자동 잠금 처리
              if (isZeroZero && !selectedPlate.isLockedFee) {
                final updatedPlate = selectedPlate.copyWith(
                  isLockedFee: true,
                  lockedAtTimeInSeconds: currentTime,
                  lockedFeeAmount: 0,
                  paymentMethod: null,
                );

                await repo.addOrUpdatePlate(documentId, updatedPlate);
                await plateState.updatePlateLocally(PlateType.parkingCompleted, updatedPlate);

                final autoLog = {
                  'action': '사전 정산(자동 잠금: 0원)',
                  'performedBy': userName,
                  'timestamp': now.toIso8601String(),
                  'lockedFee': 0,
                  'auto': true,
                };

                await firestore.collection('plates').doc(documentId).update({
                  'logs': FieldValue.arrayUnion([autoLog])
                });

                showSuccessSnackbar(context, '0원 유형이라 자동으로 잠금되었습니다.');
                return;
              }
              // === [추가 끝]

              if ((billingType ?? '').trim().isEmpty) {
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
                await plateState.updatePlateLocally(PlateType.parkingCompleted, updatedPlate);

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
                await plateState.updatePlateLocally(PlateType.parkingCompleted, updatedPlate);

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

                showSuccessSnackbar(
                  context,
                  '사전 정산 완료: ₩${result.lockedFee} (${result.paymentMethod})',
                );
              }
            } else if (index == 1) {
              showDialog(
                context: context,
                builder: (context) => SetDepartureRequestBottomSheet(
                  onConfirm: () => handleDepartureRequested(context),
                ),
              );
            } else if (index == 2) {
              await showParkingCompletedStatusBottomSheet(
                context: context,
                plate: selectedPlate,
                onRequestEntry: () => handleEntryParkingRequest(
                  context,
                  selectedPlate.plateNumber,
                  selectedPlate.area,
                ),
                onDelete: () {
                  showDialog(
                    context: context,
                    builder: (_) => PlateRemoveDialog(
                      onConfirm: () {
                        context.read<DeletePlate>().deleteFromParkingCompleted(
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
