// lib/screens/type_pages/parking_completed_package/parking_completed_control_buttons.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../enums/plate_type.dart';
import '../../../../repositories/plate_repo_services/plate_repository.dart';
import '../../../../states/plate/delete_plate.dart';
import '../../../../states/plate/plate_state.dart';
import '../../../../states/user/user_state.dart';
import '../../../../utils/snackbar_helper.dart';

import '../../../../widgets/dialog/billing_bottom_sheet/billing_bottom_sheet.dart';
import '../../../../widgets/dialog/confirm_cancel_fee_dialog.dart';
import '../lite_departure_completed_bottom_sheet.dart';
import 'widgets/lite_parking_completed_status_bottom_sheet.dart';
import 'widgets/lite_set_departure_request_dialog.dart';
import '../../../../widgets/dialog/plate_remove_dialog.dart';

// import '../../../utils/usage_reporter.dart';

/// Deep Blue 팔레트(서비스 카드와 동일 계열) + 상태 색상
class _Palette {
  static const base = Color(0xFF0D47A1); // primary
  static const dark = Color(0xFF09367D); // 강조 텍스트/아이콘

  // 상태 강조 색
  static const danger = Color(0xFFD32F2F); // 출차 요청(붉은색)
  static const success = Color(0xFF2E7D32); // 출차 완료(초록색)
}

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
  final Function(BuildContext context, String plateNumber, String area)
  handleEntryParkingRequest;
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
        final selectedPlate =
        plateState.getSelectedPlate(PlateType.parkingCompleted, userName);
        final isPlateSelected =
            selectedPlate != null && selectedPlate.isSelected;

        // 팔레트 기반 컬러
        final Color selectedItemColor = _Palette.base;
        final Color unselectedItemColor = _Palette.dark.withOpacity(.55);
        final Color muted = _Palette.dark.withOpacity(.60);

        return BottomNavigationBar(
          type: BottomNavigationBarType.fixed,
          backgroundColor: Colors.white,
          elevation: 0,
          selectedFontSize: 12,
          unselectedFontSize: 12,
          iconSize: 24,
          selectedItemColor: selectedItemColor,
          unselectedItemColor: unselectedItemColor,
          items: (isLocationPickerMode || isStatusMode)
              ? [
            BottomNavigationBarItem(
              icon: AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                transitionBuilder: (child, anim) =>
                    ScaleTransition(scale: anim, child: child),
                child: isLocked
                    ? const Icon(Icons.lock, key: ValueKey('locked'))
                    : const Icon(Icons.lock_open, key: ValueKey('unlocked')),
              ),
              label: isLocked ? '화면 잠금' : '잠금 해제',
            ),
            const BottomNavigationBarItem(
              icon: Icon(Icons.move_down, color: _Palette.danger),
              label: '출차 요청',
            ),
            const BottomNavigationBarItem(
              icon: Icon(Icons.directions_car, color: _Palette.success),
              label: '출차 완료',
            ),
          ]
              : [
            BottomNavigationBarItem(
              icon: AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                transitionBuilder: (child, animation) =>
                    ScaleTransition(scale: animation, child: child),
                child: isPlateSelected
                    ? (selectedPlate.isLockedFee
                    ? const Icon(Icons.lock_open,
                    key: ValueKey('unlock'),
                    color: Color(0x9909367D))
                    : const Icon(Icons.lock,
                    key: ValueKey('lock'),
                    color: Color(0x9909367D)))
                    : Icon(Icons.refresh,
                    key: const ValueKey('refresh'), color: muted),
              ),
              label: isPlateSelected
                  ? (selectedPlate.isLockedFee
                  ? '정산 취소'
                  : '사전 정산')
                  : '채팅하기',
            ),
            BottomNavigationBarItem(
              icon: Icon(
                isPlateSelected ? Icons.check_circle : Icons.search,
                color:
                isPlateSelected ? _Palette.danger : muted,
              ),
              label:
              isPlateSelected ? '출차 요청' : '번호판 검색',
            ),
            BottomNavigationBarItem(
              icon: AnimatedRotation(
                turns: isSorted ? 0.5 : 0.0,
                duration: const Duration(milliseconds: 300),
                child: Transform.scale(
                  scaleX: isSorted ? -1 : 1,
                  child: Icon(
                    isPlateSelected
                        ? Icons.settings
                        : Icons.sort,
                    color: muted,
                  ),
                ),
              ),
              label: isPlateSelected
                  ? '상태 수정'
                  : (isSorted ? '최신순' : '오래된 순'),
            ),
          ],
          onTap: (index) async {
            // 상태/로케이션 선택 모드 전용(여기서는 DB 없음)
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
                  builder: (context) =>
                  const DepartureCompletedBottomSheet(),
                );
              }
              return;
            }

            // 일반 모드: 선택 안된 경우(여기서는 DB 없음)
            if (!isParkingAreaMode || !isPlateSelected) {
              if (index == 0 || index == 1) {
                showSearchDialog();
              } else if (index == 2) {
                toggleSortIcon();
              }
              return;
            }

            // 선택된 차량 기준 실행
            final repo = context.read<PlateRepository>();
            final billingType = selectedPlate.billingType;
            final now = DateTime.now();
            final entryTime =
                selectedPlate.requestTime.toUtc().millisecondsSinceEpoch ~/
                    1000;
            final currentTime =
                now.toUtc().millisecondsSinceEpoch ~/ 1000;
            final firestore = FirebaseFirestore.instance;
            final documentId = selectedPlate.id;
            final selectedArea = selectedPlate.area;

            if (index == 0) {
              // === 0원 규칙: basicAmount==0 && addAmount==0
              final bool isZeroZero =
                  ((selectedPlate.basicAmount ?? 0) == 0) &&
                      ((selectedPlate.addAmount ?? 0) == 0);

              // 0원 + 이미 잠금 -> 해제 금지 (DB 없음)
              if (isZeroZero && selectedPlate.isLockedFee) {
                showFailedSnackbar(context,
                    '이 차량은 0원 규칙으로 잠금 상태이며 해제할 수 없습니다.');
                return;
              }

              // 0원 + 아직 잠금 아님 -> 자동 잠금 (WRITE ×2)
              if (isZeroZero && !selectedPlate.isLockedFee) {
                final updatedPlate = selectedPlate.copyWith(
                  isLockedFee: true,
                  lockedAtTimeInSeconds: currentTime,
                  lockedFeeAmount: 0,
                  paymentMethod: null,
                );

                try {
                  await repo.addOrUpdatePlate(documentId, updatedPlate);
                  _reportDbSafe(
                    area: selectedArea,
                    action: 'write',
                    source:
                    'parkingCompleted.prebill.autoZero.repo.addOrUpdatePlate',
                    n: 1,
                  );

                  await context
                      .read<PlateState>()
                      .updatePlateLocally(
                      PlateType.parkingCompleted, updatedPlate);

                  final autoLog = {
                    'action': '사전 정산(자동 잠금: 0원)',
                    'performedBy': userName,
                    'timestamp': now.toIso8601String(),
                    'lockedFee': 0,
                    'auto': true,
                  };

                  await firestore
                      .collection('plates')
                      .doc(documentId)
                      .update({
                    'logs': FieldValue.arrayUnion([autoLog])
                  });
                  _reportDbSafe(
                    area: selectedArea,
                    action: 'write',
                    source:
                    'parkingCompleted.prebill.autoZero.plates.update.logs.arrayUnion',
                    n: 1,
                  );

                  showSuccessSnackbar(
                      context, '0원 유형이라 자동으로 잠금되었습니다.');
                } catch (e) {
                  showFailedSnackbar(context,
                      '자동 잠금 처리에 실패했습니다. 다시 시도해 주세요.');
                }
                return;
              }

              // 정산 타입 미지정 (DB 없음)
              if ((billingType ?? '').trim().isEmpty) {
                showFailedSnackbar(
                    context, '정산 타입이 지정되지 않아 사전 정산이 불가능합니다.');
                return;
              }

              // 이미 잠금 → 정산 취소 (WRITE ×2)
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

                try {
                  await repo.addOrUpdatePlate(documentId, updatedPlate);
                  _reportDbSafe(
                    area: selectedArea,
                    action: 'write',
                    source:
                    'parkingCompleted.prebill.unlock.repo.addOrUpdatePlate',
                    n: 1,
                  );

                  await context
                      .read<PlateState>()
                      .updatePlateLocally(
                      PlateType.parkingCompleted, updatedPlate);

                  final cancelLog = {
                    'action': '사전 정산 취소',
                    'performedBy': userName,
                    'timestamp': now.toIso8601String(),
                  };

                  await firestore
                      .collection('plates')
                      .doc(documentId)
                      .update({
                    'logs': FieldValue.arrayUnion([cancelLog])
                  });
                  _reportDbSafe(
                    area: selectedArea,
                    action: 'write',
                    source:
                    'parkingCompleted.prebill.unlock.plates.update.logs.arrayUnion',
                    n: 1,
                  );

                  showSuccessSnackbar(context, '사전 정산이 취소되었습니다.');
                } catch (e) {
                  showFailedSnackbar(context, '정산 취소 중 오류가 발생했습니다.');
                }
              } else {
                // 사전 정산(바텀시트) → 확정 시 WRITE ×2
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
                  regularDurationHours:
                  selectedPlate.regularDurationHours,
                );
                if (result == null) return;

                final updatedPlate = selectedPlate.copyWith(
                  isLockedFee: true,
                  lockedAtTimeInSeconds: currentTime,
                  lockedFeeAmount: result.lockedFee,
                  paymentMethod: result.paymentMethod,
                );

                try {
                  await repo.addOrUpdatePlate(documentId, updatedPlate);
                  _reportDbSafe(
                    area: selectedArea,
                    action: 'write',
                    source:
                    'parkingCompleted.prebill.lock.repo.addOrUpdatePlate',
                    n: 1,
                  );

                  await context
                      .read<PlateState>()
                      .updatePlateLocally(
                      PlateType.parkingCompleted, updatedPlate);

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

                  await firestore
                      .collection('plates')
                      .doc(documentId)
                      .update({
                    'logs': FieldValue.arrayUnion([log])
                  });
                  _reportDbSafe(
                    area: selectedArea,
                    action: 'write',
                    source:
                    'parkingCompleted.prebill.lock.plates.update.logs.arrayUnion',
                    n: 1,
                  );

                  showSuccessSnackbar(
                    context,
                    '사전 정산 완료: ₩${result.lockedFee} (${result.paymentMethod})',
                  );
                } catch (e) {
                  showFailedSnackbar(context, '사전 정산 처리 중 오류가 발생했습니다.');
                }
              }
            } else if (index == 1) {
              // 출차 요청(확정 동작은 외부 핸들러에서 Firebase 처리/계측)
              showDialog(
                context: context,
                builder: (context) => SetDepartureRequestBottomSheet(
                  onConfirm: () => handleDepartureRequested(context),
                ),
              );
            } else if (index == 2) {
              // 상태 수정 시트(삭제 실행 시 DeletePlate 내부에서 Firebase 처리/계측)
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
                        try {
                          context
                              .read<DeletePlate>()
                              .deleteFromParkingCompleted(
                            selectedPlate.plateNumber,
                            selectedPlate.area,
                          );
                          showSuccessSnackbar(context,
                              "삭제 완료: ${selectedPlate.plateNumber}");
                        } catch (_) {
                          // DeletePlate 내부에서 실패 처리
                        }
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

/// UsageReporter: 파이어베이스 DB 작업만 계측 (read / write / delete)
void _reportDbSafe({
  required String area,
  required String action, // 'read' | 'write' | 'delete'
  required String source,
  int n = 1,
}) {
  try {
    /*UsageReporter.instance.report(
      area: area.trim(),
      action: action,
      n: n,
      source: source,
    );*/
  } catch (_) {
    // 계측 실패는 UX에 영향 없음
  }
}
