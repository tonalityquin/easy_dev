import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../enums/plate_type.dart';
import '../../../../repositories/plate_repo_services/plate_repository.dart';
import '../../../../states/area/area_state.dart';
import '../../../../states/page/normal_page_state.dart';
import '../../../../states/plate/delete_plate.dart';
import '../../../../states/plate/normal_plate_state.dart';
import '../../../../states/user/user_state.dart';
import '../../../../utils/snackbar_helper.dart';

import '../../../../widgets/dialog/billing_bottom_sheet/billing_bottom_sheet.dart';
import '../../../../widgets/dialog/confirm_cancel_fee_dialog.dart';
import '../normal_departure_completed_bottom_sheet.dart';
import 'widgets/normal_parking_completed_status_bottom_sheet.dart';
import 'widgets/normal_set_departure_request_dialog.dart';
import '../../../../widgets/dialog/plate_remove_dialog.dart';

/// Deep Blue 팔레트(서비스 카드와 동일 계열) + 상태 색상
class _Palette {
  static const base = Color(0xFF37474F); // primary
  static const dark = Color(0xFF37474F); // 강조 텍스트/아이콘

  // 상태 강조 색
  static const danger = Color(0xFFD32F2F); // 출차 요청(붉은색)
  static const success = Color(0xFF2E7D32); // 출차 완료(초록색)
}

/// ✅ 출차 요청(PlateType.departureRequests) 건수(aggregation count) 표시 위젯
/// - plates 컬렉션에서 (type == departure_requests && area == area) 조건으로 count()
/// - refreshToken 변경 시(같은 area여도) 다시 count().get()
class DepartureRequestsAggregationCount extends StatefulWidget {
  final String area;
  final Color color;
  final double fontSize;

  /// ✅ 같은 area에서도 재조회 트리거로 사용
  final int refreshToken;

  const DepartureRequestsAggregationCount({
    super.key,
    required this.area,
    required this.color,
    this.fontSize = 18,
    required this.refreshToken,
  });

  @override
  State<DepartureRequestsAggregationCount> createState() =>
      _DepartureRequestsAggregationCountState();
}

class _DepartureRequestsAggregationCountState
    extends State<DepartureRequestsAggregationCount> {
  Future<int>? _future;

  @override
  void initState() {
    super.initState();
    _future = _fetch();
  }

  @override
  void didUpdateWidget(
      covariant DepartureRequestsAggregationCount oldWidget) {
    super.didUpdateWidget(oldWidget);

    final areaChanged = oldWidget.area.trim() != widget.area.trim();
    final tokenChanged = oldWidget.refreshToken != widget.refreshToken;

    if (areaChanged || tokenChanged) {
      _future = _fetch(); // ✅ 같은 area여도 token이 바뀌면 재조회
    }
  }

  Future<int> _fetch() async {
    final area = widget.area.trim();
    if (area.isEmpty) return 0;

    final agg = FirebaseFirestore.instance
        .collection('plates')
        .where('type', isEqualTo: PlateType.departureRequests.firestoreValue)
        .where('area', isEqualTo: area)
        .count();

    final snap = await agg.get();
    return snap.count ?? 0;
  }

  @override
  Widget build(BuildContext context) {
    final area = widget.area.trim();

    // area가 비어있으면 표시만 0으로(조회 시도 없음)
    if (area.isEmpty) {
      return Center(
        child: Text(
          '0',
          style: TextStyle(
            color: widget.color,
            fontSize: widget.fontSize,
            fontWeight: FontWeight.bold,
          ),
        ),
      );
    }

    return FutureBuilder<int>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2.2,
              valueColor: AlwaysStoppedAnimation<Color>(widget.color),
            ),
          );
        }

        if (snap.hasError) {
          return Center(
            child: Text(
              '—',
              style: TextStyle(
                color: widget.color,
                fontSize: widget.fontSize,
                fontWeight: FontWeight.bold,
              ),
            ),
          );
        }

        final count = snap.data ?? 0;
        return FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            '$count',
            style: TextStyle(
              color: widget.color,
              fontSize: widget.fontSize,
              fontWeight: FontWeight.bold,
            ),
          ),
        );
      },
    );
  }
}

class NormalParkingCompletedControlButtons extends StatelessWidget {
  final bool isParkingAreaMode;
  final bool isStatusMode;
  final bool isLocationPickerMode;
  final bool isSorted;
  final bool isLocked;
  final VoidCallback onToggleLock;
  final VoidCallback showSearchDialog;
  final VoidCallback toggleSortIcon;
  final Function(BuildContext context, String plateNumber, String area)
  handleEntryParkingRequest;
  final Function(BuildContext context) handleDepartureRequested;

  const NormalParkingCompletedControlButtons({
    super.key,
    required this.isParkingAreaMode,
    required this.isStatusMode,
    required this.isLocationPickerMode,
    required this.isSorted,
    required this.isLocked,
    required this.onToggleLock,
    required this.showSearchDialog,
    required this.toggleSortIcon,
    required this.handleEntryParkingRequest,
    required this.handleDepartureRequested,
  });

  /// ✅ area 결정(주석 의도에 맞춰 fallbackArea(선택 plate.area) 우선)
  String _resolveArea(BuildContext context, {String? fallbackArea}) {
    final fb = (fallbackArea ?? '').trim();
    if (fb.isNotEmpty) return fb;

    final userArea = context.read<UserState>().currentArea.trim();
    if (userArea.isNotEmpty) return userArea;

    final stateArea = context.read<AreaState>().currentArea.trim();
    if (stateArea.isNotEmpty) return stateArea;

    return '';
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<NormalPlateState>(
      builder: (context, normalPlateState, _) {
        final userName = context.read<UserState>().name;
        final normalSelectedPlate = normalPlateState.normalGetSelectedPlate(
          PlateType.parkingCompleted,
          userName,
        );
        final isPlateSelected =
            normalSelectedPlate != null && normalSelectedPlate.isSelected;

        final departureCountArea = _resolveArea(
          context,
          fallbackArea: normalSelectedPlate?.area,
        );

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
                    : const Icon(Icons.lock_open,
                    key: ValueKey('unlocked')),
              ),
              label: isLocked ? '화면 잠금' : '잠금 해제',
            ),

            // ✅ 출차 요청: aggregation count (refreshToken 기반 재조회)
            BottomNavigationBarItem(
              icon: Selector<NormalPageState, int>(
                selector: (_, s) => s.departureRequestsCountRefreshToken,
                builder: (context, token, _) {
                  return DepartureRequestsAggregationCount(
                    area: departureCountArea,
                    color: _Palette.danger,
                    fontSize: 18,
                    refreshToken: token,
                  );
                },
              ),
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
                    ? (normalSelectedPlate.isLockedFee
                    ? const Icon(Icons.lock_open,
                    key: ValueKey('unlock'),
                    color: Color(0xFF37474F))
                    : const Icon(Icons.lock,
                    key: ValueKey('lock'),
                    color: Color(0xFF37474F)))
                    : Icon(Icons.refresh,
                    key: const ValueKey('refresh'), color: muted),
              ),
              label: isPlateSelected
                  ? (normalSelectedPlate.isLockedFee ? '정산 취소' : '사전 정산')
                  : '채팅하기',
            ),

            // ✅ (선택된 경우) 출차 요청: aggregation count (refreshToken 기반 재조회)
            BottomNavigationBarItem(
              icon: isPlateSelected
                  ? Selector<NormalPageState, int>(
                selector: (_, s) =>
                s.departureRequestsCountRefreshToken,
                builder: (context, token, _) {
                  return DepartureRequestsAggregationCount(
                    area: departureCountArea,
                    color: _Palette.danger,
                    fontSize: 18,
                    refreshToken: token,
                  );
                },
              )
                  : Icon(Icons.search, color: muted),
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
                  builder: (context) => const NormalDepartureCompletedBottomSheet(),
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
            final billingType = normalSelectedPlate.billingType;
            final now = DateTime.now();
            final entryTime =
                normalSelectedPlate.requestTime.toUtc().millisecondsSinceEpoch ~/ 1000;
            final currentTime = now.toUtc().millisecondsSinceEpoch ~/ 1000;
            final firestore = FirebaseFirestore.instance;
            final documentId = normalSelectedPlate.id;
            final selectedArea = normalSelectedPlate.area;

            if (index == 0) {
              final bool isZeroZero =
                  ((normalSelectedPlate.basicAmount ?? 0) == 0) &&
                      ((normalSelectedPlate.addAmount ?? 0) == 0);

              if (isZeroZero && normalSelectedPlate.isLockedFee) {
                showFailedSnackbar(
                    context, '이 차량은 0원 규칙으로 잠금 상태이며 해제할 수 없습니다.');
                return;
              }

              if (isZeroZero && !normalSelectedPlate.isLockedFee) {
                final updatedPlate = normalSelectedPlate.copyWith(
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
                    source: 'parkingCompleted.prebill.autoZero.repo.addOrUpdatePlate',
                    n: 1,
                  );

                  await context
                      .read<NormalPlateState>()
                      .normalUpdatePlateLocally(PlateType.parkingCompleted, updatedPlate);

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
                  _reportDbSafe(
                    area: selectedArea,
                    action: 'write',
                    source: 'parkingCompleted.prebill.autoZero.plates.update.logs.arrayUnion',
                    n: 1,
                  );

                  showSuccessSnackbar(context, '0원 유형이라 자동으로 잠금되었습니다.');
                } catch (e) {
                  showFailedSnackbar(context, '자동 잠금 처리에 실패했습니다. 다시 시도해 주세요.');
                }
                return;
              }

              if ((billingType ?? '').trim().isEmpty) {
                showFailedSnackbar(context, '정산 타입이 지정되지 않아 사전 정산이 불가능합니다.');
                return;
              }

              if (normalSelectedPlate.isLockedFee) {
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (_) => const ConfirmCancelFeeDialog(),
                );
                if (confirm != true) return;

                final updatedPlate = normalSelectedPlate.copyWith(
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
                    source: 'parkingCompleted.prebill.unlock.repo.addOrUpdatePlate',
                    n: 1,
                  );

                  await context
                      .read<NormalPlateState>()
                      .normalUpdatePlateLocally(PlateType.parkingCompleted, updatedPlate);

                  final cancelLog = {
                    'action': '사전 정산 취소',
                    'performedBy': userName,
                    'timestamp': now.toIso8601String(),
                  };

                  await firestore.collection('plates').doc(documentId).update({
                    'logs': FieldValue.arrayUnion([cancelLog])
                  });
                  _reportDbSafe(
                    area: selectedArea,
                    action: 'write',
                    source: 'parkingCompleted.prebill.unlock.plates.update.logs.arrayUnion',
                    n: 1,
                  );

                  showSuccessSnackbar(context, '사전 정산이 취소되었습니다.');
                } catch (e) {
                  showFailedSnackbar(context, '정산 취소 중 오류가 발생했습니다.');
                }
              } else {
                final result = await showOnTapBillingBottomSheet(
                  context: context,
                  entryTimeInSeconds: entryTime,
                  currentTimeInSeconds: currentTime,
                  basicStandard: normalSelectedPlate.basicStandard ?? 0,
                  basicAmount: normalSelectedPlate.basicAmount ?? 0,
                  addStandard: normalSelectedPlate.addStandard ?? 0,
                  addAmount: normalSelectedPlate.addAmount ?? 0,
                  billingType: normalSelectedPlate.billingType ?? '변동',
                  regularAmount: normalSelectedPlate.regularAmount,
                  regularDurationHours: normalSelectedPlate.regularDurationHours,
                );
                if (result == null) return;

                final updatedPlate = normalSelectedPlate.copyWith(
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
                    source: 'parkingCompleted.prebill.lock.repo.addOrUpdatePlate',
                    n: 1,
                  );

                  await context
                      .read<NormalPlateState>()
                      .normalUpdatePlateLocally(PlateType.parkingCompleted, updatedPlate);

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
                  _reportDbSafe(
                    area: selectedArea,
                    action: 'write',
                    source: 'parkingCompleted.prebill.lock.plates.update.logs.arrayUnion',
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
              showDialog(
                context: context,
                builder: (context) => NormalSetDepartureRequestDialog(
                  onConfirm: () => handleDepartureRequested(context),
                ),
              );
            } else if (index == 2) {
              await showNormalParkingCompletedStatusBottomSheet(
                context: context,
                plate: normalSelectedPlate,
                onRequestEntry: () => handleEntryParkingRequest(
                  context,
                  normalSelectedPlate.plateNumber,
                  normalSelectedPlate.area,
                ),
                onDelete: () {
                  showDialog(
                    context: context,
                    builder: (_) => PlateRemoveDialog(
                      onConfirm: () {
                        try {
                          context.read<DeletePlate>().deleteFromParkingCompleted(
                            normalSelectedPlate.plateNumber,
                            normalSelectedPlate.area,
                          );
                          showSuccessSnackbar(
                              context, "삭제 완료: ${normalSelectedPlate.plateNumber}");
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
