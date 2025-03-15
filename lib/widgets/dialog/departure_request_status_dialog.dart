import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../states/plate/plate_state.dart';
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

void handleEntryRequestFromDeparture(BuildContext context, String plateNumber, String area) {
  final plateState = context.read<PlateState>();
  plateState.updatePlateStatus(
    plateNumber: plateNumber,
    area: area,
    fromCollection: 'departure_requests',
    toCollection: 'parking_requests',
    newType: '입차 요청',
  );
  plateState.goBackToParkingRequest(plateNumber, null);
  showSnackbar(context, "입차 요청이 완료되었습니다.");
}

void handleParkingCompletedFromDeparture(BuildContext context, String plateNumber, String area) {
  final plateState = context.read<PlateState>();
  plateState.updatePlateStatus(
    plateNumber: plateNumber,
    area: area,
    fromCollection: 'departure_requests',
    toCollection: 'parking_completed',
    newType: '입차 완료',
  );
  showSnackbar(context, "입차 완료가 처리되었습니다.");
}
