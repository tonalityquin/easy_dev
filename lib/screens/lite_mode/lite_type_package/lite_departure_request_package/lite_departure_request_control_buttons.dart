// lib/screens/type_pages/departure_requests_package/departure_request_control_buttons.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // HapticFeedback
import 'package:provider/provider.dart';

import '../../../../enums/plate_type.dart';
import '../../../../repositories/plate_repo_services/plate_repository.dart';
import '../../../../states/plate/delete_plate.dart';
import '../../../../states/plate/plate_state.dart';
import '../../../../states/user/user_state.dart';
import '../../../../utils/snackbar_helper.dart';

import '../../../../widgets/dialog/billing_bottom_sheet/billing_bottom_sheet.dart';
import '../../../../widgets/dialog/confirm_cancel_fee_dialog.dart';
import 'widgets/lite_departure_request_status_bottom_sheet.dart';
import 'widgets/lite_set_departure_completed_dialog.dart';
import '../../../../widgets/dialog/plate_remove_dialog.dart';

/// Deep Blue 팔레트 + 상태 강조 색
class _Palette {
  static const base = Color(0xFF0D47A1);
  static const dark = Color(0xFF09367D);
  static const danger = Color(0xFFD32F2F);
  static const success = Color(0xFF2E7D32);
}

class DepartureRequestControlButtons extends StatelessWidget {
  final bool isSorted;
  final bool isLocked;

  final VoidCallback showSearchDialog;
  final VoidCallback toggleSortIcon;
  final VoidCallback handleDepartureCompleted;
  final VoidCallback toggleLock;

  final Function(BuildContext context, String plateNumber, String area)
  handleEntryParkingRequest;
  final Function(
      BuildContext context,
      String plateNumber,
      String area,
      String location,
      ) handleEntryParkingCompleted;

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
    final Color selectedItemColor = _Palette.base;
    final Color unselectedItemColor = _Palette.dark.withOpacity(.55);
    final Color muted = _Palette.dark.withOpacity(.60);

    return Consumer<PlateState>(
      builder: (context, plateState, _) {
        final userName = context.read<UserState>().name;

        final selectedPlate = plateState.getSelectedPlate(
          PlateType.departureRequests,
          userName,
        );
        final isPlateSelected =
            selectedPlate != null && selectedPlate.isSelected;

        return BottomNavigationBar(
          backgroundColor: Colors.white,
          elevation: 0,
          type: BottomNavigationBarType.fixed,
          selectedItemColor: selectedItemColor,
          unselectedItemColor: unselectedItemColor,
          selectedFontSize: 12,
          unselectedFontSize: 12,
          iconSize: 24,
          items: [
            BottomNavigationBarItem(
              icon: Tooltip(
                message: isPlateSelected ? '정산 관리' : '화면 잠금',
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  transitionBuilder: (child, anim) =>
                      ScaleTransition(scale: anim, child: child),
                  child: isPlateSelected
                      ? Icon(
                    Icons.payments,
                    key: const ValueKey('payments'),
                    color: muted, // 기존 디자인 유지
                  )
                      : (isLocked
                      ? Icon(
                    Icons.lock,
                    key: const ValueKey('locked'),
                    color: muted,
                  )
                      : Icon(
                    Icons.lock_open,
                    key: const ValueKey('unlocked'),
                    color: muted,
                  )),
                ),
              ),
              label: isPlateSelected ? '정산 관리' : '화면 잠금',
            ),
            BottomNavigationBarItem(
              icon: Tooltip(
                message: isPlateSelected ? '출차 완료' : '번호판 검색',
                child: Icon(
                  isPlateSelected ? Icons.check_circle : Icons.search,
                  color: isPlateSelected ? _Palette.success : _Palette.danger,
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
                      color: muted,
                    ),
                  ),
                ),
              ),
              label: isPlateSelected ? '상태 수정' : (isSorted ? '최신순' : '오래된순'),
            ),
          ],
          onTap: (index) async {
            HapticFeedback.selectionClick();

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

            final plate = selectedPlate;
            final plateState = context.read<PlateState>();
            final userName = context.read<UserState>().name;
            final now = DateTime.now();
            final currentTime = now.toUtc().millisecondsSinceEpoch ~/ 1000;
            final entryTime =
                plate.requestTime.toUtc().millisecondsSinceEpoch ~/ 1000;
            final documentId = plate.id;

            if (index == 0) {
              final type = (plate.billingType ?? '').trim();
              final isFixed = type == '고정';
              final isZeroAutoLock =
                  (((plate.basicAmount ?? 0) == 0) &&
                      ((plate.addAmount ?? 0) == 0)) ||
                      (isFixed && (plate.regularAmount ?? 0) == 0);

              if (isZeroAutoLock && plate.isLockedFee) {
                showFailedSnackbar(
                    context, '이 차량은 0원 규칙으로 잠금 상태이며 해제할 수 없습니다.');
                return;
              }

              if (isZeroAutoLock && !plate.isLockedFee) {
                final updatedPlate = plate.copyWith(
                  isLockedFee: true,
                  lockedAtTimeInSeconds: currentTime,
                  lockedFeeAmount: 0,
                  paymentMethod: null,
                  isSelected: false,
                  selectedBy: null,
                );
                try {
                  await repo.addOrUpdatePlate(documentId, updatedPlate);
                  await plateState.updatePlateLocally(
                    PlateType.departureRequests,
                    updatedPlate,
                  );

                  final autoLog = {
                    'action': '사전 정산(자동 잠금: 0원)',
                    'performedBy': userName,
                    'timestamp': now.toIso8601String(),
                    'lockedFee': 0,
                    'auto': true,
                  };

                  // ✅ 서버에서 selectedBy 흔적 제거 + 로그 동시 기록
                  await firestore.collection('plates').doc(documentId).update({
                    'isSelected': false,
                    'selectedBy': FieldValue.delete(),
                    'logs': FieldValue.arrayUnion([autoLog]),
                  });

                  HapticFeedback.mediumImpact();
                  showSuccessSnackbar(context, '0원 유형이라 자동으로 잠금되었습니다.');

                  if (context.mounted) {
                    context.read<PlateState>().clearPendingIfMatches(documentId);
                  }
                } catch (e, st) {
                  debugPrint('auto-lock(0원) error: $e\n$st');
                  showFailedSnackbar(context, '자동 잠금 처리에 실패했습니다. 다시 시도해 주세요.');
                }
                return;
              }

              final billingType = plate.billingType ?? '';
              if (billingType.trim().isEmpty) {
                showFailedSnackbar(
                    context, '정산 타입이 지정되지 않아 사전 정산이 불가능합니다.');
                return;
              }

              if (plate.isLockedFee) {
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (_) => const ConfirmCancelFeeDialog(),
                );
                if (confirm != true) return;

                final updatedPlate = plate.copyWith(
                  isLockedFee: false,
                  lockedAtTimeInSeconds: null,
                  lockedFeeAmount: null,
                  paymentMethod: null,
                  isSelected: false,
                  selectedBy: null,
                );

                try {
                  await repo.addOrUpdatePlate(documentId, updatedPlate);
                  await plateState.updatePlateLocally(
                    PlateType.departureRequests,
                    updatedPlate,
                  );

                  final cancelLog = {
                    'action': '사전 정산 취소',
                    'performedBy': userName,
                    'timestamp': now.toIso8601String(),
                  };

                  // ✅ 서버에서 selectedBy 흔적 제거 + 로그 동시 기록
                  await firestore.collection('plates').doc(documentId).update({
                    'isSelected': false,
                    'selectedBy': FieldValue.delete(),
                    'logs': FieldValue.arrayUnion([cancelLog]),
                  });

                  HapticFeedback.mediumImpact();
                  showSuccessSnackbar(context, '사전 정산이 취소되었습니다.');

                  if (context.mounted) {
                    context.read<PlateState>().clearPendingIfMatches(documentId);
                  }
                } catch (e, st) {
                  debugPrint('unlock(cancel fee) error: $e\n$st');
                  showFailedSnackbar(context, '사전 정산 취소 중 오류가 발생했습니다.');
                }
              } else {
                final result = await showOnTapBillingBottomSheet(
                  context: context,
                  entryTimeInSeconds: entryTime,
                  currentTimeInSeconds: currentTime,
                  basicStandard: plate.basicStandard ?? 0,
                  basicAmount: plate.basicAmount ?? 0,
                  addStandard: plate.addStandard ?? 0,
                  addAmount: plate.addAmount ?? 0,
                  billingType: plate.billingType ?? '변동',
                  regularAmount: plate.regularAmount,
                  regularDurationHours: plate.regularDurationHours,
                );
                if (result == null) return;

                final updatedPlate = plate.copyWith(
                  isLockedFee: true,
                  lockedAtTimeInSeconds: currentTime,
                  lockedFeeAmount: result.lockedFee,
                  paymentMethod: result.paymentMethod,
                  isSelected: false,
                  selectedBy: null,
                );

                try {
                  await repo.addOrUpdatePlate(documentId, updatedPlate);
                  await plateState.updatePlateLocally(
                    PlateType.departureRequests,
                    updatedPlate,
                  );

                  final log = {
                    'action': '사전 정산',
                    'performedBy': userName,
                    'timestamp': now.toIso8601String(),
                    'lockedFee': result.lockedFee,
                    'paymentMethod': result.paymentMethod,
                    if (result.reason != null &&
                        result.reason!.trim().isNotEmpty)
                      'reason': result.reason!.trim(),
                  };

                  // ✅ 서버에서 selectedBy 흔적 제거 + 로그 동시 기록
                  await firestore.collection('plates').doc(documentId).update({
                    'isSelected': false,
                    'selectedBy': FieldValue.delete(),
                    'logs': FieldValue.arrayUnion([log]),
                  });

                  HapticFeedback.mediumImpact();
                  showSuccessSnackbar(
                    context,
                    '사전 정산 완료: ₩${result.lockedFee} (${result.paymentMethod})',
                  );

                  if (context.mounted) {
                    context.read<PlateState>().clearPendingIfMatches(documentId);
                  }
                } catch (e, st) {
                  debugPrint('lock(fee) error: $e\n$st');
                  showFailedSnackbar(context, '사전 정산 처리 중 오류가 발생했습니다.');
                }
              }
            } else if (index == 1) {
              showDialog(
                context: context,
                builder: (_) => SetDepartureCompletedBottomSheet(
                  onConfirm: () {
                    handleDepartureCompleted();
                  },
                ),
              );
            } else if (index == 2) {
              await showDepartureRequestStatusBottomSheet(
                context: context,
                plate: plate,
                onRequestEntry: () {
                  handleEntryParkingRequest(
                    context,
                    plate.plateNumber,
                    plate.area,
                  );
                },
                onCompleteEntry: () {
                  handleEntryParkingCompleted(
                    context,
                    plate.plateNumber,
                    plate.area,
                    plate.location,
                  );
                },
                onDelete: () {
                  showDialog(
                    context: context,
                    builder: (_) => PlateRemoveDialog(
                      onConfirm: () {
                        context.read<DeletePlate>().deleteFromDepartureRequest(
                          plate.plateNumber,
                          plate.area,
                        );
                        showSuccessSnackbar(
                          context,
                          "삭제 완료: ${plate.plateNumber}",
                        );
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
