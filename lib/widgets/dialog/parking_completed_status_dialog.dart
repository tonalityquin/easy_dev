import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../states/plate_state.dart';
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

void handleEntryRequest(BuildContext context, String plateNumber, String area) {
  final plateState = context.read<PlateState>();
  plateState.updatePlateStatus(
    plateNumber: plateNumber,
    area: area,
    fromCollection: 'parking_completed',
    toCollection: 'parking_requests',
    newType: '입차 요청',
  );
  plateState.goBackToParkingRequest(plateNumber, "미지정");
  showSnackbar(context, "입차 요청이 완료되었습니다.");
}
