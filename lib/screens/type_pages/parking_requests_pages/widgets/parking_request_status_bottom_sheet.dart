import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../models/plate_model.dart';
import '../../../../screens/modify_pages/modify_plate_screen.dart';
import '../../../../screens/logs/plate_log_viewer_page.dart';
import '../../../../states/area/area_state.dart';
import '../../../../enums/plate_type.dart';
import '../../../../states/user/user_state.dart';

Future<void> showParkingRequestStatusBottomSheet({
  required BuildContext context,
  required PlateModel plate,
  required VoidCallback onCancelEntryRequest,
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
        initialChildSize: 0.45,
        minChildSize: 0.3,
        maxChildSize: 0.9,
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
                      '입차 요청 상태 처리',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                const SizedBox(height: 24),

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
                          collectionKey: PlateType.parkingRequests,
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
                  label: const Text("입차 요청 취소"),
                  onPressed: () {
                    Navigator.pop(context);
                    onCancelEntryRequest();
                  },
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 52),
                    backgroundColor: Colors.redAccent,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      );
    },
  );
}

