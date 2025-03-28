import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../screens/logs/plate_log_viewer_page.dart';
import '../../states/plate/movement_plate.dart';
import '../../states/plate/plate_state.dart';
import '../../utils/show_snackbar.dart';

class DepartureRequestStatusDialog extends StatelessWidget {
  final VoidCallback onRequestEntry;
  final VoidCallback onCompleteEntry;
  final VoidCallback onDelete;
  final String plateNumber;
  final String area;


  const DepartureRequestStatusDialog({
    super.key,
    required this.onRequestEntry,
    required this.onCompleteEntry,
    required this.onDelete,
    required this.plateNumber,
    required this.area,
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text("상태 수정"),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            title: Text("로그 확인"),
            onTap: () {
              Navigator.of(context).pop();
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => PlateLogViewerPage(initialPlateNumber: plateNumber),
                ),
              );
            },
          ),
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
              onCompleteEntry();
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
  final plateState = context.read<PlateState>();

  movementPlate.goBackToParkingRequest(
    fromCollection: 'departure_requests',
    // 🔥 출차 요청에서 입차 요청으로 이동
    plateNumber: plateNumber,
    area: area,
    plateState: plateState,
    newLocation: "미지정", // ❓ 선택적으로 위치 변경 가능
  );

  showSnackbar(context, "입차 요청이 처리되었습니다.");
}

void handleEntryParkingCompleted(BuildContext context, String plateNumber, String area, String location) {
  final movementPlate = context.read<MovementPlate>(); // ✅ MovementPlate 사용
  final plateState = context.read<PlateState>();
  movementPlate.moveDepartureToParkingCompleted(
    plateNumber,
    area,
    plateState,
    location,
  );
  showSnackbar(context, "입차 완료가 처리되었습니다.");
}
