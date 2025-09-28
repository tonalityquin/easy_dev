import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../models/plate_model.dart';
import '../../../../states/plate/movement_plate.dart';

Future<bool?> showTabletPageStatusBottomSheet({
  required BuildContext context,
  required PlateModel plate,
  required Future<void> Function() onRequestEntry, // 시그니처 호환성을 위해 유지(미사용)
  required VoidCallback onDelete,                  // 시그니처 호환성을 위해 유지(미사용)
}) async {
  return showModalBottomSheet<bool>(
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
                    Icon(Icons.directions_car, color: Colors.blueAccent),
                    SizedBox(width: 8),
                    Text(
                      '출차 요청 확인',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),

                const SizedBox(height: 20),

                Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.blueAccent),
                    ),
                    child: Text(
                      plate.plateNumber,
                      style: const TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 4),
                  child: Text(
                    '선택한 차량을 정말 출차 요청으로 변경하시겠습니까?',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 14, color: Colors.black87),
                  ),
                ),

                const SizedBox(height: 28),

                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.close),
                        label: const Text('아니요'),
                        onPressed: () => Navigator.pop(context, false),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(double.infinity, 48),
                          side: const BorderSide(color: Colors.black26),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.exit_to_app),
                        label: const Text('네, 출차 요청'),
                        onPressed: () async {
                          final movementPlate = context.read<MovementPlate>();
                          await movementPlate.setDepartureRequested(
                            plate.plateNumber,
                            plate.area,
                            plate.location,
                          );
                          if (!context.mounted) return;
                          Navigator.pop(context, true);
                        },
                        style: ElevatedButton.styleFrom(
                          minimumSize: const Size(double.infinity, 48),
                          backgroundColor: Colors.blueAccent,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      );
    },
  );
}
