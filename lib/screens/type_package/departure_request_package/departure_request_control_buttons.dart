// lib/screens/type_pages/departure_request_pages/departure_request_control_buttons.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // HapticFeedback
import 'package:provider/provider.dart';

import '../../../enums/plate_type.dart';
import '../../../repositories/plate_repo_services/plate_repository.dart';
import '../../../states/plate/delete_plate.dart';
import '../../../states/plate/plate_state.dart';
import '../../../states/user/user_state.dart';
import '../../../utils/snackbar_helper.dart';
// ✅ UsageReporter 계측 (Firebase 로직만)
import '../../../utils/usage_reporter.dart';

import '../../../widgets/dialog/billing_bottom_sheet/billing_bottom_sheet.dart';
import '../../../widgets/dialog/confirm_cancel_fee_dialog.dart';
import 'widgets/departure_request_status_bottom_sheet.dart';
import 'widgets/set_departure_completed_dialog.dart';
import '../../../widgets/dialog/plate_remove_dialog.dart';

/// Deep Blue 팔레트 + 상태 강조 색
class _Palette {
  static const base = Color(0xFF0D47A1); // primary
  static const dark = Color(0xFF09367D); // 강조 텍스트/아이콘
  static const danger = Color(0xFFD32F2F); // 🔴 검색(비선택)
  static const success = Color(0xFF2E7D32); // 🟢 출차(선택)
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
    // 팔레트 기반 색
    final Color selectedItemColor = _Palette.base;
    final Color unselectedItemColor = _Palette.dark.withOpacity(.55);
    final Color muted = _Palette.dark.withOpacity(.60);

    return Consumer<PlateState>(
      builder: (context, plateState, _) {
        final userName = context.read<UserState>().name;

        // 선택된 Plate만 구독해 불필요한 리빌드 최소화
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
                child: Icon(
                  isPlateSelected
                      ? Icons.payments
                      : (isLocked ? Icons.lock : Icons.lock_open),
                  color: muted,
                ),
              ),
              label: isPlateSelected ? '정산 관리' : '화면 잠금',
            ),
            BottomNavigationBarItem(
              icon: Tooltip(
                message: isPlateSelected ? '출차 완료' : '번호판 검색',
                child: Icon(
                  isPlateSelected ? Icons.check_circle : Icons.search,
                  // 요구사항: 검색=붉은색, 출차=초록색
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
            final repo = context.read<PlateRepository>();
            final firestore = FirebaseFirestore.instance;

            // 비선택 상태: 각 탭 별 기본 액션 (Firebase 접근 없음 → 계측 제외)
            if (!isPlateSelected) {
              HapticFeedback.selectionClick();
              if (index == 0) {
                toggleLock();
              } else if (index == 1) {
                showSearchDialog();
              } else if (index == 2) {
                toggleSortIcon();
              }
              return;
            }

            // 선택 상태: plate 스냅샷 고정
            final plate = selectedPlate;
            final now = DateTime.now();
            final currentTime = now.toUtc().millisecondsSinceEpoch ~/ 1000;
            final entryTime = plate.requestTime.toUtc().millisecondsSinceEpoch ~/ 1000;
            final documentId = plate.id;
            final area = plate.area; // 계측 시 사용

            if (index == 0) {
              // “0원 자동 잠금” 조건(변동 + 정기 모두)
              final type = (plate.billingType ?? '').trim();
              final isFixed = type == '고정';
              final isZeroAutoLock =
                  (((plate.basicAmount ?? 0) == 0) && ((plate.addAmount ?? 0) == 0)) ||
                      (isFixed && (plate.regularAmount ?? 0) == 0);

              // 0원 + 이미 잠금 -> 해제 금지 (Firebase 없음)
              if (isZeroAutoLock && plate.isLockedFee) {
                showFailedSnackbar(context, '이 차량은 0원 규칙으로 잠금 상태이며 해제할 수 없습니다.');
                return;
              }

              // 0원 + 아직 잠금 아님 -> 자동 잠금 (Firebase write 2회)
              if (isZeroAutoLock && !plate.isLockedFee) {
                final updatedPlate = plate.copyWith(
                  isLockedFee: true,
                  lockedAtTimeInSeconds: currentTime,
                  lockedFeeAmount: 0,
                  paymentMethod: null,
                );
                try {
                  await repo.addOrUpdatePlate(documentId, updatedPlate);
                  // ✅ 계측: WRITE (plates upsert via repository)
                  _reportDbSafe(
                    area: area,
                    action: 'write',
                    source: 'departureReq.prebill.autoZero.repo.addOrUpdatePlate',
                    n: 1,
                  );

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
                  await firestore.collection('plates').doc(documentId).update({
                    'logs': FieldValue.arrayUnion([autoLog])
                  });
                  // ✅ 계측: WRITE (logs arrayUnion)
                  _reportDbSafe(
                    area: area,
                    action: 'write',
                    source: 'departureReq.prebill.autoZero.plates.update.logs.arrayUnion',
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

              // 일반 흐름: 정산 타입 필요 (Firebase 없음)
              final billingType = plate.billingType ?? '';
              if (billingType.trim().isEmpty) {
                showFailedSnackbar(context, '정산 타입이 지정되지 않아 사전 정산이 불가능합니다.');
                return;
              }

              // 이미 잠금 → 해제 흐름 (Firebase write 2회)
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
                );

                try {
                  await repo.addOrUpdatePlate(documentId, updatedPlate);
                  // ✅ 계측: WRITE (plates upsert via repository)
                  _reportDbSafe(
                    area: area,
                    action: 'write',
                    source: 'departureReq.prebill.unlock.repo.addOrUpdatePlate',
                    n: 1,
                  );

                  await plateState.updatePlateLocally(
                    PlateType.departureRequests,
                    updatedPlate,
                  );

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
                    area: area,
                    action: 'write',
                    source: 'departureReq.prebill.unlock.plates.update.logs.arrayUnion',
                    n: 1,
                  );

                  HapticFeedback.mediumImpact();
                  showSuccessSnackbar(context, '사전 정산이 취소되었습니다.');
                } catch (e, st) {
                  debugPrint('unlock(cancel fee) error: $e\n$st');
                  showFailedSnackbar(context, '사전 정산 취소 중 오류가 발생했습니다.');
                }
              } else {
                // 잠금 아님 → 바텀시트 열어 사전 정산 (Firebase write 2회)
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
                if (result == null) {
                  return;
                }

                final updatedPlate = plate.copyWith(
                  isLockedFee: true,
                  lockedAtTimeInSeconds: currentTime,
                  lockedFeeAmount: result.lockedFee,
                  paymentMethod: result.paymentMethod,
                );

                try {
                  await repo.addOrUpdatePlate(documentId, updatedPlate);
                  // ✅ 계측: WRITE (plates upsert via repository)
                  _reportDbSafe(
                    area: area,
                    action: 'write',
                    source: 'departureReq.prebill.lock.repo.addOrUpdatePlate',
                    n: 1,
                  );

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
                    if (result.reason != null && result.reason!.trim().isNotEmpty)
                      'reason': result.reason!.trim(),
                  };

                  await firestore.collection('plates').doc(documentId).update({
                    'logs': FieldValue.arrayUnion([log])
                  });
                  // ✅ 계측: WRITE (logs arrayUnion)
                  _reportDbSafe(
                    area: area,
                    action: 'write',
                    source: 'departureReq.prebill.lock.plates.update.logs.arrayUnion',
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
            } else if (index == 1) {
              // 출차 완료 확인 다이얼로그 (Firebase 없음 — 실제 처리 콜백 내부에서 수행/계측)
              HapticFeedback.selectionClick();
              showDialog(
                context: context,
                builder: (_) => SetDepartureCompletedBottomSheet(
                  onConfirm: () {
                    handleDepartureCompleted();
                  },
                ),
              );
            } else if (index == 2) {
              // 상태 수정 시트 (여기서는 네비게이션/콜백만, Firebase 없음)
              HapticFeedback.selectionClick();
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
                        // ⚠️ 실제 삭제는 DeletePlate 내부에서 Firestore 수행/계측하도록 처리
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

/// UsageReporter: Firebase DB 작업만 계측
void _reportDbSafe({
  required String area,
  required String action, // 'read' | 'write' | 'delete'
  required String source,
  int n = 1,
}) {
  try {
    UsageReporter.instance.report(
      area: area,
      action: action,
      n: n,
      source: source,
    );
  } catch (_) {
    // 계측 실패는 기능에 영향 X
  }
}
