// lib/screens/type_pages/parking_requests_package/parking_request_control_buttons.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // HapticFeedback
import 'package:provider/provider.dart';

import '../../../enums/plate_type.dart';
import '../../../models/plate_model.dart';
import '../../../repositories/plate_repo_services/plate_repository.dart';
import '../../../states/plate/delete_plate.dart';
import '../../../states/plate/plate_state.dart';
import '../../../states/user/user_state.dart';
import '../../../utils/snackbar_helper.dart';
import '../../../widgets/dialog/billing_bottom_sheet/billing_bottom_sheet.dart';
import '../../../widgets/dialog/confirm_cancel_fee_dialog.dart';
import 'widgets/parking_request_status_bottom_sheet.dart';

/// Deep Blue 팔레트(서비스 카드와 동일 계열) + 대비 강조 색
class _Palette {
  static const base = Color(0xFF0D47A1); // primary (Deep Blue)
  static const dark = Color(0xFF09367D); // 강조 텍스트/아이콘
  static const success = Color(0xFF2E7D32); // 입차(완료)용 - Green 800
  static const accent = Color(0xFFFF6D00); // 검색 액션용 - Orange 800
}

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
    final userName = context.read<UserState>().name;

    // 선택된 차량만 추출 → 리빌드 최소화
    final selectedPlate = context.select<PlateState, PlateModel?>(
          (s) => s.getSelectedPlate(PlateType.parkingRequests, userName),
    );
    final isPlateSelected = selectedPlate != null && selectedPlate.isSelected;

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
                color: _Palette.base,
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
            message: isPlateSelected ? '입차 완료' : '번호판 검색',
            child: isPlateSelected
                ? const Icon(Icons.check_circle, color: _Palette.success)
                : const Icon(Icons.search, color: _Palette.accent),
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
        final plateState = context.read<PlateState>();
        final plate = selectedPlate; // 고정

        if (index == 0) {
          if (plate != null && plate.isSelected) {
            await _handleBillingAction(
              context: context,
              selectedPlate: plate,
              userName: userName,
              repo: repo,
              plateState: plateState,
            );
          } else {
            onToggleLock();
          }
        } else if (index == 1) {
          if (plate != null && plate.isSelected) {
            onParkingCompleted();
          } else {
            onSearchPressed();
          }
        } else if (index == 2) {
          if (plate != null && plate.isSelected) {
            await showParkingRequestStatusBottomSheet(
              context: context,
              plate: plate,
              onCancelEntryRequest: () async {
                try {
                  await context.read<DeletePlate>().deleteFromParkingRequest(
                    plate.plateNumber,
                    plate.area,
                  );
                  HapticFeedback.mediumImpact();
                  showSuccessSnackbar(
                      context, "입차 요청이 취소되었습니다: ${plate.plateNumber}");
                } catch (e, st) {
                  debugPrint('cancel entry request error: $e\n$st');
                  showFailedSnackbar(context, "입차 요청 취소 중 오류가 발생했습니다.");
                }
              },
            );
          } else {
            onSortToggle();
          }
        }
      },
    );
  }

  Future<void> _handleBillingAction({
    required BuildContext context,
    required PlateModel selectedPlate,
    required String userName,
    required PlateRepository repo,
    required PlateState plateState,
  }) async {
    final firestore = FirebaseFirestore.instance;
    final now = DateTime.now();

    final String documentId = selectedPlate.id;
    final int entryTime =
        selectedPlate.requestTime.toUtc().millisecondsSinceEpoch ~/ 1000;
    final int currentTime = now.toUtc().millisecondsSinceEpoch ~/ 1000;

    final type = (selectedPlate.billingType ?? '').trim();
    final isFixed = type == '고정';
    final bool isZeroAutoLock =
        (((selectedPlate.basicAmount ?? 0) == 0) &&
            ((selectedPlate.addAmount ?? 0) == 0)) ||
            (isFixed && (selectedPlate.regularAmount ?? 0) == 0);

    // 0원 + 이미 잠금 → 해제 금지
    if (isZeroAutoLock && selectedPlate.isLockedFee) {
      showFailedSnackbar(context, '이 차량은 0원 규칙으로 잠금 상태이며 해제할 수 없습니다.');
      return;
    }

    // 0원 + 아직 잠금 아님 → 자동 잠금
    if (isZeroAutoLock && !selectedPlate.isLockedFee) {
      final updatedPlate = selectedPlate.copyWith(
        isLockedFee: true,
        lockedAtTimeInSeconds: currentTime,
        lockedFeeAmount: 0,
        paymentMethod: null,
        // ✅ 정산 후 선택 해제
        isSelected: false,
        selectedBy: null,
      );

      try {
        await repo.addOrUpdatePlate(documentId, updatedPlate);
        await plateState.updatePlateLocally(
            PlateType.parkingRequests, updatedPlate);

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

        // ✅ 보류 초기화
        if (context.mounted) {
          context.read<PlateState>().clearPendingIfMatches(documentId);
        }
      } catch (e, st) {
        debugPrint('auto-lock(0원) error: $e\n$st');
        showFailedSnackbar(context, '자동 잠금 처리에 실패했습니다. 다시 시도해 주세요.');
      }
      return;
    }

    // 일반 흐름: 정산 타입 확인
    final billingType = selectedPlate.billingType;
    if (billingType == null || billingType.trim().isEmpty) {
      showFailedSnackbar(context, '정산 타입이 지정되지 않아 사전 정산이 불가능합니다.');
      return;
    }

    // 이미 잠금 → 해제(사전 정산 취소)
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
        // ✅ 취소 후에도 선택 해제
        isSelected: false,
        selectedBy: null,
      );

      try {
        await repo.addOrUpdatePlate(documentId, updatedPlate);
        await plateState.updatePlateLocally(
            PlateType.parkingRequests, updatedPlate);

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

        // ✅ 보류 초기화
        if (context.mounted) {
          context.read<PlateState>().clearPendingIfMatches(documentId);
        }
      } catch (e, st) {
        debugPrint('unlock(cancel fee) error: $e\n$st');
        showFailedSnackbar(context, '사전 정산 취소 중 오류가 발생했습니다.');
      }
      return;
    }

    // 잠금 아님 → 바텀시트 열어 사전 정산
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
      // ✅ 정산 후 선택 해제
      isSelected: false,
      selectedBy: null,
    );

    try {
      await repo.addOrUpdatePlate(documentId, updatedPlate);
      await plateState.updatePlateLocally(
          PlateType.parkingRequests, updatedPlate);

      final log = {
        'action': '사전 정산',
        'performedBy': userName,
        'timestamp': now.toIso8601String(),
        'lockedFee': result.lockedFee,
        'paymentMethod': result.paymentMethod,
        if (result.reason != null && result.reason!.trim().isNotEmpty)
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

      // ✅ 보류 초기화
      if (context.mounted) {
        context.read<PlateState>().clearPendingIfMatches(documentId);
      }
    } catch (e, st) {
      debugPrint('lock(fee) error: $e\n$st');
      showFailedSnackbar(context, '사전 정산 처리 중 오류가 발생했습니다.');
    }
  }
}
