import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../states/plate_state.dart';
import '../../utils/show_snackbar.dart';

class ParkingCompletedStatusDialog extends StatelessWidget {
  final VoidCallback onRequestEntry;
  final VoidCallback onCompleteDeparture;
  final VoidCallback onDelete;
  final String plateNumber;
  final String area; // ✅ 지역 정보 추가

  const ParkingCompletedStatusDialog({
    super.key,
    required this.onRequestEntry,
    required this.onCompleteDeparture,
    required this.onDelete,
    required this.plateNumber,
    required this.area, // ✅ 지역 정보 추가
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text("상태 수정"),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ✅ "입차 요청" 버튼 추가
          ListTile(
            title: Text("입차 요청"),
            onTap: () {
              Navigator.of(context).pop(); // 다이얼로그 닫기
              onRequestEntry(); // 입차 요청 실행
            },
          ),
          // ✅ 기존 "출차 완료" 버튼 유지
          ListTile(
            title: Text("출차 완료"),
            onTap: () {
              Navigator.of(context).pop();
              onCompleteDeparture();
            },
          ),
          // ✅ 기존 "삭제" 버튼 유지
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

  // 🔹 'parking_completed'에서 'parking_requests'로 plate 이동
  plateState.updatePlateStatus(
    plateNumber: plateNumber,
    area: area,
    fromCollection: 'parking_completed', // 🔹 기존 컬렉션: 입차 완료 목록
    toCollection: 'parking_requests',    // 🔹 이동할 컬렉션: 입차 요청 목록
    newType: '입차 요청',
  );

  // 🔹 location을 '미지정'으로 변경
  plateState.returnParkingRequest(plateNumber, "미지정");

  // ✅ 완료 메시지 표시
  showSnackbar(context, "입차 요청이 완료되었습니다.");
}
