import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../states/plate/movement_plate.dart';
import '../../utils/show_snackbar.dart';

class DepartureRequestStatusDialog extends StatelessWidget {
  final VoidCallback onRequestEntry;
  final VoidCallback onCompleteDeparture;
  final VoidCallback onDelete;

  const DepartureRequestStatusDialog({
    super.key,
    required this.onRequestEntry,
    required this.onCompleteDeparture,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text("상태 수정"),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            title: const Text("입차 요청"),
            onTap: () {
              Navigator.pop(context);
              onRequestEntry();
            },
          ),
          ListTile(
            title: const Text("입차 완료"),
            onTap: () {
              Navigator.pop(context);
              onCompleteDeparture();
            },
          ),
          ListTile(
            title: const Text("삭제"),
            onTap: () {
              Navigator.pop(context);
              onDelete();
            },
          ),
        ],
      ),
    );
  }
}

void handleEntryParkingRequest(BuildContext context, String plateNumber, String area) {
  final movementPlate = context.read<MovementPlate>(); // ✅ MovementPlate 사용

  movementPlate.goBackToParkingRequest(
    fromCollection: 'departure_requests', // 🔥 출차 요청에서 입차 요청으로 이동
    plateNumber: plateNumber,
    area: area,
    newLocation: "미지정", // ❓ 선택적으로 위치 변경 가능
  );

  showSnackbar(context, "입차 요청이 처리되었습니다.");
}



void handleEntryParkingCompleted(BuildContext context, String plateNumber, String area) {
  final movementPlate = context.read<MovementPlate>(); // ✅ MovementPlate 사용
  movementPlate.updatePlateStatus(
    plateNumber: plateNumber,
    area: area,
    fromCollection: 'departure_requests',
    toCollection: 'parking_completed',
    newType: '입차 완료',
  );
  showSnackbar(context, "입차 완료가 처리되었습니다.");
}
