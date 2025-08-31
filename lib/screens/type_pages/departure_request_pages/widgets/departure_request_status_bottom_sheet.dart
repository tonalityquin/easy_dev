import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../models/plate_model.dart';
import '../../../../screens/modify_pages/modify_plate_screen.dart';
import '../../../../screens/logs/plate_log_viewer_page.dart';
import '../../../../states/plate/movement_plate.dart';
import '../../../../states/user/user_state.dart';
import '../../../../utils/snackbar_helper.dart';
import '../../../../enums/plate_type.dart';

Future<void> showDepartureRequestStatusBottomSheet({
  required BuildContext context,
  required PlateModel plate,
  required VoidCallback onRequestEntry,
  required VoidCallback onCompleteEntry,
  required VoidCallback onDelete,
}) async {
  final plateNumber = plate.plateNumber;
  final area = plate.area;
  final division = context.read<UserState>().division;

  // 바깥 컨텍스트를 캡처하여 pop 뒤 push 시 안전하게 사용
  final rootContext = context;

  // ✅ 하얀색 배경 버튼 공통 스타일
  ButtonStyle _whiteSheetButtonStyle(BuildContext ctx) => ElevatedButton.styleFrom(
    minimumSize: const Size(double.infinity, 52),
    backgroundColor: Colors.white,
    foregroundColor: Colors.black87,
    elevation: 0,
    side: BorderSide(color: Theme.of(ctx).dividerColor),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
  );

  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (modalCtx) {
      return DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        builder: (sheetCtx, scrollController) {
          return SafeArea(
            top: false, // 상단 라운드 유지
            child: Container(
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
                  Row(
                    children: const [
                      Icon(Icons.settings, color: Colors.blueAccent),
                      SizedBox(width: 8),
                      Text(
                        '출차 요청 상태 처리',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // 정보 수정 (하얀색 배경)
                  ElevatedButton.icon(
                    icon: const Icon(Icons.edit_note_outlined),
                    label: const Text("정보 수정"),
                    onPressed: () {
                      Navigator.pop(sheetCtx); // 시트 닫기
                      Future.microtask(() {
                        if (!rootContext.mounted) return;
                        Navigator.push(
                          rootContext,
                          MaterialPageRoute(
                            builder: (_) => ModifyPlateScreen(
                              plate: plate,
                              collectionKey: PlateType.departureRequests,
                            ),
                          ),
                        );
                      });
                    },
                    style: _whiteSheetButtonStyle(sheetCtx),
                  ),
                  const SizedBox(height: 12),

                  // 로그 확인 (하얀색 배경)
                  ElevatedButton.icon(
                    icon: const Icon(Icons.history),
                    label: const Text("로그 확인"),
                    onPressed: () {
                      Navigator.pop(sheetCtx); // 시트 닫기
                      Future.microtask(() {
                        if (!rootContext.mounted) return;
                        Navigator.push(
                          rootContext,
                          MaterialPageRoute(
                            builder: (_) => PlateLogViewerBottomSheet(
                              initialPlateNumber: plateNumber,
                              division: division,
                              area: area,
                              requestTime: plate.requestTime,
                            ),
                          ),
                        );
                      });
                    },
                    style: _whiteSheetButtonStyle(sheetCtx),
                  ),
                  const SizedBox(height: 12),

                  // 입차 요청으로 되돌리기
                  ElevatedButton.icon(
                    icon: const Icon(Icons.assignment_return),
                    label: const Text("입차 요청으로 되돌리기"),
                    onPressed: () {
                      Navigator.pop(sheetCtx);
                      Future.microtask(onRequestEntry);
                    },
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 52),
                      backgroundColor: Colors.orange.shade400,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // 입차 완료 처리
                  ElevatedButton.icon(
                    icon: const Icon(Icons.check_circle_outline),
                    label: const Text("입차 완료 처리"),
                    onPressed: () {
                      Navigator.pop(sheetCtx);
                      Future.microtask(onCompleteEntry);
                    },
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 52),
                      backgroundColor: Colors.green.shade600,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // 삭제
                  TextButton.icon(
                    icon: const Icon(Icons.delete_forever, color: Colors.red),
                    label: const Text("삭제", style: TextStyle(color: Colors.red)),
                    onPressed: () {
                      Navigator.pop(sheetCtx);
                      Future.microtask(onDelete);
                    },
                  ),
                ],
              ),
            ),
          );
        },
      );
    },
  );
}

Future<void> handleEntryParkingRequest(
    BuildContext context,
    String plateNumber,
    String area,
    ) async {
  final movementPlate = context.read<MovementPlate>();
  final performedBy = context.read<UserState>().name;

  try {
    await movementPlate.goBackToParkingRequest(
      fromType: PlateType.departureRequests,
      plateNumber: plateNumber,
      area: area,
      newLocation: "미지정",
      performedBy: performedBy,
    );
    if (context.mounted) {
      showSuccessSnackbar(context, "입차 요청이 처리되었습니다.");
    }
  } catch (e) {
    if (context.mounted) {
      showFailedSnackbar(context, "입차 요청 처리 중 오류: $e");
    }
  }
}

Future<void> handleEntryParkingCompleted(
    BuildContext context,
    String plateNumber,
    String area,
    String location,
    ) async {
  final movementPlate = context.read<MovementPlate>();

  try {
    await movementPlate.goBackToParkingCompleted(
      plateNumber,
      area,
      location,
    );
    if (context.mounted) {
      showSuccessSnackbar(context, "입차 완료가 처리되었습니다.");
    }
  } catch (e) {
    if (context.mounted) {
      showFailedSnackbar(context, "입차 완료 처리 중 오류: $e");
    }
  }
}
