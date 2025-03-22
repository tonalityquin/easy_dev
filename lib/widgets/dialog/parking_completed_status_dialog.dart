import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../states/plate/movement_plate.dart';
import '../../states/plate/plate_state.dart';
import '../../utils/show_snackbar.dart';

class ParkingCompletedStatusDialog extends StatelessWidget {
  final VoidCallback onRequestEntry;
  final VoidCallback onCompleteDeparture;
  final VoidCallback onDelete;
  final String plateNumber;
  final String area;

  const ParkingCompletedStatusDialog({
    super.key,
    required this.onRequestEntry,
    required this.onCompleteDeparture,
    required this.onDelete,
    required this.plateNumber,
    required this.area,
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text("상태 수정"),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            title: Text("입차 요청"),
            onTap: () {
              Navigator.of(context).pop();
              onRequestEntry();
            },
          ),
          ListTile(
            title: Text("출차 완료"),
            onTap: () {
              Navigator.of(context).pop();
              onCompleteDeparture();
            },
          ),
          ListTile(
            title: Text("삭제"),
            onTap: () {
              Navigator.of(context).pop();
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
  final plateState = context.read<PlateState>();

  movementPlate.goBackToParkingRequest(
    fromCollection: 'parking_completed',
    // 🔥 어디서 이동하는지 명시
    plateNumber: plateNumber,
    area: area,
    plateState: plateState,
    newLocation: "미지정", // ❓ 선택적으로 위치 변경 가능
  );

  showSnackbar(context, "입차 요청이 처리되었습니다.");
}

void handleEntryDepartureCompleted(BuildContext context, String plateNumber, String area) {
  final movementPlate = context.read<MovementPlate>(); // ✅ MovementPlate 사용
  final plateState = context.read<PlateState>();
  movementPlate.setDepartureCompleted(
    plateNumber,
    area,
    plateState,
  );
  showSnackbar(context, "출차 완료가 처리되었습니다.");
}
