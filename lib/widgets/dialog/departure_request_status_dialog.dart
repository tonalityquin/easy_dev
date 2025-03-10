import 'package:flutter/material.dart';
import 'package:provider/provider.dart'; // ✅ Provider 패키지 추가
import '../../states/plate_state.dart';
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

  // 🔹 'departure_requests'에서 'parking_requests'로 plate 이동 (입차 요청)
  plateState.updatePlateStatus(
    plateNumber: plateNumber,
    area: area,
    fromCollection: 'departure_requests',  // 🔹 기존 컬렉션: 출차 요청 목록
    toCollection: 'parking_requests',      // 🔹 이동할 컬렉션: 입차 요청 목록
    newType: '입차 요청',
  );

  // 🔹 location 값을 초기화 (자동으로 "미지정"이 설정됨)
  plateState.returnParkingRequest(plateNumber, null);

  // ✅ 완료 메시지 표시
  showSnackbar(context, "입차 요청이 완료되었습니다.");
}

void handleParkingCompletedFromDeparture(BuildContext context, String plateNumber, String area) {
  final plateState = context.read<PlateState>();

  // 🔹 'departure_requests'에서 'parking_completed'로 이동
  plateState.updatePlateStatus(
    plateNumber: plateNumber,
    area: area,
    fromCollection: 'departure_requests',  // 🔹 기존 컬렉션: 출차 요청 목록
    toCollection: 'parking_completed',    // 🔹 이동할 컬렉션: 입차 완료 목록
    newType: '입차 완료',
  );

  // 🔹 location을 기존 값으로 유지 (출차 완료 후 동일 위치에 주차될 가능성 고려)
  showSnackbar(context, "입차 완료가 처리되었습니다.");
}
