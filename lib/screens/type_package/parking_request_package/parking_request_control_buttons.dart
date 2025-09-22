// lib/screens/type_pages/parking_requests_pages/parking_request_control_buttons.dart
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

// ✅ UsageReporter: 파이어베이스(읽기/쓰기/삭제) 발생 지점만 계측
import '../../../utils/usage_reporter.dart';

/// Deep Blue 팔레트(서비스 카드와 동일 계열) + 대비 강조 색
class _Palette {
  static const base   = Color(0xFF0D47A1); // primary (Deep Blue)
  static const dark   = Color(0xFF09367D); // 강조 텍스트/아이콘

  // 대비되는 강조 색
  static const success = Color(0xFF2E7D32); // 입차(완료)용 - Green 800
  static const accent  = Color(0xFFFF6D00); // 검색 액션용 - Orange 800
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
    // userName은 변경 가능성이 낮으므로 read
    final userName = context.read<UserState>().name;

    // 선택된 차량만 추출 → 리빌드 최소화
    final selectedPlate = context.select<PlateState, PlateModel?>(
          (s) => s.getSelectedPlate(PlateType.parkingRequests, userName),
    );
    final isPlateSelected = selectedPlate != null && selectedPlate.isSelected;

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
      items: [
        BottomNavigationBarItem(
          icon: Tooltip(
            message: isPlateSelected ? '정산 관리' : '화면 잠금',
            child: Icon(
              isPlateSelected ? Icons.payments : (isLocked ? Icons.lock : Icons.lock_open),
              color: isPlateSelected ? _Palette.base : muted,
            ),
          ),
          label: isPlateSelected ? '정산 관리' : '화면 잠금',
        ),

        // 두 번째 탭: ‘번호판 검색’ ↔ ‘입차’ 아이콘 색상 대비 강조
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
        final repo = context.read<PlateRepository>();
        final plate = selectedPlate; // ✨ 로컬 변수로 고정

        // 액션 공통: 가벼운 햅틱
        HapticFeedback.selectionClick();

        if (index == 0) {
          if (plate != null && plate.isSelected) {
            await _handleBillingAction(
              context,
              plate, // ✅ PlateModel로 타입 고정
              userName,
              repo,
            );
          } else {
            onToggleLock();
          }
        } else if (index == 1) {
          if (plate != null && plate.isSelected) {
            onParkingCompleted(); // 실제 Firebase 작업/계측은 해당 흐름 내부에서 처리
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
                  // ⚠️ 실제 삭제는 DeletePlate 내부에서 Firestore 수행/계측
                  await context.read<DeletePlate>().deleteFromParkingRequest(
                    plate.plateNumber,
                    plate.area,
                  );
                  HapticFeedback.mediumImpact();
                  showSuccessSnackbar(context, "입차 요청이 취소되었습니다: ${plate.plateNumber}");
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

  Future<void> _handleBillingAction(
      BuildContext context,
      PlateModel selectedPlate, // ✅ 명시 타입
      String userName,
      PlateRepository repo,
      ) async {
    final firestore = FirebaseFirestore.instance;
    final now = DateTime.now();

    // 키 스냅샷(레이스 대비)
    final String documentId = selectedPlate.id;
    final int entryTime = selectedPlate.requestTime.toUtc().millisecondsSinceEpoch ~/ 1000;
    final int currentTime = now.toUtc().millisecondsSinceEpoch ~/ 1000;

    // “0원 자동 잠금” 조건(변동 + 정기 모두 명시)
    final type = (selectedPlate.billingType ?? '').trim();
    final isFixed = type == '고정';
    final bool isZeroAutoLock =
        (((selectedPlate.basicAmount ?? 0) == 0) && ((selectedPlate.addAmount ?? 0) == 0)) ||
            (isFixed && (selectedPlate.regularAmount ?? 0) == 0);

    // 0원 + 이미 잠금 → 해제 금지 (Firebase 없음)
    if (isZeroAutoLock && selectedPlate.isLockedFee) {
      showFailedSnackbar(context, '이 차량은 0원 규칙으로 잠금 상태이며 해제할 수 없습니다.');
      return;
    }

    // 0원 + 아직 잠금 아님 → 자동 잠금(바텀시트 생략) — Firebase WRITE ×2
    if (isZeroAutoLock && !selectedPlate.isLockedFee) {
      final updatedPlate = selectedPlate.copyWith(
        isLockedFee: true,
        lockedAtTimeInSeconds: currentTime,
        lockedFeeAmount: 0,
        paymentMethod: null,
      );

      try {
        await repo.addOrUpdatePlate(documentId, updatedPlate);
        // ✅ 계측: WRITE (plates upsert via repository)
        _reportDbSafe(
          area: selectedPlate.area,
          action: 'write',
          source: 'parkingRequest.billing.autoLock.zero.repo.addOrUpdatePlate',
          n: 1,
        );

        context.read<PlateState>().updatePlateLocally(PlateType.parkingRequests, updatedPlate);

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
        // ✅ 계측: WRITE (logs arrayUnion)
        _reportDbSafe(
          area: selectedPlate.area,
          action: 'write',
          source: 'parkingRequest.billing.autoLock.zero.plates.update.logs.arrayUnion',
          n: 1,
        );

        HapticFeedback.mediumImpact();
        showSuccessSnackbar(context, '0원 유형이라 자동으로 잠금되었습니다.');
      } catch (e, st) {
        debugPrint('auto-lock(0원) error: $e\n$st');
        showFailedSnackbar(context, '자동 잠금 처리에 실패했습니다. 다시 시도해 주세요.');
      }
      return;
    }

    // 일반 흐름: 정산 타입 확인 (Firebase 없음)
    final billingType = selectedPlate.billingType;
    if (billingType == null || billingType.trim().isEmpty) {
      showFailedSnackbar(context, '정산 타입이 지정되지 않아 사전 정산이 불가능합니다.');
      return;
    }

    // 이미 잠금 → 해제 확인 후 취소 처리 — Firebase WRITE ×2
    if (selectedPlate.isLockedFee) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (_) => const ConfirmCancelFeeDialog(),
      );
      if (confirm != true) {
        return;
      }

      final updatedPlate = selectedPlate.copyWith(
        isLockedFee: false,
        lockedAtTimeInSeconds: null,
        lockedFeeAmount: null,
        paymentMethod: null,
      );

      try {
        await repo.addOrUpdatePlate(documentId, updatedPlate);
        // ✅ 계측: WRITE (plates upsert via repository)
        _reportDbSafe(
          area: selectedPlate.area,
          action: 'write',
          source: 'parkingRequest.billing.unlock.repo.addOrUpdatePlate',
          n: 1,
        );

        context.read<PlateState>().updatePlateLocally(PlateType.parkingRequests, updatedPlate);

        final cancelLog = {
          'action': '사전 정산 취소',
          'performedBy': userName,
          'timestamp': now.toIso8601String(),
        };
        await firestore.collection('plates').doc(documentId).update({
          'logs': FieldValue.arrayUnion([cancelLog])
        });
        // ✅ 계측: WRITE (logs arrayUnion)
        _reportDbSafe(
          area: selectedPlate.area,
          action: 'write',
          source: 'parkingRequest.billing.unlock.plates.update.logs.arrayUnion',
          n: 1,
        );

        HapticFeedback.mediumImpact();
        showSuccessSnackbar(context, '사전 정산이 취소되었습니다.');
      } catch (e, st) {
        debugPrint('unlock(cancel fee) error: $e\n$st');
        showFailedSnackbar(context, '사전 정산 취소 중 오류가 발생했습니다.');
      }
      return;
    }

    // 잠금 아님 → 바텀시트 열어 사전 정산 — Firebase WRITE ×2
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
    if (result == null) {
      return;
    }

    final updatedPlate = selectedPlate.copyWith(
      isLockedFee: true,
      lockedAtTimeInSeconds: currentTime,
      lockedFeeAmount: result.lockedFee,
      paymentMethod: result.paymentMethod,
    );

    try {
      await repo.addOrUpdatePlate(documentId, updatedPlate);
      // ✅ 계측: WRITE (plates upsert via repository)
      _reportDbSafe(
        area: selectedPlate.area,
        action: 'write',
        source: 'parkingRequest.billing.lock.repo.addOrUpdatePlate',
        n: 1,
      );

      context.read<PlateState>().updatePlateLocally(PlateType.parkingRequests, updatedPlate);

      final log = {
        'action': '사전 정산',
        'performedBy': userName,
        'timestamp': now.toIso8601String(),
        'lockedFee': result.lockedFee,
        'paymentMethod': result.paymentMethod,
        if (result.reason != null && result.reason!.trim().isNotEmpty)
          'reason': result.reason!.trim(), // 사유 저장
      };

      await FirebaseFirestore.instance.collection('plates').doc(documentId).update({
        'logs': FieldValue.arrayUnion([log])
      });
      // ✅ 계측: WRITE (logs arrayUnion)
      _reportDbSafe(
        area: selectedPlate.area,
        action: 'write',
        source: 'parkingRequest.billing.lock.plates.update.logs.arrayUnion',
        n: 1,
      );

      HapticFeedback.mediumImpact();
      showSuccessSnackbar(
        context,
        '사전 정산 완료: ₩${result.lockedFee} (${result.paymentMethod})',
      );
    } catch (e, st) {
      debugPrint('lock(fee) error: $e\n$st');
      showFailedSnackbar(context, '사전 정산 처리 중 오류가 발생했습니다.');
    }
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
    UsageReporter.instance.report(
      area: area.trim(),
      action: action,
      n: n,
      source: source,
    );
  } catch (_) {
    // 계측 실패는 기능에 영향 없음
  }
}
