import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../models/plate_model.dart';
import '../../../../screens/modify_pages/modify_plate_screen.dart';
import '../../../../screens/logs/plate_log_viewer_page.dart';
import '../../../../states/area/area_state.dart';
import '../../../../states/plate/movement_plate.dart';
import '../../../../states/user/user_state.dart';
import '../../../../enums/plate_type.dart';

Future<void> showParkingCompletedStatusBottomSheet({
  required BuildContext context,
  required PlateModel plate,
  required Future<void> Function() onRequestEntry,
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
                  icon: const Icon(Icons.exit_to_app),
                  label: const Text("출차 요청으로 이동"),
                  onPressed: () async {
                    final movementPlate = context.read<MovementPlate>();
                    final performedBy = context.read<UserState>().name;

                    await movementPlate.setDepartureRequested(
                      plate.plateNumber,
                      plate.area,
                      plate.location,
                      performedBy: performedBy,
                    );

                    if (!context.mounted) return;
                    Navigator.pop(context);
                  },
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 52),
                    backgroundColor: Colors.blueAccent,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
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
                  onPressed: () async {
                    final movementPlate = context.read<MovementPlate>();
                    final performedBy = context.read<UserState>().name;

                    await movementPlate.goBackToParkingRequest(
                      fromType: PlateType.parkingCompleted,
                      plateNumber: plate.plateNumber,
                      area: plate.area,
                      newLocation: "미지정",
                      performedBy: performedBy,
                    );

                    if (!context.mounted) return;
                    Navigator.pop(context);
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

Future<void> handleEntryParkingRequest(BuildContext context, String plateNumber, String area) async {
  final movementPlate = context.read<MovementPlate>();
  final performedBy = context.read<UserState>().name;

  await movementPlate.goBackToParkingRequest(
    fromType: PlateType.parkingCompleted,
    plateNumber: plateNumber,
    area: area,
    newLocation: "미지정",
    performedBy: performedBy,
  );
}
