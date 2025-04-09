import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../models/plate_model.dart';
import '../../screens/modify_pages/modify_3_digit.dart';
import '../../screens/logs/plate_log_viewer_page.dart';
import '../../states/plate/movement_plate.dart';
import '../../states/plate/plate_state.dart';
import '../../utils/fee_calculator.dart';

class ParkingCompletedStatusDialog extends StatelessWidget {
  final VoidCallback onRequestEntry;
  final VoidCallback onDelete;
  final String plateNumber;
  final String area;
  final PlateModel plate;

  const ParkingCompletedStatusDialog({
    super.key,
    required this.plate,
    required this.onRequestEntry,
    required this.onDelete,
    required this.plateNumber,
    required this.area,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ScaleTransitionDialog(
        child: AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: const [
              Icon(Icons.settings, color: Colors.blueAccent),
              SizedBox(width: 8),
              Text('입차 완료 상태 처리', style: TextStyle(fontWeight: FontWeight.bold)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ElevatedButton.icon(
                icon: const Icon(Icons.history),
                label: const Text("로그 확인"),
                onPressed: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => PlateLogViewerPage(initialPlateNumber: plateNumber),
                    ),
                  );
                },
                style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 48)),
              ),
              const SizedBox(height: 8),
              ElevatedButton.icon(
                icon: const Icon(Icons.edit_note_outlined),
                label: const Text("정보 수정"),
                onPressed: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => Modify3Digit(
                        plate: plate,
                        collectionKey: 'parking_completed',
                      ),
                    ),
                  );
                },
                style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 48)),
              ),
              const SizedBox(height: 8),
              ElevatedButton.icon(
                icon: const Icon(Icons.assignment_return),
                label: const Text("입차 요청으로 되돌리기"),
                onPressed: () {
                  Navigator.pop(context);
                  onRequestEntry();
                },
                style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 48)),
              ),
              const SizedBox(height: 8),
              ElevatedButton.icon(
                icon: const Icon(Icons.exit_to_app),
                label: const Text("출차 완료 처리"),
                onPressed: () async {
                  Navigator.pop(context);
                  await Future.delayed(Duration.zero);
                  if (context.mounted) {
                    handleEntryDepartureCompleted(context, plate);
                  }
                },
                style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 48)),
              ),
              const SizedBox(height: 8),
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
        ),
      ),
    );
  }
}

class ScaleTransitionDialog extends StatefulWidget {
  final Widget child;

  const ScaleTransitionDialog({super.key, required this.child});

  @override
  State<ScaleTransitionDialog> createState() => _ScaleTransitionDialogState();
}

class _ScaleTransitionDialogState extends State<ScaleTransitionDialog> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 250),
      vsync: this,
    );
    _scaleAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutBack,
    );
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _scaleAnimation,
      child: widget.child,
    );
  }
}

void handleEntryParkingRequest(BuildContext context, String plateNumber, String area) {
  final movementPlate = context.read<MovementPlate>();
  final plateState = context.read<PlateState>();

  movementPlate.goBackToParkingRequest(
    fromCollection: 'parking_completed',
    plateNumber: plateNumber,
    area: area,
    plateState: plateState,
    newLocation: "미지정",
  );
}

void handleEntryDepartureCompleted(BuildContext context, PlateModel plate) async {
  final movementPlate = context.read<MovementPlate>();
  final plateState = context.read<PlateState>();

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

    if (shouldSettle == null) {
      return;
    }
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
    await movementPlate.doubleParkingCompletedToDepartureCompletedWithPlate(
      updatedPlate,
      plateState,
    );
  } catch (e) {
    debugPrint("출차 완료 실패: $e");
  }
}

void handlePrePayment(BuildContext context, String plateNumber, String area, String location) {
  final movementPlate = context.read<MovementPlate>();
  final plateState = context.read<PlateState>();

  movementPlate.setDepartureRequested(
    plateNumber,
    area,
    plateState,
    location,
  );
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
