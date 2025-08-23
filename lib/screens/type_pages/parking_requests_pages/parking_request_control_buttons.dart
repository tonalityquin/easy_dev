import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../enums/plate_type.dart';
import '../../../repositories/plate/plate_repository.dart';
import '../../../states/area/area_state.dart';
import '../../../states/plate/delete_plate.dart';
import '../../../states/plate/plate_state.dart';
import '../../../states/user/user_state.dart';
import '../../../utils/snackbar_helper.dart';
import '../../../widgets/dialog/billing_bottom_sheet/billing_bottom_sheet.dart';
import '../../../widgets/dialog/confirm_cancel_fee_dialog.dart';
import 'widgets/parking_request_status_bottom_sheet.dart';

class ParkingRequestControlButtons extends StatelessWidget {
  final bool isSorted;
  final bool isLocked;
  final VoidCallback onSearchPressed;
  final VoidCallback onSortToggle;
  final VoidCallback onParkingCompleted;
  final VoidCallback onToggleLock;

  const ParkingRequestControlButtons({
    super.key,
    required this.isSorted,
    required this.isLocked,
    required this.onSearchPressed,
    required this.onSortToggle,
    required this.onParkingCompleted,
    required this.onToggleLock,
  });

  @override
  Widget build(BuildContext context) {
    return Consumer<PlateState>(
      builder: (context, plateState, _) {
        final userName = context.read<UserState>().name;
        final selectedPlate = plateState.getSelectedPlate(PlateType.parkingRequests, userName);
        final isPlateSelected = selectedPlate != null && selectedPlate.isSelected;

        return BottomNavigationBar(
          type: BottomNavigationBarType.fixed,
          backgroundColor: Colors.white,
          elevation: 0,
          selectedFontSize: 12,
          unselectedFontSize: 12,
          iconSize: 24,
          selectedItemColor: Colors.black,
          unselectedItemColor: Colors.grey[700],
          items: [
            BottomNavigationBarItem(
              icon: Tooltip(
                message: isPlateSelected ? '정산 관리' : '화면 잠금',
                child: Icon(
                  isPlateSelected
                      ? Icons.payments
                      : (isLocked ? Icons.lock : Icons.lock_open),
                  color: Colors.grey[700],
                ),
              ),
              label: isPlateSelected ? '정산 관리' : '화면 잠금',
            ),
            BottomNavigationBarItem(
              icon: Tooltip(
                message: isPlateSelected ? '입차 완료' : '번호판 검색',
                child: isPlateSelected
                    ? Icon(Icons.check_circle, color: Colors.green[600])
                    : Icon(Icons.search, color: Colors.grey[700]),
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

            if (index == 0) {
              if (isPlateSelected) {
                await _handleBillingAction(
                  context,
                  selectedPlate,
                  userName,
                  repo,
                  division,
                  area,
                );
              } else {
                onToggleLock();
              }
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
      String division,
      String area,
      ) async {
    final billingType = selectedPlate.billingType;
    if (billingType == null || billingType.trim().isEmpty) {
      showFailedSnackbar(context, '정산 타입이 지정되지 않아 사전 정산이 불가능합니다.');
      return;
    }

    final now = DateTime.now();
    final entryTime = selectedPlate.requestTime.toUtc().millisecondsSinceEpoch ~/ 1000;
    final currentTime = now.toUtc().millisecondsSinceEpoch ~/ 1000;
    final documentId = selectedPlate.id;

    final firestore = FirebaseFirestore.instance;

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
      context.read<PlateState>().updatePlateLocally(PlateType.parkingRequests, updatedPlate);

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
      context.read<PlateState>().updatePlateLocally(PlateType.parkingRequests, updatedPlate);

      final log = {
        'action': '사전 정산',
        'performedBy': userName,
        'timestamp': now.toIso8601String(),
        'lockedFee': result.lockedFee,
        'paymentMethod': result.paymentMethod,
      };

      await firestore.collection('plates').doc(documentId).update({
        'logs': FieldValue.arrayUnion([log])
      });

      showSuccessSnackbar(context, '사전 정산 완료: ₩${result.lockedFee} (${result.paymentMethod})');
    }
  }
}
