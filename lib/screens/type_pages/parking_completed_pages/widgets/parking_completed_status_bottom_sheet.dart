import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../../../models/plate_model.dart';
import '../../../../screens/modify_pages/modify_plate_screen.dart';
import '../../../../screens/logs/plate_log_viewer_page.dart';
import '../../../../states/area/area_state.dart';
import '../../../../states/plate/movement_plate.dart';
import '../../../../states/user/user_state.dart';
import '../../../../utils/fee_calculator.dart';
import '../../../../enums/plate_type.dart';

// 중복 import 생략

Future<void> showParkingCompletedStatusBottomSheet({
  required BuildContext context,
  required PlateModel plate,
  required VoidCallback onRequestEntry,
  required VoidCallback onDelete,
}) async {
  final plateNumber = plate.plateNumber;
  final division = context.read<UserState>().division;
  final area = context.read<AreaState>().currentArea;

  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) {
      return DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        builder: (context, scrollController) {
          return Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
            child: ListView(
              controller: scrollController,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 20),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade400,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
                const Row(
                  children: [
                    Icon(Icons.settings, color: Colors.blueAccent),
                    SizedBox(width: 8),
                    Text(
                      '입차 완료 상태 처리',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  icon: const Icon(Icons.history),
                  label: const Text("로그 확인"),
                  onPressed: () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => PlateLogViewerBottomSheet(
                          initialPlateNumber: plateNumber,
                          division: division,
                          area: area,
                          requestTime: plate.requestTime,
                        ),
                      ),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 52),
                    backgroundColor: Colors.grey.shade100,
                    foregroundColor: Colors.black87,
                    elevation: 0,
                    side: const BorderSide(color: Colors.black12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                ElevatedButton.icon(
                  icon: const Icon(Icons.edit_note_outlined),
                  label: const Text("정보 수정"),
                  onPressed: () {
                    Navigator.pop(context);
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => ModifyPlateScreen(
                          plate: plate,
                          collectionKey: PlateType.parkingCompleted,
                        ),
                      ),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 52),
                    backgroundColor: Colors.grey.shade100,
                    foregroundColor: Colors.black87,
                    elevation: 0,
                    side: const BorderSide(color: Colors.black12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                ElevatedButton.icon(
                  icon: const Icon(Icons.assignment_return),
                  label: const Text("입차 요청으로 되돌리기"),
                  onPressed: () {
                    Navigator.pop(context);
                    onRequestEntry();
                  },
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 52),
                    backgroundColor: Colors.orange.shade400,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                ElevatedButton.icon(
                  icon: const Icon(Icons.exit_to_app),
                  label: const Text("출차 완료 처리"),
                  onPressed: () async {
                    Navigator.pop(context);
                    await Future.delayed(Duration.zero);
                    if (context.mounted) {
                      await handleEntryDepartureCompleted(context, plate);
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 52),
                    backgroundColor: Colors.green.shade600,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextButton.icon(
                  icon: const Icon(Icons.delete_forever, color: Colors.red),
                  label: const Text("삭제", style: TextStyle(color: Colors.red)),
                  onPressed: () {
                    Navigator.pop(context);
                    onDelete();
                  },
                ),
              ],
            ),
          );
        },
      );
    },
  );
}

void handleEntryParkingRequest(BuildContext context, String plateNumber, String area) {
  final movementPlate = context.read<MovementPlate>();
  final performedBy = context.read<UserState>().name; // ✅ 사용자 이름 가져오기

  movementPlate.goBackToParkingRequest(
    fromType: PlateType.parkingCompleted,
    plateNumber: plateNumber,
    area: area,
    newLocation: "미지정",
    performedBy: performedBy, // ✅ 전달
  );
}

Future<void> handleEntryDepartureCompleted(BuildContext context, PlateModel plate) async {
  final movementPlate = context.read<MovementPlate>();

  PlateModel updatedPlate = plate;

  if (plate.isLockedFee != true) {
    final shouldSettle = await showDialog<bool?>(
      context: context,
      builder: (context) => _DepartureSettlementConfirmDialog(
        entryTimeInSeconds: plate.requestTime.toUtc().millisecondsSinceEpoch ~/ 1000,
        basicStandard: plate.basicStandard ?? 0,
        basicAmount: plate.basicAmount ?? 0,
        addStandard: plate.addStandard ?? 0,
        addAmount: plate.addAmount ?? 0,
      ),
    );

    if (shouldSettle == null) return;

    if (shouldSettle == true) {
      final now = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000;
      final entryTime = plate.requestTime.toUtc().millisecondsSinceEpoch ~/ 1000;

      final lockedFee = calculateParkingFee(
        entryTimeInSeconds: entryTime,
        currentTimeInSeconds: now,
        basicStandard: plate.basicStandard ?? 0,
        basicAmount: plate.basicAmount ?? 0,
        addStandard: plate.addStandard ?? 0,
        addAmount: plate.addAmount ?? 0,
      ).round();

      updatedPlate = plate.copyWith(
        isLockedFee: true,
        lockedAtTimeInSeconds: now,
        lockedFeeAmount: lockedFee,
      );
    }
  }

  try {
    await movementPlate.jumpingDepartureCompleted(updatedPlate);
  } catch (e) {
    debugPrint("출차 완료 실패: $e");
  }
}

class _DepartureSettlementConfirmDialog extends StatelessWidget {
  final int entryTimeInSeconds;
  final int basicStandard;
  final int basicAmount;
  final int addStandard;
  final int addAmount;

  const _DepartureSettlementConfirmDialog({
    required this.entryTimeInSeconds,
    required this.basicStandard,
    required this.basicAmount,
    required this.addStandard,
    required this.addAmount,
  });

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final currentTimeInSeconds = now.toUtc().millisecondsSinceEpoch ~/ 1000;
    final formattedNow = DateFormat('yyyy-MM-dd HH:mm:ss').format(now);

    final fee = calculateParkingFee(
      entryTimeInSeconds: entryTimeInSeconds,
      currentTimeInSeconds: currentTimeInSeconds,
      basicStandard: basicStandard,
      basicAmount: basicAmount,
      addStandard: addStandard,
      addAmount: addAmount,
    ).round();

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: const [
          Icon(Icons.attach_money, color: Colors.green, size: 28),
          SizedBox(width: 8),
          Text('정산 확인', style: TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('출차 시각: $formattedNow', style: const TextStyle(fontSize: 16)),
          const SizedBox(height: 8),
          Text('예상 정산 금액: ₩$fee', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const SizedBox(height: 16),
          const Text(
            '지금 정산하시겠습니까?\n정산하지 않으면 요금이 계속 증가합니다.',
            style: TextStyle(fontSize: 14),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, null),
          child: const Text('출차 취소'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('아니요'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('예'),
        ),
      ],
    );
  }
}
