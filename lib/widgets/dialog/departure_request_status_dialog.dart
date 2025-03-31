import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/plate_model.dart';
import '../../screens/input_pages/modify_plate_info.dart';
import '../../screens/logs/plate_log_viewer_page.dart';
import '../../states/plate/movement_plate.dart';
import '../../states/plate/plate_state.dart';
import '../../utils/snackbar_helper.dart';

class DepartureRequestStatusDialog extends StatelessWidget {
  final VoidCallback onRequestEntry;
  final VoidCallback onCompleteEntry;
  final VoidCallback onDelete;
  final String plateNumber;
  final String area;
  final PlateModel plate;


  const DepartureRequestStatusDialog({
    super.key,
    required this.onRequestEntry,
    required this.onCompleteEntry,
    required this.onDelete,
    required this.plateNumber,
    required this.area,
    required this.plate,
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
              Text('출차 요청 상태 처리', style: TextStyle(fontWeight: FontWeight.bold)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ElevatedButton.icon(
                icon: const Icon(Icons.edit_note_outlined),
                label: const Text("정보 수정"),
                onPressed: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ModifyPlateInfo(
                        plate: plate,
                        collectionKey: 'departure_requests',
                      ),
                    ),
                  );
                },
                style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 48)),
              ),
              const SizedBox(height: 8),
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
                icon: const Icon(Icons.check_circle_outline),
                label: const Text("입차 완료 처리"),
                onPressed: () {
                  Navigator.pop(context);
                  onCompleteEntry();
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

class _ScaleTransitionDialogState extends State<ScaleTransitionDialog>
    with SingleTickerProviderStateMixin {
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

//
// ✅ 상태 변경 핸들러들
//

/// 출차 요청 → 입차 요청
void handleEntryParkingRequest(BuildContext context, String plateNumber, String area) {
  final movementPlate = context.read<MovementPlate>();
  final plateState = context.read<PlateState>();

  movementPlate.goBackToParkingRequest(
    fromCollection: 'departure_requests',
    plateNumber: plateNumber,
    area: area,
    plateState: plateState,
    newLocation: "미지정",
  );

  showSuccessSnackbar(context, "입차 요청이 처리되었습니다.");
}

/// 출차 요청 → 입차 완료
void handleEntryParkingCompleted(BuildContext context, String plateNumber, String area, String location) {
  final movementPlate = context.read<MovementPlate>();
  final plateState = context.read<PlateState>();

  movementPlate.moveDepartureToParkingCompleted(
    plateNumber,
    area,
    plateState,
    location,
  );

  showSuccessSnackbar(context, "입차 완료가 처리되었습니다.");
}

/// 출차 요청 → 출차 완료 (사전 정산)
void handlePrePayment(BuildContext context, String plateNumber, String area, String location) {
  final movementPlate = context.read<MovementPlate>();
  final plateState = context.read<PlateState>();

  movementPlate.setDepartureRequested(
    plateNumber,
    area,
    plateState,
    location,
  );

  showSuccessSnackbar(context, "사전 정산이 처리되었습니다.");
}
